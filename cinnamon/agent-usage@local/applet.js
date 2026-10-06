// Agent usage for Cinnamon: Omarchy's Agents panel as a Cinnamon panel
// applet.
//
// The panel itself is panel.js, shared with the GNOME extension and rewritten
// for Cinnamon's module system when the applet is built
// (cinnamon/esm-to-cinnamon.py). This is Cinnamon's side of it: the applet in
// the panel, the popup that holds the panel, the settings, and the host the
// panel calls back into.

const Applet = imports.ui.applet;
const Main = imports.ui.main;
const PopupMenu = imports.ui.popupMenu;
const Settings = imports.ui.settings;
const Util = imports.misc.util;
const Cinnamon = imports.gi.Cinnamon;
const Clutter = imports.gi.Clutter;
const Gio = imports.gi.Gio;
const St = imports.gi.St;

// Cinnamon 6.8 imports an applet's own modules through its extension
// object; 6.0 to 6.6 through require().
function load(name) {
    const me = imports.ui.extension.getCurrentExtension?.();
    return me?.imports ? me.imports[name] : require(`./${name}`);
}

const {PanelController} = load('panel');
const Terminals = load('terminals');

const TERMINAL_SCHEMA = 'org.cinnamon.desktop.default-applications.terminal';

// The panel reads its settings the way Gio.Settings offers them (GNOME's);
// Cinnamon's applet settings get the same face.
function settingsAdapter(settings) {
    return {
        get_int: key => Math.round(Number(settings.getValue(key))) || 0,
        get_string: key => String(settings.getValue(key) ?? ''),
        get_boolean: key => settings.getValue(key) === true,
        connect: (signal, callback) => settings.connect(signal, () => callback()),
        disconnect: id => settings.disconnect(id),
    };
}

class AgentUsageApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);
        this._path = metadata.path;
        this._topBar = {text: '', alarming: false, stale: false};
        this._terminalSettings = undefined;

        this.setAllowedLayout(Applet.AllowedLayout.BOTH);
        // A vertical panel has no room for the percentage; the robot stays.
        this.set_show_label_in_vertical_panels(false);
        this.set_applet_icon_symbolic_path(`${this._path}/icons/agent-usage-symbolic.svg`);
        this.set_applet_label('');
        this.set_applet_tooltip('Agent usage');

        this._settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
        this._listChoices();

        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        this.menu.actor.add_style_class_name('agent-usage-menu');

        this._controller = new PanelController({
            path: this._path,
            settings: settingsAdapter(this._settings),
            installedVersion: metadata.version ?? '',
            host: {
                showTopBar: state => this._showTopBar(state),
                closeMenu: () => this.menu.close(),
                isMenuOpen: () => this.menu.isOpen,
                keepFocus: () => this._keepFocus(),
                scrollToTop: () => {
                    const adjustment = this._scroll.get_vscroll_bar()?.get_adjustment();
                    if (adjustment)
                        adjustment.value = 0;
                },
                openSettings: () => this.configureApplet(),
                openUpdate: () => this.updateNow(),
                notify: text => Main.notify('Agent usage', text),
                openApp: desktopId => this._openApp(desktopId),
                spawn: argv => Util.spawn(argv),
                preferredTerminal: () => this._preferredTerminal(),
            },
        });

        // Takes the panel's full height when it fits, and only scrolls once the
        // menu reaches the max-height Cinnamon sets to keep it on screen.
        this._scroll = new St.ScrollView({
            style_class: 'agent-usage-scroll',
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
            clip_to_allocation: true,
        });
        this._scroll.add_actor(this._controller.actor);
        this.menu.box.add_child(this._scroll);
        this.menu.connect('open-state-changed', (_menu, open) => this._controller.onMenuOpenChanged(open));
        // Capture keys before the menu's own handler, which would otherwise
        // use ←/→ for its items.
        this.menu.actor.connect('captured-event', (_actor, event) => this._onMenuKey(event));

        // Cinnamon keeps applets running while the screen is locked; the
        // panel pauses until it's unlocked.
        this._lockSubscription = Gio.DBus.session.signal_subscribe(
            null, 'org.cinnamon.ScreenSaver', 'ActiveChanged', '/org/cinnamon/ScreenSaver', null,
            Gio.DBusSignalFlags.NONE,
            (_connection, _sender, _path, _iface, _signal, params) => {
                const [active] = params.deep_unpack();
                this._controller.setLocked(active);
            });

        this._controller.start();
    }

    on_applet_clicked() {
        this.menu.toggle();
    }

    on_applet_middle_clicked() {
        this._controller.refresh();
    }

    // Right click opens the agent, as on GNOME and macOS. In panel edit mode
    // it shows Cinnamon's own applet menu, so the applet can still be moved,
    // configured or removed.
    _onButtonPressEvent(actor, event) {
        if (event.get_button() === 3 && this._applet_enabled && !global.settings.get_boolean('panel-edit-mode')) {
            this.menu.close();
            this._controller.launchAgent();
            return Clutter.EVENT_STOP;
        }
        return super._onButtonPressEvent(actor, event);
    }

    // Cinnamon resets the icon's style classes when the panel changes height.
    on_panel_height_changed() {
        this._styleAlarm();
    }

    on_applet_removed_from_panel() {
        if (this._lockSubscription) {
            Gio.DBus.session.signal_unsubscribe(this._lockSubscription);
            this._lockSubscription = 0;
        }
        this._controller.destroy();
        this._settings.finalize();
        this.menu.destroy();
    }

    // The settings window's "Try it" button: exactly what the panel's open
    // button and a right click do.
    tryLaunch() {
        this._controller.launchAgent();
    }

    // "Update now" in the settings, and "vX.Y.Z available" in the panel:
    // `agent-usage update` in the chosen terminal, which waits for Enter at
    // the end. The installer reloads the applet, so nothing needs restarting.
    updateNow() {
        const sourceDir = this._controller.sourceDir;
        if (!sourceDir) {
            Main.notify('Agent usage', "This copy wasn't installed from git, so it can't update itself. Reinstall it with get.sh (see the README).");
            return;
        }
        const terminal = Terminals.terminalArgv(this._controller.launchSettings(), [`${sourceDir}/bin/agent-usage`, 'update', '--pause']);
        if (terminal.error) {
            Main.notify('Agent usage', terminal.error);
            return;
        }
        Util.spawn(terminal.argv);
    }

    _onMenuKey(event) {
        if (event.type() !== Clutter.EventType.KEY_PRESS)
            return Clutter.EVENT_PROPAGATE;
        return this._controller.handleKey(event.get_key_symbol()) ? Clutter.EVENT_STOP : Clutter.EVENT_PROPAGATE;
    }

    // Unlike on GNOME, the robot stays in the panel without usage to show:
    // the installer put it there, and the open panel says why it's empty.
    _showTopBar(state) {
        this._topBar = state;
        this.set_applet_label(state.text);
        this._applet_label.opacity = state.stale ? 140 : 255;
        this._styleAlarm();
    }

    _styleAlarm() {
        for (const actor of [this._applet_icon, this._applet_label]) {
            if (!actor)
                continue;
            if (this._topBar.alarming)
                actor.add_style_class_name('agent-usage-alarm');
            else
                actor.remove_style_class_name('agent-usage-alarm');
        }
    }

    // Rebuilding the panel destroys whatever had keyboard focus; hand it back
    // to the menu so ←/→ and r keep working while it's open.
    _keepFocus() {
        if (!this.menu.isOpen)
            return;
        const focus = global.stage.get_key_focus();
        if (!focus || !this.menu.actor.contains(focus))
            this.menu.actor.grab_key_focus();
    }

    // Brings the app forward when it's already open, and starts it otherwise.
    _openApp(desktopId) {
        const app = Cinnamon.AppSystem.get_default().lookup_app(desktopId);
        if (app)
            app.activate();
        else
            Main.notify('Agent usage', `Couldn't open ${desktopId}.`);
    }

    // "Automatic" tries the terminal from System Settings → Preferred
    // Applications first.
    _preferredTerminal() {
        if (this._terminalSettings === undefined) {
            const found = Gio.SettingsSchemaSource.get_default()?.lookup(TERMINAL_SCHEMA, true);
            this._terminalSettings = found ? new Gio.Settings({schema_id: TERMINAL_SCHEMA}) : null;
        }
        if (!this._terminalSettings)
            return null;
        return Terminals.preferredTerminal(this._terminalSettings.get_string('exec'), this._terminalSettings.get_string('exec-arg'));
    }

    // The settings window lists every agent and the installed terminals,
    // marking the ones this machine doesn't have, as GNOME's does.
    _listChoices() {
        const agents = {};
        for (const agent of Terminals.AGENTS)
            agents[Terminals.agentInstalled(agent) ? agent.name : `${agent.name} (not installed)`] = agent.id;
        agents['Custom…'] = 'custom';

        // The installed terminals, plus the current choice if it has since
        // been uninstalled, so the list can still show it.
        const installed = Terminals.installedTerminals();
        const current = this._settings.getValue('terminal');
        const terminals = {Automatic: 'auto'};
        for (const terminal of Terminals.TERMINALS) {
            if (installed.includes(terminal))
                terminals[terminal.name] = terminal.id;
            else if (terminal.id === current)
                terminals[`${terminal.name} (not installed)`] = terminal.id;
        }
        terminals['Custom…'] = 'custom';

        for (const [key, options] of [['agent', agents], ['terminal', terminals]]) {
            if (JSON.stringify(this._settings.getOptions(key)) !== JSON.stringify(options))
                this._settings.setOptions(key, options);
        }
    }
}

function main(metadata, orientation, panelHeight, instanceId) {
    return new AgentUsageApplet(metadata, orientation, panelHeight, instanceId);
}
