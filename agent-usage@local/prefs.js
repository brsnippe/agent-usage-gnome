import Adw from 'gi://Adw';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import * as Terminals from './terminals.js';
import {isNewer} from './versions.js';

// A dropdown over string ids: shows `labels`, stores the matching id.
function choiceRow(settings, key, title, ids, labels) {
    const row = new Adw.ComboRow({title, model: Gtk.StringList.new(labels), use_markup: false});
    row.selected = Math.max(0, ids.indexOf(settings.get_string(key)));
    row.connect('notify::selected', () => {
        if (ids[row.selected] !== settings.get_string(key))
            settings.set_string(key, ids[row.selected]);
    });
    return row;
}

export default class AgentUsagePreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        window.set_default_size(620, 860);

        const cancellable = new Gio.Cancellable();
        window.connect('close-request', () => {
            cancellable.cancel();
            return false;
        });

        const page = new Adw.PreferencesPage({title: 'General', icon_name: 'preferences-system-symbolic'});
        page.add(this._refreshGroup(settings));
        page.add(this._topBarGroup(settings));
        page.add(this._launchGroup(settings));
        page.add(this._updatesGroup(settings, cancellable));
        window.add(page);
    }

    // install.sh records the git checkout a git install came from.
    _sourceDir() {
        try {
            const [, bytes] = GLib.file_get_contents(`${this.path}/source`);
            const dir = new TextDecoder().decode(bytes).trim();
            return GLib.file_test(`${dir}/bin/agent-usage`, GLib.FileTest.IS_EXECUTABLE) ? dir : null;
        } catch {
            return null;
        }
    }

    _updatesGroup(settings, cancellable) {
        const group = new Adw.PreferencesGroup({title: 'Updates'});
        const installed = String(this.metadata['version-name'] ?? '');
        const shown = installed ? `v${installed}` : 'an unknown version';
        const sourceDir = this._sourceDir();

        const versionRow = new Adw.ActionRow({title: 'Version', use_markup: false, subtitle_selectable: true});
        const button = new Gtk.Button({label: 'Update', valign: Gtk.Align.CENTER, sensitive: false, css_classes: ['suggested-action']});
        versionRow.add_suffix(button);
        group.add(versionRow);

        const check = new Adw.SwitchRow({
            title: 'Check for new versions',
            subtitle: 'Every hour and after waking from sleep. Asks the git repository this was installed from. The panel says when one is out.',
        });
        settings.bind('check-updates', check, 'active', Gio.SettingsBindFlags.DEFAULT);
        group.add(check);

        if (!sourceDir) {
            versionRow.subtitle = `${shown} · not installed from git, so it can't update itself. Reinstall with get.sh (see the README).`;
            check.sensitive = false;
            return group;
        }

        versionRow.subtitle = `${shown} · checking for a newer version…`;
        try {
            const proc = Gio.Subprocess.new([`${sourceDir}/bin/agent-usage`, 'latest'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            proc.communicate_utf8_async(null, cancellable, (_proc, result) => {
                try {
                    const [, stdout, stderr] = proc.communicate_utf8_finish(result);
                    const latest = String(stdout || '').trim();
                    if (!proc.get_successful()) {
                        versionRow.subtitle = `${shown} · couldn't check: ${String(stderr || '').trim().replace(/^agent-usage: /, '')}`;
                    } else if (isNewer(latest, installed)) {
                        versionRow.subtitle = `${shown} · v${latest} is available`;
                        button.sensitive = true;
                    } else {
                        versionRow.subtitle = `${shown} · up to date`;
                    }
                } catch (e) {
                    if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        versionRow.subtitle = `${shown} · couldn't check: ${e.message}`;
                }
            });
        } catch (e) {
            versionRow.subtitle = `${shown} · couldn't check: ${e.message}`;
        }

        // In a terminal, so the progress (and any sudo prompt for packages)
        // is visible.
        button.connect('clicked', () => {
            const terminal = Terminals.terminalArgv(Terminals.launchSettings(settings),
                [`${sourceDir}/bin/agent-usage`, 'update', '--pause']);
            if (terminal.error) {
                versionRow.subtitle = terminal.error;
                return;
            }
            try {
                const launcher = new Gio.SubprocessLauncher({flags: Gio.SubprocessFlags.NONE});
                launcher.set_cwd(GLib.get_home_dir());
                launcher.spawnv(terminal.argv);
                versionRow.subtitle = `Updating in ${terminal.terminalName}. Afterwards, reload GNOME: Alt+F2, r, Enter on X11, or log out and back in.`;
                button.sensitive = false;
            } catch (e) {
                versionRow.subtitle = `Couldn't start the update: ${e.message}`;
            }
        });
        return group;
    }

    _refreshGroup(settings) {
        const group = new Adw.PreferencesGroup({
            title: 'Refresh',
            description: 'Changes apply right away. The panel also refreshes when you open it, after you unlock the screen, and when the computer wakes from sleep.',
        });

        const limits = new Adw.SpinRow({
            title: 'Check limits every',
            subtitle: 'Seconds. Keeps the percentage in the top bar current; opening the panel always checks right away. Anthropic refuses checks that come too often, and checking then pauses for 1 to 15 minutes.',
            adjustment: new Gtk.Adjustment({lower: 30, upper: 3600, step_increment: 30, page_increment: 300}),
        });
        settings.bind('limits-interval', limits, 'value', Gio.SettingsBindFlags.DEFAULT);
        group.add(limits);

        const scan = new Adw.SpinRow({
            title: 'Rescan local usage every',
            subtitle: 'Minutes. Rereads transcripts and OpenCode history for the token charts.',
            adjustment: new Gtk.Adjustment({lower: 5, upper: 60, step_increment: 1, page_increment: 5}),
        });
        settings.bind('scan-interval', scan, 'value', Gio.SettingsBindFlags.DEFAULT);
        group.add(scan);
        return group;
    }

    _topBarGroup(settings) {
        const group = new Adw.PreferencesGroup({title: 'Top bar'});
        const session = new Adw.SpinRow({
            title: 'Show the session limit from',
            subtitle: 'Percent. Once the 5-hour session limit is this full, the top bar shows it, even when the weekly limit is fuller. Below it, the top bar shows the fullest limit. 0 always shows the session limit.',
            adjustment: new Gtk.Adjustment({lower: 0, upper: 100, step_increment: 5, page_increment: 10}),
        });
        settings.bind('session-threshold', session, 'value', Gio.SettingsBindFlags.DEFAULT);
        group.add(session);

        const colors = new Adw.SwitchRow({
            title: 'Session colors',
            subtitle: 'The robot turns orange while a Claude Code or OpenCode session waits for you, and green once one has finished, until you open the panel. Works through hooks in Claude Code and a plugin in OpenCode 2; switching this off removes them.',
        });
        settings.bind('session-colors', colors, 'active', Gio.SettingsBindFlags.DEFAULT);
        group.add(colors);
        return group;
    }

    _launchGroup(settings) {
        const group = new Adw.PreferencesGroup({
            title: 'Open agent',
            description: "What the panel's open button, and right-clicking the top-bar icon, opens: an agent in a terminal, or a desktop app.",
        });

        const rightClick = new Adw.SwitchRow({
            title: 'Right-click opens the agent',
            subtitle: 'Off: right-click opens the panel, as left-click does.',
        });
        settings.bind('right-click-opens-agent', rightClick, 'active', Gio.SettingsBindFlags.DEFAULT);
        group.add(rightClick);

        // Agents: all of them, marked when this machine doesn't have one.
        const agentIds = [...Terminals.AGENTS.map(agent => agent.id), 'custom'];
        const agentLabels = [
            ...Terminals.AGENTS.map(agent => Terminals.agentInstalled(agent) ? agent.name : `${agent.name} (not installed)`),
            'Custom…',
        ];
        group.add(choiceRow(settings, 'agent', 'Agent', agentIds, agentLabels));

        const agentCommand = new Adw.EntryRow({title: 'Custom agent command, e.g. claude --continue', use_markup: false});
        settings.bind('agent-command', agentCommand, 'text', Gio.SettingsBindFlags.DEFAULT);
        group.add(agentCommand);

        // Terminals: the installed ones, plus the current choice if it has
        // since been uninstalled, so the dropdown can still show it.
        const installed = Terminals.installedTerminals();
        const current = Terminals.TERMINALS.find(terminal => terminal.id === settings.get_string('terminal'));
        const terminals = current && !installed.includes(current)
            ? Terminals.TERMINALS.filter(terminal => installed.includes(terminal) || terminal === current)
            : installed;
        const terminalIds = ['auto', ...terminals.map(terminal => terminal.id), 'custom'];
        const terminalLabels = [
            'Automatic',
            ...terminals.map(terminal => installed.includes(terminal) ? terminal.name : `${terminal.name} (not installed)`),
            'Custom…',
        ];
        const terminalRow = choiceRow(settings, 'terminal', 'Terminal', terminalIds, terminalLabels);
        terminalRow.subtitle = 'Signing in and updating use it too, also with a desktop app.';
        group.add(terminalRow);

        const terminalCommand = new Adw.EntryRow({title: 'Custom terminal command, e.g. ghostty -e {command}', use_markup: false});
        settings.bind('terminal-command', terminalCommand, 'text', Gio.SettingsBindFlags.DEFAULT);
        group.add(terminalCommand);

        const tryRow = new Adw.ActionRow({title: 'Try it', use_markup: false, subtitle_selectable: true});
        const tryButton = new Gtk.Button({label: 'Open', valign: Gtk.Align.CENTER});
        tryRow.add_suffix(tryButton);
        group.add(tryRow);

        const update = () => {
            agentCommand.visible = settings.get_string('agent') === 'custom';
            terminalCommand.visible = settings.get_string('terminal') === 'custom';
            const launch = Terminals.resolveLaunch(Terminals.launchSettings(settings));
            tryRow.subtitle = Terminals.describeLaunch(launch);
            tryButton.sensitive = !launch.error;
        };
        settings.connect('changed', update);
        update();

        tryButton.connect('clicked', () => {
            const launch = Terminals.resolveLaunch(Terminals.launchSettings(settings));
            if (launch.error)
                return;
            try {
                if (launch.desktopId) {
                    Gio.AppInfo.get_all().find(info => info.get_id() === launch.desktopId)?.launch([], null);
                    return;
                }
                const launcher = new Gio.SubprocessLauncher({flags: Gio.SubprocessFlags.NONE});
                launcher.set_cwd(GLib.get_home_dir());
                launcher.spawnv(launch.argv);
            } catch (e) {
                tryRow.subtitle = `Couldn't start it: ${e.message}`;
            }
        });
        return group;
    }
}
