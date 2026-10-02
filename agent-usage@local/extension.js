// Agent usage: Omarchy's Agents bar widget as a GNOME Shell top-bar panel.
//
// Like the original, this is only a display. bin/agent-usage-update runs one
// collector per agent and writes a JSON record per agent to
// ~/.local/state/omarchy/agents/usage/; the panel watches that folder and
// draws whatever is there.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';

import * as Terminals from './terminals.js';
import {UpdateQueue, updateArgv} from './updates.js';
import * as Usage from './usage.js';
import {isNewer} from './versions.js';

const RETRY_SECONDS = 30;
const TICK_SECONDS = 30;
// After waking from sleep, give the network a moment before checking.
const WAKE_DELAY_SECONDS = 5;
// New releases: once a day, starting a minute after login.
const RELEASE_CHECK_SECONDS = 24 * 3600;
const FIRST_RELEASE_CHECK_SECONDS = 60;
const LAUNCH_KEYS = ['agent', 'agent-command', 'terminal', 'terminal-command'];

// Kanagawa, as Omarchy draws it. The bars are painted with Cairo, so they
// take their colors from here; everything else is in stylesheet.css.
const FOREGROUND = [220 / 255, 215 / 255, 186 / 255];
const URGENT = [195 / 255, 64 / 255, 67 / 255];

function roundedRect(cr, x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    if (r <= 0) {
        cr.rectangle(x, y, width, height);
        return;
    }
    cr.newSubPath();
    cr.arc(x + width - r, y + r, r, -Math.PI / 2, 0);
    cr.arc(x + width - r, y + height - r, r, 0, Math.PI / 2);
    cr.arc(x + r, y + height - r, r, Math.PI / 2, Math.PI);
    cr.arc(x + r, y + r, r, Math.PI, 1.5 * Math.PI);
    cr.closePath();
}

// A track with a fill: the limit meters, the day bars, and the share bar
// behind each model row. `pill` rounds the ends; the model rows stay square.
const Bar = GObject.registerClass(
class AgentUsageBar extends St.DrawingArea {
    _init({value = 0, alarming = false, fillAlpha = 1, trackAlpha = 0.14, pill = true, styleClass = 'agent-usage-bar', ...props} = {}) {
        super._init({style_class: styleClass, x_expand: true, y_align: Clutter.ActorAlign.CENTER, ...props});
        this._value = Usage.clamp(Number(value) || 0);
        this._color = alarming ? URGENT : FOREGROUND;
        this._fillAlpha = fillAlpha;
        this._trackAlpha = trackAlpha;
        this._pill = pill;
        this.connect('repaint', () => this._paint());
    }

    _paint() {
        const cr = this.get_context();
        const [width, height] = this.get_surface_size();
        const radius = this._pill ? height / 2 : 0;
        roundedRect(cr, 0, 0, width, height, radius);
        cr.setSourceRGBA(...FOREGROUND, this._trackAlpha);
        cr.fill();
        const fill = width * this._value;
        if (fill > 0) {
            roundedRect(cr, 0, 0, fill, height, radius);
            cr.setSourceRGBA(...this._color, this._fillAlpha);
            cr.fill();
        }
        cr.$dispose();
    }
});

function label(text, styleClass, props = {}) {
    return new St.Label({text, style_class: styleClass, y_align: Clutter.ActorAlign.CENTER, ...props});
}

function wrappingLabel(text, styleClass) {
    const widget = label(text, styleClass, {x_expand: true});
    widget.clutter_text.line_wrap = true;
    widget.clutter_text.line_wrap_mode = Pango.WrapMode.WORD_CHAR;
    widget.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
    return widget;
}

function separator() {
    return new St.Widget({style_class: 'agent-usage-separator', x_expand: true});
}

const Indicator = GObject.registerClass(
class AgentUsageIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.5, 'Agent usage', false);

        this._extension = extension;
        this._path = extension.path;
        this._settings = extension.getSettings();
        this._updater = `${extension.path}/bin/agent-usage-update`;
        this._usageDir = `${GLib.get_user_state_dir()}/omarchy/agents/usage`;
        this._records = [];
        this._recordsKey = null;
        this._providers = [];
        this._selectedId = '';
        this._countdowns = [];
        this._footer = null;
        this._hoverText = null;
        this._queue = new UpdateQueue();
        this._cancellable = new Gio.Cancellable();
        this._sources = new Set();
        this._reloadId = 0;
        this._retryId = 0;
        this._tickId = 0;
        this._wakeId = 0;
        this._limitsTimerId = 0;
        this._scanTimerId = 0;
        this._sleepSubscription = 0;
        this._releaseTimerId = 0;
        this._installedVersion = String(extension.metadata['version-name'] ?? '');
        this._sourceDir = this._readSourceDir();
        this._newRelease = null;

        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        this._icon = new St.Icon({
            gicon: Gio.icon_new_for_string(`${this._path}/icons/agent-usage-symbolic.svg`),
            style_class: 'system-status-icon',
        });
        this._label = label('', 'agent-usage-panel-label');
        box.add_child(this._icon);
        box.add_child(this._label);
        this.add_child(box);

        this.menu.actor.add_style_class_name('agent-usage-menu');
        this._panel = new St.BoxLayout({vertical: true, style_class: 'agent-usage-panel'});
        // Takes the panel's full height when it fits, and only scrolls once the
        // menu reaches the max-height GNOME sets to keep it on screen.
        this._scroll = new St.ScrollView({
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
            clip_to_allocation: true,
            child: this._panel,
        });
        this.menu.box.add_child(this._scroll);
        this.menu.connect('open-state-changed', (_menu, open) => this._onOpenChanged(open));
        // Capture keys before GNOME's own handler, which would otherwise move
        // ←/→ to the neighbouring top-bar menu.
        this.menu.actor.connect('captured-event', (_actor, event) => this._onMenuKey(event));

        GLib.mkdir_with_parents(this._usageDir, 0o755);
        this._monitor = Gio.File.new_for_path(this._usageDir).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connect('changed', () => this._scheduleReload());

        this._settingsIds = ['changed::limits-interval', 'changed::scan-interval']
            .map(signal => this._settings.connect(signal, () => this._restartTimers()));
        // The header's "Open …" button names the agent and terminal.
        for (const key of LAUNCH_KEYS)
            this._settingsIds.push(this._settings.connect(`changed::${key}`, () => this._buildPanel()));
        this._settingsIds.push(this._settings.connect('changed::check-updates', () => this._restartReleaseChecks()));

        // logind announces suspend and resume. With lock-on-suspend (Ubuntu's
        // default) GNOME re-enables extensions at unlock, which refreshes too;
        // this covers machines that wake straight to the desktop.
        this._sleepSubscription = Gio.DBus.system.signal_subscribe(
            'org.freedesktop.login1', 'org.freedesktop.login1.Manager', 'PrepareForSleep',
            '/org/freedesktop/login1', null, Gio.DBusSignalFlags.NONE,
            (_connection, _sender, _path, _iface, _signal, params) => {
                const [goingToSleep] = params.deep_unpack();
                if (!goingToSleep)
                    this._onWake();
            });

        this.connect('destroy', () => this._cleanup());

        this._reload();
        this._runUpdate('normal');
        this._restartTimers();
        this._restartReleaseChecks();
    }

    // ------------------------------------------------------------ releases

    // install.sh records the git checkout a git install came from; installs
    // from a tarball have none and never check.
    _readSourceDir() {
        try {
            const [, bytes] = GLib.file_get_contents(`${this._path}/source`);
            const dir = new TextDecoder().decode(bytes).trim();
            return GLib.file_test(`${dir}/bin/agent-usage`, GLib.FileTest.IS_EXECUTABLE) ? dir : null;
        } catch {
            return null;
        }
    }

    _restartReleaseChecks() {
        this._releaseTimerId = this._removeSource(this._releaseTimerId);
        if (!this._sourceDir || !this._settings.get_boolean('check-updates')) {
            this._newRelease = null;
            this._showFooter();
            return;
        }
        this._releaseTimerId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, FIRST_RELEASE_CHECK_SECONDS, () => {
            this._checkForRelease();
            this._sources.delete(this._releaseTimerId);
            this._releaseTimerId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, RELEASE_CHECK_SECONDS, () => {
                this._checkForRelease();
                return GLib.SOURCE_CONTINUE;
            }));
            return GLib.SOURCE_REMOVE;
        }));
    }

    _checkForRelease() {
        let proc;
        try {
            proc = Gio.Subprocess.new([`${this._sourceDir}/bin/agent-usage`, 'latest'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            console.warn(`agent-usage: release check failed: ${e.message}`);
            return;
        }
        proc.communicate_utf8_async(null, this._cancellable, (_proc, result) => {
            try {
                const [, stdout] = proc.communicate_utf8_finish(result);
                if (!proc.get_successful())
                    return;
                const latest = String(stdout || '').trim();
                this._newRelease = isNewer(latest, this._installedVersion) ? latest : null;
                this._showFooter();
            } catch (e) {
                if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    console.warn(`agent-usage: release check failed: ${e.message}`);
            }
        });
    }

    // Two cadences: the cheap limits probe keeps the top-bar percentage live,
    // and the slower full pass rescans transcripts for the token charts.
    _restartTimers() {
        this._limitsTimerId = this._removeSource(this._limitsTimerId);
        this._scanTimerId = this._removeSource(this._scanTimerId);
        const limitsSeconds = Math.max(30, this._settings.get_int('limits-interval'));
        const scanSeconds = 60 * Math.max(5, this._settings.get_int('scan-interval'));
        this._limitsTimerId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, limitsSeconds, () => {
            this._runUpdate('limits');
            return GLib.SOURCE_CONTINUE;
        }));
        this._scanTimerId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, scanSeconds, () => {
            this._runUpdate('normal');
            return GLib.SOURCE_CONTINUE;
        }));
    }

    _onWake() {
        this._wakeId = this._removeSource(this._wakeId);
        this._wakeId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, WAKE_DELAY_SECONDS, () => {
            this._sources.delete(this._wakeId);
            this._wakeId = 0;
            this._runUpdate('normal');
            return GLib.SOURCE_REMOVE;
        }));
    }

    // Left click opens the panel (PanelMenu.Button), middle click refreshes,
    // right click opens the agent: the same as Omarchy's bar icon.
    vfunc_event(event) {
        if (event.type() === Clutter.EventType.BUTTON_PRESS) {
            const button = event.get_button();
            if (button === Clutter.BUTTON_MIDDLE) {
                this._runUpdate('force');
                return Clutter.EVENT_STOP;
            }
            if (button === Clutter.BUTTON_SECONDARY) {
                this.menu.close();
                this._launchAgent();
                return Clutter.EVENT_STOP;
            }
        }
        return super.vfunc_event(event);
    }

    // ------------------------------------------------------------ data

    _addSource(id) {
        this._sources.add(id);
        return id;
    }

    _removeSource(id) {
        if (id) {
            GLib.source_remove(id);
            this._sources.delete(id);
        }
        return 0;
    }

    _scheduleReload() {
        // One update writes several files in quick succession; render once.
        if (this._reloadId)
            return;
        this._reloadId = this._addSource(GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            this._sources.delete(this._reloadId);
            this._reloadId = 0;
            this._reload();
            return GLib.SOURCE_REMOVE;
        }));
    }

    _loadRecords() {
        const dir = Gio.File.new_for_path(this._usageDir);
        const names = [];
        try {
            const enumerator = dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
            let info;
            while ((info = enumerator.next_file(null))) {
                const name = info.get_name();
                if (name.endsWith('.json') && !name.startsWith('.'))
                    names.push(name);
            }
            enumerator.close(null);
        } catch {
            return [];
        }
        const decoder = new TextDecoder();
        const records = [];
        for (const name of names.sort()) {
            try {
                const [, bytes] = dir.get_child(name).load_contents(null);
                const record = JSON.parse(decoder.decode(bytes));
                if (record && typeof record === 'object' && record.id)
                    records.push(record);
            } catch {
                // A record mid-write or malformed: skip it until the next change.
            }
        }
        return records;
    }

    _reload() {
        this._records = this._loadRecords();
        // Every check rewrites the records' timestamps. Only rebuild when
        // something on screen changed, so an open panel doesn't reset under
        // the pointer every few seconds.
        const key = Usage.displayKey(this._records);
        if (key === this._recordsKey) {
            this._showFooter();
        } else {
            this._recordsKey = key;
            this._render();
        }
        this._scheduleRetry();
    }

    _runUpdate(kind, agents = []) {
        const request = this._queue.request(kind, agents);
        if (request)
            this._startUpdate(request);
        else
            this._showFooter();
    }

    _startUpdate(request) {
        const argv = updateArgv(this._updater, request);
        let proc;
        try {
            proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (e) {
            console.error(`agent-usage: could not run ${this._updater}: ${e.message}`);
            this._finishUpdate();
            return;
        }
        this._showFooter();
        proc.communicate_utf8_async(null, this._cancellable, (_proc, result) => {
            try {
                const [, , stderr] = proc.communicate_utf8_finish(result);
                if (stderr && stderr.trim())
                    console.warn(`agent-usage: ${stderr.trim()}`);
            } catch (e) {
                if (e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    return;
                console.error(`agent-usage: ${e.message}`);
            }
            this._finishUpdate();
        });
    }

    _finishUpdate() {
        const next = this._queue.finish();
        this._reload();
        if (next)
            this._startUpdate(next);
    }

    // A collector that could not reach its limits endpoint at all (typically
    // right after login, before the network is up) sets retryAdvised. Rerun
    // just those agents sooner than the regular interval.
    _scheduleRetry() {
        const advising = this._records.filter(record => record.retryAdvised === true).map(record => String(record.id));
        if (advising.length === 0 || this._retryId)
            return;
        this._retryId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, RETRY_SECONDS, () => {
            this._sources.delete(this._retryId);
            this._retryId = 0;
            this._runUpdate('limits', advising);
            return GLib.SOURCE_REMOVE;
        }));
    }

    _launch() {
        return Terminals.resolveLaunch(Terminals.launchSettings(this._settings));
    }

    _launchAgent() {
        const launch = this._launch();
        if (launch.error) {
            Main.notify('Agent usage', launch.error);
            return;
        }
        Util.spawn(launch.argv);
    }

    // ------------------------------------------------------------ menu

    _onOpenChanged(open) {
        if (open) {
            // Opening wants the numbers that go stale on the wire, not another
            // walk over every transcript on disk.
            this._runUpdate('limits');
            this._scrollToTop();
            this._updateCountdowns();
            this._tickId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, TICK_SECONDS, () => {
                this._updateCountdowns();
                return GLib.SOURCE_CONTINUE;
            }));
        } else {
            this._tickId = this._removeSource(this._tickId);
            this._hoverText = null;
            this._showFooter();
        }
    }

    _onMenuKey(event) {
        if (event.type() !== Clutter.EventType.KEY_PRESS)
            return Clutter.EVENT_PROPAGATE;
        const key = event.get_key_symbol();
        if (key === Clutter.KEY_r || key === Clutter.KEY_R) {
            this._runUpdate('force');
            return Clutter.EVENT_STOP;
        }
        if (this._providers.length > 1) {
            if (key === Clutter.KEY_Left || key === Clutter.KEY_h) {
                this._step(-1);
                return Clutter.EVENT_STOP;
            }
            if (key === Clutter.KEY_Right || key === Clutter.KEY_l) {
                this._step(1);
                return Clutter.EVENT_STOP;
            }
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _step(delta) {
        const count = this._providers.length;
        const index = this._providers.findIndex(record => String(record.id) === this._selectedId);
        this._select(this._providers[(((index + delta) % count) + count) % count].id);
    }

    _select(id) {
        this._selectedId = String(id);
        this._buildPanel();
        this._scrollToTop();
    }

    _scrollToTop() {
        if (this._scroll.vadjustment)
            this._scroll.vadjustment.value = 0;
    }

    // ------------------------------------------------------------ view

    _render() {
        this._providers = Usage.visibleProviders(this._records);
        // Nothing to report, nothing in the top bar: the icon appears the moment
        // the first scan finds usage.
        this.visible = this._providers.length > 0;

        const highest = Usage.highestPercent(this._providers);
        this._label.text = highest === null ? '' : `${Math.round(highest * 100)}%`;
        this._label.visible = highest !== null;
        const alarming = this._providers.some(Usage.isAlarming);
        for (const actor of [this._icon, this._label]) {
            if (alarming)
                actor.add_style_class_name('agent-usage-alarm');
            else
                actor.remove_style_class_name('agent-usage-alarm');
        }
        // A percentage from an earlier check fades, so it doesn't pass for live.
        this._label.opacity = this._providers.some(Usage.limitsStale) ? 140 : 255;

        // The selection follows the agent, not its slot, so a second agent's
        // first scan doesn't swap out what you were reading.
        if (!this._providers.some(record => String(record.id) === this._selectedId))
            this._selectedId = this._providers.length > 0 ? String(this._providers[0].id) : '';
        this._buildPanel();
    }

    _buildPanel() {
        this._panel.destroy_all_children();
        this._countdowns = [];
        this._footer = null;
        this._hoverText = null;

        const record = this._providers.find(candidate => String(candidate.id) === this._selectedId);
        if (!record) {
            this._panel.add_child(wrappingLabel("No AI coding subscriptions found.\nAgents show up here once you've used them.", 'agent-usage-empty'));
            return;
        }

        this._panel.add_child(this._hero(record));
        if (this._providers.length > 1)
            this._panel.add_child(this._tabs());

        if (String(record.usageStatusText || '') !== '' && String(record.authHelpText || '') !== '') {
            const card = new St.BoxLayout({style_class: 'agent-usage-status', x_expand: true});
            card.add_child(wrappingLabel(String(record.authHelpText), 'agent-usage-status-text'));
            this._panel.add_child(card);
        }

        const balance = Usage.balanceValue(record.balance);
        const limits = Usage.limitWindows(record);
        if (balance || limits.length > 0)
            this._panel.add_child(separator());
        if (balance)
            this._panel.add_child(this._balanceSection(balance));
        if (limits.length > 0)
            this._panel.add_child(this._limitsSection(limits, record));

        const days = Usage.recentDays(record);
        if (days.length > 0) {
            this._panel.add_child(separator());
            this._panel.add_child(this._daysSection(record, days));
        }

        const today = Usage.todayModelRows(record);
        if (today.length > 0) {
            this._panel.add_child(separator());
            this._panel.add_child(this._modelsSection('TODAY BY MODEL', today, Usage.todayModelDetail));
        }

        const models = Usage.modelRows(record);
        if (models.length > 0) {
            this._panel.add_child(separator());
            this._panel.add_child(this._modelsSection('ALL TIME BY MODEL', models, Usage.modelDetail));
        }

        this._footer = label('', 'agent-usage-footer', {x_expand: true, reactive: true, track_hover: true});
        // With a new release out, the footer says so and opens the settings,
        // where the Update button is.
        this._footer.connect('button-release-event', () => {
            if (!this._newRelease)
                return Clutter.EVENT_PROPAGATE;
            this.menu.close();
            this._extension.openPreferences();
            return Clutter.EVENT_STOP;
        });
        this._panel.add_child(this._footer);
        this._showFooter();
        this._updateCountdowns();
        this._keepFocus();
    }

    // Rebuilding destroys whatever had keyboard focus; hand it back to the
    // menu so ←/→ and r keep working while the panel is open.
    _keepFocus() {
        if (!this.menu.isOpen)
            return;
        const focus = global.stage.get_key_focus();
        if (!focus || !this.menu.actor.contains(focus))
            this.menu.actor.grab_key_focus();
    }

    _logo(id) {
        const file = Gio.File.new_for_path(`${this._path}/icons/${id}.svg`);
        const gicon = file.query_exists(null)
            ? new Gio.FileIcon({file})
            : Gio.icon_new_for_string(`${this._path}/icons/agent-usage-symbolic.svg`);
        return new St.Icon({gicon, style_class: 'agent-usage-logo', y_align: Clutter.ActorAlign.CENTER});
    }

    _action(iconName, accessibleName, callback) {
        const button = new St.Button({
            style_class: 'agent-usage-action',
            can_focus: true,
            track_hover: true,
            accessible_name: accessibleName,
            y_align: Clutter.ActorAlign.CENTER,
            child: new St.Icon({icon_name: iconName, style_class: 'agent-usage-action-icon'}),
        });
        button.connect('clicked', callback);
        this._hover(button, accessibleName);
        return button;
    }

    _hero(record) {
        const hero = new St.BoxLayout({style_class: 'agent-usage-hero', x_expand: true});
        hero.add_child(this._logo(String(record.id)));

        const text = new St.BoxLayout({vertical: true, x_expand: true, y_align: Clutter.ActorAlign.CENTER});
        text.add_child(label(String(record.name || record.id), 'agent-usage-title'));
        text.add_child(label(Usage.heroMeta(record).toUpperCase(), 'agent-usage-meta'));
        hero.add_child(text);

        hero.add_child(this._action('view-refresh-symbolic', 'Refresh now (r)', () => this._runUpdate('force')));
        // Hidden when there is no agent to open; a missing terminal still gets
        // the button, so clicking it says what's wrong.
        const launch = this._launch();
        if (launch.reason !== 'agent') {
            const hint = launch.error ? `Open ${launch.agentName}` : `Open ${launch.agentName} in ${launch.terminalName}`;
            hero.add_child(this._action('utilities-terminal-symbolic', hint, () => {
                this.menu.close();
                this._launchAgent();
            }));
        }
        hero.add_child(this._action('preferences-system-symbolic', 'Settings', () => {
            this.menu.close();
            this._extension.openPreferences();
        }));
        return hero;
    }

    _tabs() {
        const tabs = new St.BoxLayout({style_class: 'agent-usage-tabs', x_expand: true});
        for (const record of this._providers) {
            const tab = new St.Button({
                label: String(record.name || record.id),
                style_class: 'agent-usage-tab',
                x_expand: true,
                can_focus: true,
                track_hover: true,
            });
            if (String(record.id) === this._selectedId)
                tab.add_style_pseudo_class('checked');
            tab.connect('clicked', () => this._select(record.id));
            tabs.add_child(tab);
        }
        return tabs;
    }

    _section(title, {hint = null, stale = false} = {}) {
        const section = new St.BoxLayout({vertical: true, style_class: 'agent-usage-section', x_expand: true});
        const heading = label(title, 'agent-usage-section-title', {reactive: !!hint, track_hover: !!hint});
        if (stale)
            heading.add_style_class_name('agent-usage-stale');
        if (hint)
            this._hover(heading, hint);
        section.add_child(heading);
        return section;
    }

    _valueRow(title, value, alarming) {
        const row = new St.BoxLayout({x_expand: true});
        row.add_child(label(title, 'agent-usage-row-title', {x_expand: true}));
        const valueLabel = label(value, 'agent-usage-row-value');
        if (alarming)
            valueLabel.add_style_class_name('agent-usage-urgent');
        row.add_child(valueLabel);
        return row;
    }

    _balanceSection(balance) {
        const section = this._section('BALANCE');
        const alarming = Usage.balanceAlarming(balance);
        section.add_child(this._valueRow('Prepaid credits', Usage.formatMoney(balance.remaining, balance.currency), alarming));
        // The meter shows what is left: a prepaid account drains toward empty.
        if (balance.funded > 0)
            section.add_child(new Bar({value: balance.remaining / balance.funded, alarming}));
        const detail = Usage.balanceDetail(balance);
        if (detail)
            section.add_child(label(detail, 'agent-usage-caption'));
        return section;
    }

    _limitsSection(limits, record) {
        const stale = Usage.limitsStale(record);
        const section = this._section(Usage.limitsTitle(record), {stale, hint: stale ? Usage.limitsNote(record) : null});
        for (const window of limits) {
            const alarming = window.percent >= Usage.ALARM_RATIO;
            const limit = new St.BoxLayout({vertical: true, style_class: 'agent-usage-limit', x_expand: true});
            limit.add_child(this._valueRow(window.title, `${Math.round(window.percent * 100)}%`, alarming));
            limit.add_child(new Bar({value: window.percent, alarming}));
            const reset = label('', 'agent-usage-caption');
            this._countdowns.push({label: reset, resetMs: window.resetMs});
            limit.add_child(reset);
            section.add_child(limit);
        }
        return section;
    }

    _daysSection(record, days) {
        const section = this._section('TOKENS BY DAY');
        const today = Usage.localDate(Date.now());
        const peak = Math.max(1, ...days.map(day => Usage.number(day.messageCount)));
        for (const day of days) {
            const isToday = String(day.date) === today;
            const row = new St.BoxLayout({style_class: 'agent-usage-day', x_expand: true, reactive: true, track_hover: true});
            if (isToday)
                row.add_style_class_name('agent-usage-today');
            row.add_child(label(isToday ? 'Today' : Usage.dayName(day.date), 'agent-usage-day-label'));
            row.add_child(new Bar({
                value: Usage.number(day.messageCount) / peak,
                fillAlpha: isToday ? 1 : 0.55,
                styleClass: 'agent-usage-bar agent-usage-day-bar',
            }));
            row.add_child(label(Usage.formatTokens(day.messageCount), 'agent-usage-day-value'));
            this._hover(row, Usage.dayDetail(day, isToday, record));
            section.add_child(row);
        }
        return section;
    }

    // One section of model rows: the bar fills behind each row, scaled to the
    // heaviest model so the top row is always full.
    _modelsSection(title, models, detail) {
        const section = this._section(title);
        const heaviest = Math.max(1, models[0].total);
        for (const model of models) {
            const row = new St.Widget({
                layout_manager: new Clutter.BinLayout(),
                style_class: 'agent-usage-model',
                x_expand: true,
                reactive: true,
                track_hover: true,
            });
            row.add_child(new Bar({
                value: model.total / heaviest,
                fillAlpha: 0.14,
                trackAlpha: 0.05,
                pill: false,
                styleClass: 'agent-usage-model-bar',
                y_expand: true,
                y_align: Clutter.ActorAlign.FILL,
            }));
            const content = new St.BoxLayout({style_class: 'agent-usage-model-content', x_expand: true});
            content.add_child(label(model.name, 'agent-usage-model-name', {x_expand: true}));
            content.add_child(label(Usage.formatTokens(model.total), 'agent-usage-model-value'));
            row.add_child(content);
            this._hover(row, detail(model));
            section.add_child(row);
        }
        return section;
    }

    // Omarchy shows details in tooltips; here they take over the footer line
    // while the pointer rests on a row, so the panel never changes size.
    _hover(actor, text) {
        actor.connect('notify::hover', () => {
            this._hoverText = actor.hover ? text : null;
            this._showFooter();
        });
    }

    _showFooter() {
        if (!this._footer)
            return;
        const running = this._queue.running;
        if (this._hoverText) {
            this._footer.text = this._hoverText;
        } else if (running && running.kind !== 'limits') {
            // The quick limits checks run every few seconds; only the slower
            // refreshes are worth calling out.
            this._footer.text = 'Refreshing…';
        } else {
            const record = Usage.visibleProviders(this._records).find(candidate => String(candidate.id) === this._selectedId);
            const updated = Usage.updatedAt(record);
            const parts = Number.isFinite(updated) ? [`Updated ${Usage.formatClock(updated)}`] : [];
            if (this._newRelease)
                parts.push(`v${this._newRelease} available`);
            this._footer.text = parts.join(' · ');
        }
        if (this._newRelease)
            this._footer.add_style_class_name('agent-usage-footer-update');
        else
            this._footer.remove_style_class_name('agent-usage-footer-update');
    }

    _updateCountdowns() {
        const now = Date.now();
        for (const {label: widget, resetMs} of this._countdowns) {
            const remaining = resetMs - now;
            widget.text = Number.isFinite(remaining) && remaining > 0 ? `Resets in ${Usage.formatDuration(remaining)}` : '';
            widget.visible = widget.text !== '';
        }
    }

    _cleanup() {
        this._cancellable.cancel();
        for (const id of this._settingsIds)
            this._settings.disconnect(id);
        this._settingsIds = [];
        if (this._sleepSubscription) {
            Gio.DBus.system.signal_unsubscribe(this._sleepSubscription);
            this._sleepSubscription = 0;
        }
        this._monitor?.cancel();
        this._monitor = null;
        for (const id of this._sources)
            GLib.source_remove(id);
        this._sources.clear();
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
