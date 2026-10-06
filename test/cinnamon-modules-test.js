// Run with: gjs -m test/cinnamon-modules-test.js
//
// The Cinnamon applet loads the shared modules after cinnamon/esm-to-cinnamon.py
// has rewritten them. This converts them and loads the result both ways
// Cinnamon does: 6.0 to 6.6 evaluate the file with require() in scope (copied
// from Cinnamon's fileUtils.js), 6.8 imports it natively. Either way it has to
// export what the ES module exports, and give the same answers.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';

import * as Terminals from '../agent-usage@local/terminals.js';
import * as Updates from '../agent-usage@local/updates.js';
import * as Usage from '../agent-usage@local/usage.js';
import * as Versions from '../agent-usage@local/versions.js';

let failures = 0;
function check(name, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok)
        failures++;
    print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`);
}

const ROOT = GLib.path_get_dirname(GLib.path_get_dirname(import.meta.url.replace('file://', '')));
const CONVERTER = `${ROOT}/cinnamon/esm-to-cinnamon.py`;
const TMP = GLib.dir_make_tmp('agent-usage-cinnamon-XXXXXX');
const APPLET = `${TMP}/applet`;
GLib.mkdir_with_parents(APPLET, 0o755);
GLib.mkdir_with_parents(`${TMP}/fake/ui`, 0o755);

function write(path, text) {
    GLib.file_set_contents(path, text);
}

function read(path) {
    return new TextDecoder().decode(GLib.file_get_contents(path)[1]);
}

function convert(source) {
    const proc = Gio.Subprocess.new(['python3', CONVERTER, source],
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
    const [, stdout, stderr] = proc.communicate_utf8(null, null);
    return {ok: proc.get_successful(), stdout, stderr: stderr.trim()};
}

const MODULES = {usage: Usage, updates: Updates, versions: Versions, terminals: Terminals};
for (const name of [...Object.keys(MODULES), 'panel']) {
    const result = convert(`${ROOT}/agent-usage@local/${name}.js`);
    check(`${name}.js converts`, result.stderr, '');
    write(`${APPLET}/${name}.js`, result.stdout);
}

// A module of our own that imports a sibling, as panel.js does; panel.js
// itself needs St, which only a running Cinnamon has.
write(`${TMP}/sibling.js`, [
    "import * as Usage from './usage.js';",
    "import {isNewer} from './versions.js';",
    '',
    'export function tokens(n) {',
    '    return Usage.formatTokens(n);',
    '}',
    '',
    "export const NEWER = isNewer('0.11.0', '0.10.0');",
].join('\n'));
write(`${APPLET}/sibling.js`, convert(`${TMP}/sibling.js`).stdout);

// Cinnamon's own imports.ui.extension: 6.8 has getCurrentExtension(), whose
// importer this test supplies; before 6.8 there is none.
write(`${TMP}/fake/ui/extension.js`, 'function getCurrentExtension() { return globalThis.agentUsageXlet ?? null; }\n');
imports.searchPath.unshift(`${TMP}/fake`);

// ---- Cinnamon 6.0 to 6.6: fileUtils.requireModule and createExports.
const loaded = new Map();
function requireModule(path) {
    path = `${APPLET}/${path.replace(/^\.\//, '').replace(/\.js$/, '')}.js`;
    if (loaded.has(path))
        return loaded.get(path);
    let JS = read(path);
    const exportsRegex = /^module\.exports(\.[a-zA-Z0-9_$]+)?\s*=/m;
    const varRegex = /^(?:'use strict';){0,}(const|var|let|function|class)\s+([a-zA-Z0-9_$]+)/gm;
    const giImportNames = ['Gio', 'GLib', 'St', 'Clutter', 'Pango', 'Cinnamon'];
    let match;
    if (!exportsRegex.test(JS)) {
        while ((match = varRegex.exec(JS)) != null) {
            if (match.index === varRegex.lastIndex)
                varRegex.lastIndex++;
            if (match[2] && giImportNames.indexOf(match[2]) === -1)
                JS += `exports.${match[2]} = typeof ${match[2]} !== 'undefined' ? ${match[2]} : null;`;
        }
    }
    JS += `return module.exports;//# sourceURL=${path}`;
    const exports = {};
    const module = {exports};
    const evaluate = (0).constructor.constructor('require', 'exports', 'module', JS);
    if (path.endsWith('/panel.js'))
        return null; // compiled, so its syntax is fine; running it needs St
    const result = evaluate.call(exports, requireModule, exports, module);
    loaded.set(path, result);
    return result;
}

// ---- Cinnamon 6.8: the native importer, through getCurrentExtension().
imports.searchPath.unshift(TMP);
globalThis.agentUsageXlet = null;
const before68 = {};
for (const name of [...Object.keys(MODULES), 'sibling', 'panel'])
    before68[name] = requireModule(`./${name}`);
globalThis.agentUsageXlet = {imports: imports.applet};
const native68 = {};
for (const name of [...Object.keys(MODULES), 'sibling'])
    native68[name] = imports.applet[name];

const kinds = module => Object.fromEntries(Object.entries(module).map(([key, value]) => [key, typeof value]));
for (const [name, esm] of Object.entries(MODULES)) {
    for (const [version, converted] of [['6.0–6.6', before68[name]], ['6.8', native68[name]]]) {
        const exported = Object.fromEntries(Object.keys(esm).map(key => [key, typeof converted[key]]));
        check(`${name}.js on Cinnamon ${version} exports what the ES module does`, exported, kinds(esm));
    }
}

for (const [version, modules] of [['6.0–6.6', before68], ['6.8', native68]]) {
    const {usage, updates, versions, terminals, sibling} = modules;
    check(`Cinnamon ${version}: formatting and model names`,
        [usage.formatTokens(1234567), usage.friendlyModelName('claude-opus-4-8'), usage.windowTitle('5h window')],
        [Usage.formatTokens(1234567), Usage.friendlyModelName('claude-opus-4-8'), Usage.windowTitle('5h window')]);
    const queue = new updates.UpdateQueue();
    check(`Cinnamon ${version}: the update queue`,
        [queue.request('normal'), queue.request('force'), queue.finish(), updates.updateArgv('u', {kind: 'limits', agents: ['claude']})],
        [{kind: 'normal', agents: []}, null, {kind: 'force', agents: []}, ['u', '--limits-only', 'claude']]);
    check(`Cinnamon ${version}: versions`, [versions.isNewer('0.11.0', '0.10.0'), versions.isNewer('0.10.0', '0.10.0-dev+abc')], [true, false]);
    const find = name => ({opencode: '/usr/bin/opencode', 'gnome-terminal': '/usr/bin/gnome-terminal', tilix: '/usr/bin/tilix'})[name] ?? null;
    const prefs = {agent: 'opencode', agentCommand: '', terminal: 'auto', terminalCommand: '', preferredTerminal: terminals.preferredTerminal('tilix', '-e')};
    check(`Cinnamon ${version}: terminals`, terminals.resolveLaunch(prefs, find, () => null), Terminals.resolveLaunch(prefs, find, () => null));
    check(`Cinnamon ${version}: a module that imports its siblings`, [sibling.tokens(1500), sibling.NEWER], ['1.5K', true]);
}
check('panel.js compiles for Cinnamon', before68.panel, null);
check("panel.js loads its siblings through the loader", read(`${APPLET}/panel.js`).match(/_load\('[\w-]+'\)/g),
    ["_load('terminals')", "_load('updates')", "_load('usage')", "_load('versions')"]);

// What the converter refuses rather than gets wrong.
const refused = {
    'a default export': 'export default class Thing {}\n',
    'an export list': 'const a = 1;\nexport {a};\n',
    'an import spread over lines': "import {\n    a,\n} from './usage.js';\n",
    'an import from outside the applet': "import * as Main from 'resource:///org/gnome/shell/ui/main.js';\n",
    'import.meta': 'const here = import.meta.url;\n',
    'a dynamic import': "const later = import('./usage.js');\n",
    "a class that doesn't close on its own line": 'export class Open {\n    x() {}\n  }\n',
};
for (const [what, source] of Object.entries(refused)) {
    write(`${TMP}/bad.js`, source);
    const result = convert(`${TMP}/bad.js`);
    check(`refuses ${what}`, [result.ok, result.stderr.startsWith('esm-to-cinnamon: bad.js:')], [false, true]);
}

GLib.spawn_command_line_sync(`rm -rf ${GLib.shell_quote(TMP)}`);
print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
