// Which agent "Open …" starts, and in which terminal. Shared by the panel
// and the settings window, so "Try it" behaves exactly like the panel
// button. Only uses GLib, so the tests run it under plain `gjs -m`.

import GLib from 'gi://GLib';

export const AGENTS = [
    {id: 'opencode', name: 'OpenCode', command: 'opencode'},
    {id: 'claude', name: 'Claude Code', command: 'claude'},
    {id: 'codex', name: 'Codex', command: 'codex'},
];

// Each entry turns the agent's argv into the terminal's arguments.
export const TERMINALS = [
    {id: 'ghostty', name: 'Ghostty', program: 'ghostty', args: command => ['-e', ...command]},
    {id: 'gnome-terminal', name: 'GNOME Terminal', program: 'gnome-terminal', args: command => ['--', ...command]},
    {id: 'ptyxis', name: 'Ptyxis', program: 'ptyxis', args: command => ['--new-window', '-x', shellJoin(command)]},
    {id: 'kitty', name: 'Kitty', program: 'kitty', args: command => [...command]},
    {id: 'alacritty', name: 'Alacritty', program: 'alacritty', args: command => ['-e', ...command]},
    {id: 'wezterm', name: 'WezTerm', program: 'wezterm', args: command => ['start', '--', ...command]},
    {id: 'foot', name: 'Foot', program: 'foot', args: command => [...command]},
    {id: 'konsole', name: 'Konsole', program: 'konsole', args: command => ['-e', ...command]},
    {id: 'xterm', name: 'xterm', program: 'xterm', args: command => ['-e', ...command]},
];

// "Automatic": the desktop's own idea of a default terminal, in the order
// the first builds used.
const AUTOMATIC = [
    {name: 'the default terminal', program: 'xdg-terminal-exec', args: command => [...command]},
    TERMINALS.find(terminal => terminal.id === 'ptyxis'),
    TERMINALS.find(terminal => terminal.id === 'gnome-terminal'),
    {name: 'the default terminal', program: 'x-terminal-emulator', args: command => ['-e', ...command]},
];

function shellJoin(argv) {
    return argv.map(arg => GLib.shell_quote(arg)).join(' ');
}

// GNOME Shell's PATH often lacks the per-user folders CLIs install into.
export function searchDirs() {
    const home = GLib.get_home_dir();
    const dirs = (GLib.getenv('PATH') || '').split(':').concat([
        `${home}/.local/bin`, `${home}/.opencode/bin`, `${home}/.npm-global/bin`, `${home}/.bun/bin`,
        `${home}/.cargo/bin`, `${home}/.local/share/mise/shims`, '/snap/bin',
    ]);
    return [...new Set(dirs.filter(Boolean))];
}

function isProgram(path) {
    return GLib.file_test(path, GLib.FileTest.IS_EXECUTABLE) && !GLib.file_test(path, GLib.FileTest.IS_DIR);
}

export function findProgram(name) {
    if (!name)
        return null;
    const expanded = name.startsWith('~/') ? GLib.get_home_dir() + name.slice(1) : name;
    if (expanded.includes('/'))
        return isProgram(expanded) ? expanded : null;
    for (const dir of searchDirs()) {
        const path = `${dir}/${expanded}`;
        if (isProgram(path))
            return path;
    }
    return null;
}

export function installedTerminals(find = findProgram) {
    return TERMINALS.filter(terminal => find(terminal.program));
}

function parse(text) {
    const trimmed = String(text || '').trim();
    if (trimmed === '')
        return {words: []};
    try {
        const [, words] = GLib.shell_parse_argv(trimmed);
        return {words};
    } catch (e) {
        return {error: e.message};
    }
}

// A custom terminal command. `{command}` on its own becomes the agent's
// arguments; inside a longer argument (`--exec={command}`) it becomes one
// quoted string; with no `{command}` at all the agent goes at the end.
export function fillTemplate(template, command) {
    const {words, error} = parse(template);
    if (error)
        return {error: `The custom terminal command can't be read: ${error}`};
    if (words.length === 0)
        return {error: 'Enter a custom terminal command in the settings.'};
    let used = false;
    const argv = [];
    for (const word of words) {
        if (word === '{command}') {
            argv.push(...command);
            used = true;
        } else if (word.includes('{command}')) {
            argv.push(word.replaceAll('{command}', shellJoin(command)));
            used = true;
        } else {
            argv.push(word);
        }
    }
    if (!used)
        argv.push(...command);
    return {argv};
}

export function launchSettings(settings) {
    return {
        agent: settings.get_string('agent'),
        agentCommand: settings.get_string('agent-command'),
        terminal: settings.get_string('terminal'),
        terminalCommand: settings.get_string('terminal-command'),
    };
}

// Returns {argv, agentName, terminalName}, or {error, reason, agentName}
// where reason is 'agent' (nothing to open) or 'terminal' (nowhere to open it).
export function resolveLaunch(prefs, find = findProgram) {
    let agentName;
    let command;
    if (prefs.agent === 'custom') {
        const {words, error} = parse(prefs.agentCommand);
        if (error)
            return {error: `The custom agent command can't be read: ${error}`, reason: 'agent', agentName: 'agent'};
        if (words.length === 0)
            return {error: 'Enter a custom agent command in the settings.', reason: 'agent', agentName: 'agent'};
        agentName = GLib.path_get_basename(words[0]);
        const path = find(words[0]);
        if (!path)
            return {error: `${words[0]} isn't installed.`, reason: 'agent', agentName};
        command = [path, ...words.slice(1)];
    } else {
        const agent = AGENTS.find(candidate => candidate.id === prefs.agent) ?? AGENTS[0];
        agentName = agent.name;
        const path = find(agent.command);
        if (!path)
            return {error: `${agent.name} isn't installed (no ${agent.command} found).`, reason: 'agent', agentName};
        command = [path];
    }

    const terminal = terminalArgv(prefs, command, find);
    if (terminal.error)
        return {error: terminal.error, reason: 'terminal', agentName};
    return {argv: terminal.argv, agentName, terminalName: terminal.terminalName};
}

// The chosen terminal, running `command` (an argv). Returns
// {argv, terminalName} or {error}.
export function terminalArgv(prefs, command, find = findProgram) {
    if (prefs.terminal === 'custom') {
        const filled = fillTemplate(prefs.terminalCommand, command);
        if (filled.error)
            return {error: filled.error};
        const program = find(filled.argv[0]);
        if (!program)
            return {error: `${filled.argv[0]}, from the custom terminal command, isn't installed.`};
        return {argv: [program, ...filled.argv.slice(1)], terminalName: GLib.path_get_basename(filled.argv[0])};
    }

    const chosen = TERMINALS.find(terminal => terminal.id === prefs.terminal);
    for (const terminal of chosen ? [chosen] : AUTOMATIC) {
        const program = find(terminal.program);
        if (program)
            return {argv: [program, ...terminal.args(command)], terminalName: terminal.name};
    }
    // A terminal picked by name that has since gone missing is an error, not
    // a reason to quietly open something else.
    return {error: chosen ? `${chosen.name} isn't installed.` : 'No terminal found. Pick one in the settings.'};
}

// The command line as a person would type it, for the settings window.
export function displayCommand(argv) {
    const home = GLib.get_home_dir();
    return argv.map(arg => {
        const shown = arg.startsWith(`${home}/`) ? `~${arg.slice(home.length)}` : arg;
        return /^[\w@%+=:,./~-]+$/.test(shown) ? shown : GLib.shell_quote(shown);
    }).join(' ');
}
