// Agent usage: Omarchy's Agents bar widget as a GNOME Shell top-bar panel.
//
// The panel itself is panel.js, shared with the Cinnamon applet. This is
// GNOME's side of it: the button in the top bar, the menu that holds the
// panel, and the host the panel calls back into.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';

import {PanelController} from './panel.js';

// GNOME 46 to 49 open a top-bar menu in PanelMenu.Button's vfunc_event; 50
// with a click gesture instead, and has no vfunc_event to hand events on to.
const OPENS_IN_VFUNC_EVENT = Object.hasOwn(PanelMenu.Button.prototype, 'vfunc_event');

function setStyleClass(actor, name, on) {
    if (on)
        actor.add_style_class_name(name);
    else
        actor.remove_style_class_name(name);
}

const Indicator = GObject.registerClass(
class AgentUsageIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.5, 'Agent usage', false);
        // GNOME 50's gesture takes any button, before vfunc_event sees it;
        // the middle and right ones are the indicator's own.
        this._clickGesture?.set_required_button(Clutter.BUTTON_PRIMARY);

        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        this._icon = new St.Icon({
            gicon: Gio.icon_new_for_string(`${extension.path}/icons/agent-usage-symbolic.svg`),
            style_class: 'system-status-icon',
        });
        this._label = new St.Label({text: '', style_class: 'agent-usage-panel-label', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._icon);
        box.add_child(this._label);
        this.add_child(box);

        this._settings = extension.getSettings();
        this._controller = new PanelController({
            path: extension.path,
            settings: this._settings,
            installedVersion: extension.metadata['version-name'] ?? '',
            host: {
                showTopBar: state => this._showTopBar(state),
                closeMenu: () => this.menu.close(),
                isMenuOpen: () => this.menu.isOpen,
                keepFocus: () => this._keepFocus(),
                scrollToTop: () => {
                    if (this._scroll.vadjustment)
                        this._scroll.vadjustment.value = 0;
                },
                openSettings: () => extension.openPreferences(),
                // The settings window has the Update button.
                openUpdate: () => extension.openPreferences(),
                quitPrompt: () => 'Switch Agent Usage off? It stays off, also after you log in again, until you switch it back on in the Extensions app.',
                quit: () => this._switchOff(extension.uuid),
                notify: text => Main.notify('Agent usage', text),
                openApp: desktopId => this._openApp(desktopId),
                spawn: argv => Util.spawn(argv),
            },
        });

        this.menu.actor.add_style_class_name('agent-usage-menu');
        // Takes the panel's full height when it fits, and only scrolls once the
        // menu reaches the max-height GNOME sets to keep it on screen.
        this._scroll = new St.ScrollView({
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
            clip_to_allocation: true,
            child: this._controller.actor,
        });
        this.menu.box.add_child(this._scroll);
        this.menu.connect('open-state-changed', (_menu, open) => this._controller.onMenuOpenChanged(open));
        // Capture keys before GNOME's own handler, which would otherwise move
        // ←/→ to the neighbouring top-bar menu.
        this.menu.actor.connect('captured-event', (_actor, event) => this._onMenuKey(event));

        this.connect('destroy', () => this._controller.destroy());
        this._controller.start();
    }

    // Left click opens the panel (PanelMenu.Button), middle click refreshes,
    // right click opens the agent: the same as Omarchy's bar icon. With that
    // switched off, right click opens the panel too.
    vfunc_event(event) {
        if (event.type() === Clutter.EventType.BUTTON_PRESS) {
            const button = event.get_button();
            if (button === Clutter.BUTTON_MIDDLE) {
                this._controller.refresh();
                return Clutter.EVENT_STOP;
            }
            if (button === Clutter.BUTTON_SECONDARY) {
                if (this._settings.get_boolean('right-click-opens-agent')) {
                    this.menu.close();
                    this._controller.launchAgent();
                } else {
                    this.menu.toggle();
                }
                return Clutter.EVENT_STOP;
            }
        }
        return OPENS_IN_VFUNC_EVENT ? super.vfunc_event(event) : Clutter.EVENT_PROPAGATE;
    }

    _onMenuKey(event) {
        if (event.type() !== Clutter.EventType.KEY_PRESS)
            return Clutter.EVENT_PROPAGATE;
        return this._controller.handleKey(event.get_key_symbol()) ? Clutter.EVENT_STOP : Clutter.EVENT_PROPAGATE;
    }

    // Nothing to report, nothing in the top bar: the icon appears the moment
    // the first scan finds usage, or a session wants you.
    _showTopBar({hasUsage, text, alarming, stale, session}) {
        this.visible = hasUsage || session !== null;
        this._label.text = text;
        this._label.visible = text !== '';
        // The robot says what the sessions want; red stays with the number.
        setStyleClass(this._icon, 'agent-usage-waiting', session === 'waiting');
        setStyleClass(this._icon, 'agent-usage-ready', session === 'ready');
        setStyleClass(this._icon, 'agent-usage-alarm', alarming && session === null);
        setStyleClass(this._label, 'agent-usage-alarm', alarming);
        this._label.opacity = stale ? 140 : 255;
    }

    _keepFocus() {
        if (!this.menu.isOpen)
            return;
        const focus = global.stage.get_key_focus();
        if (!focus || !this.menu.actor.contains(focus))
            this.menu.actor.grab_key_focus();
    }

    // Brings the app forward when it's already open, and starts it otherwise.
    _openApp(desktopId) {
        const app = Shell.AppSystem.get_default().lookup_app(desktopId);
        if (app)
            app.activate();
        else
            Main.notify('Agent usage', `Couldn't open ${desktopId}.`);
    }

    // ⏻ in the panel: switched off as the Extensions app would, which
    // destroys this button, so only once the click is done.
    _switchOff(uuid) {
        Main.notify('Agent usage', `Switched off. To switch it back on: the Extensions app, or gnome-extensions enable ${uuid}`);
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            Main.extensionManager.disableExtension(uuid);
            return GLib.SOURCE_REMOVE;
        });
    }
});

export default class AgentUsageExtension extends Extension {
    enable() {
        this._indicator = new Indicator(this);
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
