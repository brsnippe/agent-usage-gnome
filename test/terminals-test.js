// Run with: gjs -m test/terminals-test.js
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
const launch = (prefs, find = ubuntu) =>
    Terminals.resolveLaunch({agent: 'opencode', agentCommand: '', terminal: 'auto', terminalCommand: '', ...prefs}, find);

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
check('findProgram ignores folders and missing names', [Terminals.findProgram('/usr'), Terminals.findProgram('surely-not-a-program')], [null, null]);

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
