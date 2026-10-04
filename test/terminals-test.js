// Run with: gjs -m test/terminals-test.js
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';

import * as Terminals from '../agent-usage@local/terminals.js';

let failures = 0;
function check(name, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok)
        failures++;
    print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`);
}

// A fake machine: which programs exist, and where.
function machine(...names) {
    const paths = Object.fromEntries(names.map(name => [name, `/usr/bin/${name}`]));
    return name => paths[name] ?? (name.startsWith('/') && Object.values(paths).includes(name) ? name : null);
}
const ubuntu = machine('opencode', 'claude', 'ghostty', 'gnome-terminal', 'x-terminal-emulator');
// Which desktop apps the fake machine has.
const withApps = (...ids) => app => ids.includes(app.id) ? {desktopId: `${app.id}.desktop`} : null;
const launch = (prefs, find = ubuntu, findApp = withApps()) =>
    Terminals.resolveLaunch({agent: 'opencode', agentCommand: '', terminal: 'auto', terminalCommand: '', ...prefs}, find, findApp);

check('automatic on stock Ubuntu picks GNOME Terminal', launch({}),
    {argv: ['/usr/bin/gnome-terminal', '--', '/usr/bin/opencode'], agentName: 'OpenCode', terminalName: 'GNOME Terminal'});
check('automatic prefers xdg-terminal-exec when present', launch({}, machine('opencode', 'xdg-terminal-exec', 'gnome-terminal')).argv,
    ['/usr/bin/xdg-terminal-exec', '/usr/bin/opencode']);
check('Ghostty', launch({terminal: 'ghostty'}).argv, ['/usr/bin/ghostty', '-e', '/usr/bin/opencode']);

const every = machine('opencode', ...Terminals.TERMINALS.map(terminal => terminal.program));
check('every listed terminal builds its own command line',
    Terminals.TERMINALS.map(terminal => launch({terminal: terminal.id}, every).argv.slice(1).join(' ')), [
        '-e /usr/bin/opencode',
        '-- /usr/bin/opencode',
        "--new-window -x '/usr/bin/opencode'",
        '/usr/bin/opencode',
        '-e /usr/bin/opencode',
        'start -- /usr/bin/opencode',
        '/usr/bin/opencode',
        '-e /usr/bin/opencode',
        '-e /usr/bin/opencode',
    ]);

check('a chosen terminal that is missing is an error, not a fallback', launch({terminal: 'kitty'}),
    {error: "Kitty isn't installed.", reason: 'terminal', agentName: 'OpenCode'});
check('no terminal at all', launch({}, machine('opencode')).reason, 'terminal');

check('Claude Code as the agent', launch({agent: 'claude', terminal: 'ghostty'}),
    {argv: ['/usr/bin/ghostty', '-e', '/usr/bin/claude'], agentName: 'Claude Code', terminalName: 'Ghostty'});
check('a missing agent hides the button', launch({agent: 'codex'}),
    {error: "Codex isn't installed (no codex found).", reason: 'agent', agentName: 'Codex'});
check('custom agent with arguments', launch({agent: 'custom', agentCommand: 'claude --continue', terminal: 'ghostty'}),
    {argv: ['/usr/bin/ghostty', '-e', '/usr/bin/claude', '--continue'], agentName: 'claude', terminalName: 'Ghostty'});
check('custom agent left empty', launch({agent: 'custom'}).error, 'Enter a custom agent command in the settings.');
check('custom agent that is not installed', launch({agent: 'custom', agentCommand: 'aider --yes'}).error, "aider isn't installed.");
check('custom agent with broken quoting', launch({agent: 'custom', agentCommand: 'claude "--x'}).reason, 'agent');

check('custom terminal with {command} as its own word',
    launch({terminal: 'custom', terminalCommand: 'ghostty --window-decoration=false -e {command}', agent: 'custom', agentCommand: 'claude --continue'}).argv,
    ['/usr/bin/ghostty', '--window-decoration=false', '-e', '/usr/bin/claude', '--continue']);
check('custom terminal without {command} appends it',
    launch({terminal: 'custom', terminalCommand: 'ghostty -e'}).argv, ['/usr/bin/ghostty', '-e', '/usr/bin/opencode']);
check('custom terminal with {command} inside a word gets one quoted string',
    launch({terminal: 'custom', terminalCommand: 'gnome-terminal --command={command}', agent: 'custom', agentCommand: 'claude --continue'}).argv,
    ['/usr/bin/gnome-terminal', "--command='/usr/bin/claude' '--continue'"]);
check('custom terminal keeps quoted arguments together',
    launch({terminal: 'custom', terminalCommand: "ghostty --title='Agent usage' -e {command}"}).argv,
    ['/usr/bin/ghostty', '--title=Agent usage', '-e', '/usr/bin/opencode']);
check('custom terminal left empty', launch({terminal: 'custom'}).error, 'Enter a custom terminal command in the settings.');
check('custom terminal that is not installed', launch({terminal: 'custom', terminalCommand: 'tilix -e {command}'}).error,
    "tilix, from the custom terminal command, isn't installed.");

// Desktop apps instead of a terminal.
const claudeApp = launch({agent: 'claude-desktop'}, ubuntu, withApps('claude'));
check('a desktop app as the agent', claudeApp, {desktopId: 'claude.desktop', opensApp: true, agentName: 'Claude (desktop app)'});
check('a missing desktop app hides the button', launch({agent: 'opencode-desktop'}, ubuntu, withApps('claude')),
    {error: "OpenCode (desktop app) isn't installed.", reason: 'agent', agentName: 'OpenCode (desktop app)'});
check('button hints', [launch({}), launch({terminal: 'kitty'}), launch({agent: 'codex'}), claudeApp].map(Terminals.buttonHint),
    ['Open OpenCode in GNOME Terminal', 'Open OpenCode', null, 'Open Claude (desktop app)']);
check('"Try it" says what it opens', [launch({terminal: 'ghostty'}), claudeApp, {opensApp: true, argv: ['/opt/OpenCode.AppImage']}].map(Terminals.describeLaunch),
    ['/usr/bin/ghostty -e /usr/bin/opencode', 'Opens the app from claude.desktop', '/opt/OpenCode.AppImage']);
check('installed agents, desktop apps included', Terminals.AGENTS.map(agent => Terminals.agentInstalled(agent, ubuntu, withApps('opencode'))),
    [true, true, true, false, false]);

const appInfo = (id, executable) => ({get_id: () => id, get_executable: () => executable});
const desktopApp = id => Terminals.DESKTOP_APPS.find(app => app.id === id);
check('a desktop app is found by its desktop file',
    Terminals.findDesktopApp(desktopApp('opencode'), [appInfo('firefox.desktop', 'firefox'), appInfo('ai.opencode.desktop.desktop', '/usr/bin/ai.opencode.desktop')], ubuntu),
    {desktopId: 'ai.opencode.desktop.desktop'});
check('…or by a desktop file of another name that runs it',
    Terminals.findDesktopApp(desktopApp('claude'), [appInfo('com.example.claude.desktop', '/opt/Claude/claude-desktop')], ubuntu),
    {desktopId: 'com.example.claude.desktop'});
check('…or by its program alone, such as an AppImage',
    Terminals.findDesktopApp(desktopApp('opencode'), [], name => name === '~/Applications/OpenCode.AppImage' ? '/home/me/Applications/OpenCode.AppImage' : null),
    {argv: ['/home/me/Applications/OpenCode.AppImage']});
check("…but Claude Code's own link handler isn't the desktop app",
    Terminals.findDesktopApp(desktopApp('claude'), [appInfo('claude-code-url-handler.desktop', '/home/me/.local/bin/claude')], ubuntu), null);

// The problem card's sign-in commands, in the chosen terminal.
check('sign in runs in the chosen terminal and waits before closing',
    Terminals.commandArgv({terminal: 'ghostty', terminalCommand: ''}, ['claude', 'auth', 'login'], {pause: true}, ubuntu),
    {argv: ['/usr/bin/ghostty', '-e', ...Terminals.withPause(['/usr/bin/claude', 'auth', 'login'])], terminalName: 'Ghostty'});
check('starting Claude Code needs no pause', Terminals.commandArgv({terminal: 'ghostty', terminalCommand: ''}, ['claude'], {}, ubuntu).argv,
    ['/usr/bin/ghostty', '-e', '/usr/bin/claude']);
check('a missing tool', Terminals.commandArgv({terminal: 'auto', terminalCommand: ''}, ['codex', 'login'], {pause: true}, ubuntu),
    {error: "codex isn't installed."});
check('a missing terminal', Terminals.commandArgv({terminal: 'kitty', terminalCommand: ''}, ['claude'], {}, ubuntu), {error: "Kitty isn't installed."});

// The pause, for real: the output stays, then Enter (here: end of input)
// closes it with the command's own exit status.
const paused = Gio.Subprocess.new(Terminals.withPause(['sh', '-c', 'echo signed in; exit 3']),
    Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE);
const [, pausedOutput] = paused.communicate_utf8(null, null);
check('the pause shows the output, asks for Enter and keeps the exit status',
    [pausedOutput, paused.get_exit_status()], ['signed in\n\nPress Enter to close this window. ', 3]);

check('installed terminals, in list order', Terminals.installedTerminals(ubuntu).map(terminal => terminal.name), ['Ghostty', 'GNOME Terminal']);
check('display command shortens home and quotes spaces',
    Terminals.displayCommand(['/usr/bin/ghostty', '--title=Agent usage', '-e', `${GLib.get_home_dir()}/.local/bin/opencode`]),
    "/usr/bin/ghostty '--title=Agent usage' -e ~/.local/bin/opencode");

// The settings schema only accepts listed values; it has to list exactly
// what the module knows.
const schemaPath = GLib.build_filenamev([GLib.path_get_dirname(import.meta.url.replace('file://', '')),
    '..', 'agent-usage@local', 'schemas', 'org.gnome.shell.extensions.agent-usage.gschema.xml']);
const schema = new TextDecoder().decode(GLib.file_get_contents(schemaPath)[1]);
const choices = key => [...(schema.match(new RegExp(`<key name="${key}"[\\s\\S]*?</key>`))?.[0] ?? '')
    .matchAll(/<choice value="([^"]+)"/g)].map(match => match[1]);
check('schema terminal choices match the module', choices('terminal'), ['auto', ...Terminals.TERMINALS.map(t => t.id), 'custom']);
check('schema agent choices match the module', choices('agent'), [...Terminals.AGENTS.map(a => a.id), 'custom']);

// The real lookup on this machine: PATH plus the per-user folders.
check('findProgram finds sh on the real PATH', Terminals.findProgram('sh') !== null, true);
check("findDesktopApp reads this machine's desktop files", Terminals.DESKTOP_APPS.map(app => {
    const found = Terminals.findDesktopApp(app);
    return found === null || typeof (found.desktopId ?? found.argv[0]) === 'string';
}), [true, true]);
check('findProgram ignores folders and missing names', [Terminals.findProgram('/usr'), Terminals.findProgram('surely-not-a-program')], [null, null]);

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
