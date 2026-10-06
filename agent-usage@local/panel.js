// The panel, shared by the GNOME extension (extension.js) and the Cinnamon
// applet (cinnamon/agent-usage@local/applet.js). Both shells draw with St and
// Clutter, so everything here works in either; each shell supplies a small
// host for what differs: the button in its bar, the menu around this panel,
// settings, notifications and opening apps.
//
// Like Omarchy's widget, this is only a display. bin/agent-usage-update runs
// one collector per agent and writes a JSON record per agent to
// ~/.local/state/omarchy/agents/usage/; the panel watches that folder and
// draws whatever is there.
//
// It also watches ~/.local/state/omarchy/agents/sessions/, where the agents'
// hooks say which sessions want you (see sessions.js), for the robot's color.
//
// The host:
//   showTopBar({hasUsage, text, alarming, stale, session})  the icon and
//                         percentage in the bar; session is 'waiting', 'ready'
//                         or null
//   closeMenu(), isMenuOpen(), keepFocus(), scrollToTop()
//   openSettings()        the settings window
//   openUpdate()          what clicking "vX.Y.Z available" does
//   quitPrompt()          what the ⏻ button asks before switching off
//   quit()                switch off: GNOME's extension, Cinnamon's applet,
//                         until switched back on
//   notify(text)
//   openApp(desktopId)    bring a desktop app forward, or start it
//   spawn(argv)
//   preferredTerminal()   optional: the desktop's own default terminal
//
// The settings: anything with get_int, get_string, get_boolean,
// connect('changed::<key>', callback) and disconnect(id), as Gio.Settings has.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Sessions from './sessions.js';
import * as Terminals from './terminals.js';
import {UpdateQueue, updateArgv} from './updates.js';
import * as Usage from './usage.js';
import {isNewer} from './versions.js';

const RETRY_SECONDS = 30;
const TICK_SECONDS = 30;
// After waking from sleep, give the network a moment before checking.
const WAKE_DELAY_SECONDS = 5;
// New releases: every hour, starting a minute after login, and after waking
// from sleep unless the last check was recent. The hourly timer doesn't run
// while the machine sleeps.
const RELEASE_CHECK_SECONDS = 3600;
const FIRST_RELEASE_CHECK_SECONDS = 60;
const WAKE_RELEASE_CHECK_SECONDS = 15 * 60;
// After a sign-in button: check that agent's limits this often, this many
// times, until the problem is gone.
const SIGN_IN_CHECK_SECONDS = 15;
const SIGN_IN_CHECKS = 20;
// While there are session files: look again this often, since a process that
// goes away doesn't change any file.
const SESSIONS_CHECK_SECONDS = 30;
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
// A plain St.DrawingArea rather than a registered subclass: Cinnamon
// re-evaluates this file when it reloads the applet, and a GObject type can
// only be registered once.
function bar({value = 0, alarming = false, fillAlpha = 1, trackAlpha = 0.14, pill = true, styleClass = 'agent-usage-bar', ...props} = {}) {
    const area = new St.DrawingArea({style_class: styleClass, x_expand: true, y_align: Clutter.ActorAlign.CENTER, ...props});
    const fraction = Usage.clamp(Number(value) || 0);
    const color = alarming ? URGENT : FOREGROUND;
    area.connect('repaint', () => {
        const cr = area.get_context();
        const [width, height] = area.get_surface_size();
        const radius = pill ? height / 2 : 0;
        roundedRect(cr, 0, 0, width, height, radius);
        cr.setSourceRGBA(...FOREGROUND, trackAlpha);
        cr.fill();
        const fill = width * fraction;
        if (fill > 0) {
            roundedRect(cr, 0, 0, fill, height, radius);
            cr.setSourceRGBA(...color, fillAlpha);
            cr.fill();
        }
        cr.$dispose();
    });
    return area;
}

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

// The JSON files in a folder, by name; dotfiles are other things, or files
// still being written.
function readJsonFiles(path) {
    const dir = Gio.File.new_for_path(path);
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
    const contents = [];
    for (const name of names.sort()) {
        try {
            const [, bytes] = dir.get_child(name).load_contents(null);
            contents.push(JSON.parse(decoder.decode(bytes)));
        } catch {
            // Mid-write or malformed: skip it until the next change.
        }
    }
    return contents;
}

// Linux has a /proc entry for every running process.
function processRunning(pid) {
    return GLib.file_test(`/proc/${pid}`, GLib.FileTest.EXISTS);
}

// The installer records the git checkout a git install came from; installs
// from a tarball have none and never check for releases.
function readSourceDir(path) {
    try {
        const [, bytes] = GLib.file_get_contents(`${path}/source`);
        const dir = new TextDecoder().decode(bytes).trim();
        return GLib.file_test(`${dir}/bin/agent-usage`, GLib.FileTest.IS_EXECUTABLE) ? dir : null;
    } catch {
        return null;
    }
}

export class PanelController {
    constructor({path, settings, host, installedVersion = ''}) {
        this._path = path;
        this._settings = settings;
        this._host = host;
        this._updater = `${path}/bin/agent-usage-update`;
        this._sessionHooks = `${path}/hooks/agent-usage-session`;
        this._usageDir = `${GLib.get_user_state_dir()}/omarchy/agents/usage`;
        this._sessionsDir = `${GLib.get_user_state_dir()}/omarchy/agents/sessions`;
        this._session = null;
        this._sessionsMonitor = null;
        this._sessionsReloadId = 0;
        this._sessionsCheckId = 0;
        this._records = [];
        this._recordsKey = null;
        this._providers = [];
        this._selectedId = '';
        this._countdowns = [];
        this._footer = null;
        this._hoverText = null;
        this._confirmingQuit = false;
        this._quitButton = null;
        this._queue = new UpdateQueue();
        this._cancellable = new Gio.Cancellable();
        this._sources = new Set();
        this._settingsIds = [];
        this._monitor = null;
        this._reloadId = 0;
        this._retryId = 0;
        this._tickId = 0;
        this._wakeId = 0;
        this._limitsTimerId = 0;
        this._scanTimerId = 0;
        this._sleepSubscription = 0;
        this._releaseTimerId = 0;
        this._lastReleaseCheck = 0;
        this._signInId = 0;
        this._locked = false;
        this._installedVersion = String(installedVersion ?? '');
        this._sourceDir = readSourceDir(path);
        this._newRelease = null;

        // What the host puts in its menu.
        this.actor = new St.BoxLayout({vertical: true, style_class: 'agent-usage-panel'});
    }

    // The git checkout this was installed from, or null.
    get sourceDir() {
        return this._sourceDir;
    }

    start() {
        GLib.mkdir_with_parents(this._usageDir, 0o755);
        this._monitor = Gio.File.new_for_path(this._usageDir).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connect('changed', () => this._scheduleReload());

        this._settingsIds = ['changed::limits-interval', 'changed::scan-interval']
            .map(signal => this._settings.connect(signal, () => this._restartTimers()));
        // The header's "Open …" button names the agent and terminal.
        for (const key of LAUNCH_KEYS)
            this._settingsIds.push(this._settings.connect(`changed::${key}`, () => this._buildPanel()));
        this._settingsIds.push(this._settings.connect('changed::check-updates', () => this._restartReleaseChecks()));
        this._settingsIds.push(this._settings.connect('changed::session-threshold', () => this._showPercent()));
        this._settingsIds.push(this._settings.connect('changed::session-colors', () => {
            this._applySessionHooks();
            this._loadSessions();
        }));

        GLib.mkdir_with_parents(this._sessionsDir, 0o755);
        this._sessionsMonitor = Gio.File.new_for_path(this._sessionsDir).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._sessionsMonitor.connect('changed', () => this._scheduleSessions());

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

        this._reload();
        this._loadSessions();
        // Every start, so an agent installed since gets its hooks too.
        this._applySessionHooks();
        this._runUpdate('normal');
        this._restartTimers();
        this._restartReleaseChecks();
    }

    destroy() {
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
        this._sessionsMonitor?.cancel();
        this._sessionsMonitor = null;
        for (const id of this._sources)
            GLib.source_remove(id);
        this._sources.clear();
    }

    // A person asked for fresh numbers: the middle click, ↻, or `r`.
    refresh() {
        this._runUpdate('force');
    }

    // Cinnamon keeps applets running while the screen is locked, where GNOME
    // switches extensions off. Nothing checks while locked, and unlocking
    // refreshes, as GNOME's re-enabling does.
    setLocked(locked) {
        if (locked === this._locked)
            return;
        this._locked = locked;
        if (locked) {
            this._limitsTimerId = this._removeSource(this._limitsTimerId);
            this._scanTimerId = this._removeSource(this._scanTimerId);
            this._releaseTimerId = this._removeSource(this._releaseTimerId);
            this._retryId = this._removeSource(this._retryId);
            this._signInId = this._removeSource(this._signInId);
            this._wakeId = this._removeSource(this._wakeId);
            return;
        }
        this._runUpdate('normal');
        this._restartTimers();
        this._restartReleaseChecks();
    }

    // The settings that say what "Open …" starts, and where.
    launchSettings() {
        return {...Terminals.launchSettings(this._settings), preferredTerminal: this._host.preferredTerminal?.() ?? null};
    }

    launchAgent() {
        // Going to your agent is looking at it.
        this._acknowledgeSessions();
        const launch = this._launch();
        if (launch.error) {
            this._host.notify(launch.error);
            return;
        }
        if (launch.desktopId)
            this._host.openApp(launch.desktopId);
        else
            this._host.spawn(launch.argv);
    }

    onMenuOpenChanged(open) {
        if (open) {
            this._acknowledgeSessions();
            // Opening wants the numbers that go stale on the wire, not another
            // walk over every transcript on disk.
            this._runUpdate('limits');
            this._host.scrollToTop();
            this._updateCountdowns();
            this._tickId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, TICK_SECONDS, () => {
                this._updateCountdowns();
                return GLib.SOURCE_CONTINUE;
            }));
        } else {
            this._tickId = this._removeSource(this._tickId);
            this._hoverText = null;
            // Closing the panel answers the ⏻ question with no.
            if (this._confirmingQuit) {
                this._confirmingQuit = false;
                this._buildPanel();
            }
            this._showFooter();
        }
    }

    // A key pressed while the menu is open. Returns true when it was ours.
    handleKey(key) {
        if (key === Clutter.KEY_r || key === Clutter.KEY_R) {
            this._runUpdate('force');
            return true;
        }
        if (key === Clutter.KEY_q || key === Clutter.KEY_Q) {
            this._askQuit();
            return true;
        }
        if (this._providers.length > 1) {
            if (key === Clutter.KEY_Left || key === Clutter.KEY_h) {
                this._step(-1);
                return true;
            }
            if (key === Clutter.KEY_Right || key === Clutter.KEY_l) {
                this._step(1);
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------ releases

    _restartReleaseChecks() {
        this._releaseTimerId = this._removeSource(this._releaseTimerId);
        if (!this._sourceDir || !this._settings.get_boolean('check-updates')) {
            this._newRelease = null;
            this._showFooter();
            return;
        }
        if (this._locked)
            return;
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

    // The wall clock, unlike the timers, counts the time spent asleep.
    _checkForReleaseAfterWake() {
        if (this._releaseTimerId && Date.now() - this._lastReleaseCheck >= WAKE_RELEASE_CHECK_SECONDS * 1000)
            this._checkForRelease();
    }

    _checkForRelease() {
        this._lastReleaseCheck = Date.now();
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

    // ------------------------------------------------------------ timers

    // Two cadences: the cheap limits probe keeps the top-bar percentage live,
    // and the slower full pass rescans transcripts for the token charts.
    _restartTimers() {
        this._limitsTimerId = this._removeSource(this._limitsTimerId);
        this._scanTimerId = this._removeSource(this._scanTimerId);
        if (this._locked)
            return;
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
        // A locked screen refreshes when it's unlocked.
        if (this._locked)
            return;
        this._wakeId = this._removeSource(this._wakeId);
        this._wakeId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, WAKE_DELAY_SECONDS, () => {
            this._sources.delete(this._wakeId);
            this._wakeId = 0;
            this._runUpdate('normal');
            this._checkForReleaseAfterWake();
            return GLib.SOURCE_REMOVE;
        }));
    }

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

    // ------------------------------------------------------------ data

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
        return readJsonFiles(this._usageDir).filter(record => record && typeof record === 'object' && record.id);
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
        if (advising.length === 0 || this._retryId || this._locked)
            return;
        this._retryId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, RETRY_SECONDS, () => {
            this._sources.delete(this._retryId);
            this._retryId = 0;
            this._runUpdate('limits', advising);
            return GLib.SOURCE_REMOVE;
        }));
    }

    // ------------------------------------------------------------ sessions

    _scheduleSessions() {
        // A hook writes its file through a temporary one; look once.
        if (this._sessionsReloadId)
            return;
        this._sessionsReloadId = this._addSource(GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            this._sources.delete(this._sessionsReloadId);
            this._sessionsReloadId = 0;
            this._loadSessions();
            return GLib.SOURCE_REMOVE;
        }));
    }

    _loadSessions() {
        const records = this._settings.get_boolean('session-colors') ? readJsonFiles(this._sessionsDir) : [];
        const session = Sessions.topBarSession(records, {now: Date.now(), seen: this._readSeen(), alive: processRunning});
        this._sessionsCheckId = this._removeSource(this._sessionsCheckId);
        if (records.length > 0) {
            this._sessionsCheckId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, SESSIONS_CHECK_SECONDS, () => {
                this._sources.delete(this._sessionsCheckId);
                this._sessionsCheckId = 0;
                this._loadSessions();
                return GLib.SOURCE_REMOVE;
            }));
        }
        if (session !== this._session) {
            this._session = session;
            this._showPercent();
        }
    }

    _readSeen() {
        try {
            const [, bytes] = GLib.file_get_contents(`${this._sessionsDir}/${Sessions.SEEN_FILE}`);
            return Sessions.parseSeen(new TextDecoder().decode(bytes));
        } catch {
            return 0;
        }
    }

    // You looked: the turns that finished so far stop turning the robot green.
    _acknowledgeSessions() {
        try {
            GLib.file_set_contents(`${this._sessionsDir}/${Sessions.SEEN_FILE}`, String(Date.now()));
        } catch (e) {
            console.warn(`agent-usage: ${e.message}`);
        }
        this._loadSessions();
    }

    // The hooks in Claude Code and the plugin in OpenCode follow the setting.
    _applySessionHooks() {
        const action = this._settings.get_boolean('session-colors') ? 'install' : 'uninstall';
        let proc;
        try {
            proc = Gio.Subprocess.new([this._sessionHooks, action, '--quiet'],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (e) {
            console.warn(`agent-usage: could not run ${this._sessionHooks}: ${e.message}`);
            return;
        }
        proc.communicate_utf8_async(null, this._cancellable, (_proc, result) => {
            try {
                const [, , stderr] = proc.communicate_utf8_finish(result);
                if (stderr && stderr.trim())
                    console.warn(`agent-usage: ${stderr.trim()}`);
            } catch (e) {
                if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    console.warn(`agent-usage: ${e.message}`);
            }
        });
    }

    _launch() {
        return Terminals.resolveLaunch(this.launchSettings());
    }

    // The problem card's buttons: a command-line tool in the chosen terminal.
    _signInCommand(action) {
        return Terminals.commandArgv(this.launchSettings(), action.command, {pause: action.pause});
    }

    _signIn(id, action) {
        const terminal = this._signInCommand(action);
        if (terminal.error) {
            this._host.notify(terminal.error);
            return;
        }
        this._host.spawn(terminal.argv);
        this._followSignIn(id);
    }

    // Signing in happens in a browser or another window; keep checking that
    // agent's limits until the problem is gone, so the panel catches up on
    // its own.
    _followSignIn(id) {
        this._signInId = this._removeSource(this._signInId);
        let checks = 0;
        this._signInId = this._addSource(GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, SIGN_IN_CHECK_SECONDS, () => {
            const record = this._records.find(candidate => String(candidate.id) === id);
            if (checks++ >= SIGN_IN_CHECKS || Usage.signInActions(record).length === 0) {
                this._sources.delete(this._signInId);
                this._signInId = 0;
                return GLib.SOURCE_REMOVE;
            }
            this._runUpdate('limits', [id]);
            return GLib.SOURCE_CONTINUE;
        }));
    }

    _step(delta) {
        const count = this._providers.length;
        const index = this._providers.findIndex(record => String(record.id) === this._selectedId);
        this._select(this._providers[(((index + delta) % count) + count) % count].id);
    }

    _select(id) {
        this._selectedId = String(id);
        this._buildPanel();
        this._host.scrollToTop();
    }

    // ⏻ and `q`. Switching off takes more than a click to undo, so the panel
    // asks first, in a card under the header.
    _askQuit() {
        this._confirmingQuit = true;
        this._buildPanel();
        this._host.scrollToTop();
    }

    // ------------------------------------------------------------ view

    _render() {
        this._providers = Usage.visibleProviders(this._records);
        this._showPercent();

        // The selection follows the agent, not its slot, so a second agent's
        // first scan doesn't swap out what you were reading.
        if (!this._providers.some(record => String(record.id) === this._selectedId))
            this._selectedId = this._providers.length > 0 ? String(this._providers[0].id) : '';
        this._buildPanel();
    }

    _showPercent() {
        const percent = Usage.topBarPercent(this._providers, this._settings.get_int('session-threshold'));
        this._host.showTopBar({
            hasUsage: this._providers.length > 0,
            text: percent === null ? '' : `${Math.round(percent * 100)}%`,
            alarming: this._providers.some(Usage.isAlarming),
            // A percentage from an earlier check fades, so it doesn't pass for live.
            stale: this._providers.some(Usage.limitsStale),
            session: this._session,
        });
    }

    _buildPanel() {
        // Cinnamon closes a menu whose keyboard focus goes away, as it would
        // with a button about to be rebuilt (Switch off has it, for one).
        const focus = this.actor.get_stage()?.get_key_focus();
        if (focus && this.actor.contains(focus))
            this.actor.grab_key_focus();
        this.actor.destroy_all_children();
        this._countdowns = [];
        this._footer = null;
        this._hoverText = null;
        this._quitButton = null;

        const record = this._providers.find(candidate => String(candidate.id) === this._selectedId);
        if (!record) {
            // The robot can be there without usage (always on Cinnamon, and on
            // GNOME while a session wants you), so an empty panel keeps ⚙ and ⏻.
            const actions = new St.BoxLayout({style_class: 'agent-usage-hero', x_align: Clutter.ActorAlign.END});
            this._endActions(actions);
            this.actor.add_child(actions);
            if (this._confirmingQuit)
                this.actor.add_child(this._quitCard());
            this.actor.add_child(wrappingLabel("No AI coding subscriptions found.\nAgents show up here once you've used them.", 'agent-usage-empty'));
            this._focus();
            return;
        }

        this.actor.add_child(this._hero(record));
        if (this._confirmingQuit)
            this.actor.add_child(this._quitCard());
        if (this._providers.length > 1)
            this.actor.add_child(this._tabs());

        if (String(record.usageStatusText || '') !== '' && String(record.authHelpText || '') !== '')
            this.actor.add_child(this._problemCard(record));

        const balance = Usage.balanceValue(record.balance);
        const limits = Usage.limitWindows(record);
        if (balance || limits.length > 0)
            this.actor.add_child(separator());
        if (balance)
            this.actor.add_child(this._balanceSection(balance));
        if (limits.length > 0)
            this.actor.add_child(this._limitsSection(limits, record));

        const days = Usage.recentDays(record);
        if (days.length > 0) {
            this.actor.add_child(separator());
            this.actor.add_child(this._daysSection(record, days));
        }

        const today = Usage.todayModelRows(record);
        if (today.length > 0) {
            this.actor.add_child(separator());
            this.actor.add_child(this._modelsSection('TODAY BY MODEL', today, Usage.todayModelDetail));
        }

        const models = Usage.modelRows(record);
        if (models.length > 0) {
            this.actor.add_child(separator());
            this.actor.add_child(this._modelsSection(Usage.allTimeTitle(record), models, Usage.modelDetail,
                {hint: Usage.allTimeDetail(record)}));
        }

        this._footer = label('', 'agent-usage-footer', {x_expand: true, reactive: true, track_hover: true});
        // With a new release out, the footer says so; clicking it goes to the
        // update (GNOME: the settings, where the Update button is).
        this._footer.connect('button-release-event', () => {
            if (!this._newRelease)
                return Clutter.EVENT_PROPAGATE;
            this._host.closeMenu();
            this._host.openUpdate();
            return Clutter.EVENT_STOP;
        });
        this.actor.add_child(this._footer);
        this._showFooter();
        this._updateCountdowns();
        this._focus();
    }

    // Rebuilding destroys whatever had keyboard focus; the host hands it back
    // to the menu so ←/→ and r keep working while the panel is open. With the
    // ⏻ card up, Switch off takes it, so `q` and then Enter switch off.
    _focus() {
        this._host.keepFocus();
        if (this._quitButton && this._host.isMenuOpen())
            this._quitButton.grab_key_focus();
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
        const launch = this._launch();
        const hint = Terminals.buttonHint(launch);
        if (hint !== null) {
            const icon = launch.opensApp ? 'application-x-executable-symbolic' : 'utilities-terminal-symbolic';
            hero.add_child(this._action(icon, hint, () => {
                this._host.closeMenu();
                this.launchAgent();
            }));
        }
        this._endActions(hero);
        return hero;
    }

    // ⚙ and ⏻: last in the header, and on their own in an empty panel.
    _endActions(box) {
        box.add_child(this._action('preferences-system-symbolic', 'Settings', () => {
            this._host.closeMenu();
            this._host.openSettings();
        }));
        box.add_child(this._action('system-shutdown-symbolic', 'Switch off (q)', () => this._askQuit()));
    }

    // What switching off means here, and the two answers.
    _quitCard() {
        const card = new St.BoxLayout({vertical: true, style_class: 'agent-usage-status', x_expand: true});
        card.add_child(wrappingLabel(this._host.quitPrompt(), 'agent-usage-status-text'));
        const row = new St.BoxLayout({style_class: 'agent-usage-status-actions'});
        const answer = (text, callback) => {
            const button = new St.Button({label: text, style_class: 'agent-usage-status-button', can_focus: true, track_hover: true});
            button.connect('clicked', callback);
            row.add_child(button);
            return button;
        };
        this._quitButton = answer('Switch off', () => {
            this._confirmingQuit = false;
            this._host.closeMenu();
            this._host.quit();
        });
        answer('Cancel', () => {
            this._confirmingQuit = false;
            this._buildPanel();
        });
        card.add_child(row);
        return card;
    }

    // What's wrong and what to do about it, with buttons when the fix is
    // signing in again.
    _problemCard(record) {
        const card = new St.BoxLayout({vertical: true, style_class: 'agent-usage-status', x_expand: true});
        card.add_child(wrappingLabel(String(record.authHelpText), 'agent-usage-status-text'));
        const actions = Usage.signInActions(record);
        if (actions.length === 0)
            return card;
        const row = new St.BoxLayout({style_class: 'agent-usage-status-actions'});
        for (const action of actions) {
            const button = new St.Button({
                label: action.label,
                style_class: 'agent-usage-status-button',
                can_focus: true,
                track_hover: true,
            });
            button.connect('clicked', () => {
                this._host.closeMenu();
                this._signIn(String(record.id), action);
            });
            const terminal = this._signInCommand(action);
            this._hover(button, terminal.error ?? `Runs ${action.command.join(' ')} in ${terminal.terminalName}`);
            row.add_child(button);
        }
        card.add_child(row);
        return card;
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
            section.add_child(bar({value: balance.remaining / balance.funded, alarming}));
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
            limit.add_child(bar({value: window.percent, alarming}));
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
            row.add_child(bar({
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
    _modelsSection(title, models, detail, {hint = null} = {}) {
        const section = this._section(title, {hint});
        const heaviest = Math.max(1, models[0].total);
        for (const model of models) {
            const row = new St.Widget({
                layout_manager: new Clutter.BinLayout(),
                style_class: 'agent-usage-model',
                x_expand: true,
                reactive: true,
                track_hover: true,
            });
            row.add_child(bar({
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
}
