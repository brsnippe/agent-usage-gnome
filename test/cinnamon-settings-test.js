// Run with: gjs -m test/cinnamon-settings-test.js
//
// The Cinnamon applet's settings (settings-schema.json, Cinnamon's own
// format) have to stay the GNOME extension's settings: the same keys, defaults
// and ranges, and the agents and terminals terminals.js knows.
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

const ROOT = GLib.path_get_dirname(GLib.path_get_dirname(import.meta.url.replace('file://', '')));
const read = path => new TextDecoder().decode(GLib.file_get_contents(`${ROOT}/${path}`)[1]);
const schema = JSON.parse(read('cinnamon/agent-usage@local/settings-schema.json'));
const gschema = read('agent-usage@local/schemas/org.gnome.shell.extensions.agent-usage.gschema.xml');
const applet = read('cinnamon/agent-usage@local/applet.js');

// GNOME's keys: name, type, default and range.
const gnomeKeys = [...gschema.matchAll(/<key name="([^"]+)" type="(.)">([\s\S]*?)<\/key>/g)].map(([, name, type, body]) => {
    const raw = body.match(/<default>(.*)<\/default>/)[1];
    const range = body.match(/<range min="(-?\d+)" max="(-?\d+)"\/>/);
    const value = type === 'i' ? Number(raw) : type === 'b' ? raw === 'true' : JSON.parse(raw);
    return {name, type, value, range: range ? [Number(range[1]), Number(range[2])] : null};
});
check("GNOME's schema has the keys this test expects", gnomeKeys.map(key => key.name),
    ['limits-interval', 'scan-interval', 'session-threshold', 'session-colors', 'session-pop', 'session-sounds', 'check-updates', 'agent', 'agent-command', 'terminal', 'terminal-command', 'right-click-opens-agent']);

const cinnamonType = {i: 'spinbutton', b: 'switch'};
for (const key of gnomeKeys) {
    const setting = schema[key.name] ?? {};
    const type = cinnamonType[key.type] ?? (setting.options ? 'combobox' : 'entry');
    check(`${key.name}: same type, default and range as on GNOME`,
        [setting.type, setting.default, key.range ? [setting.min, setting.max] : null],
        [type, key.value, key.range]);
}

check('agent choices match terminals.js', Object.values(schema.agent.options), [...Terminals.AGENTS.map(agent => agent.id), 'custom']);
check('terminal choices match terminals.js', Object.values(schema.terminal.options), ['auto', ...Terminals.TERMINALS.map(terminal => terminal.id), 'custom']);
check('agent names match terminals.js', Object.keys(schema.agent.options), [...Terminals.AGENTS.map(agent => agent.name), 'Custom…']);
check('terminal names match terminals.js', Object.keys(schema.terminal.options), ['Automatic', ...Terminals.TERMINALS.map(terminal => terminal.name), 'Custom…']);

// The layout shows every setting once, and only settings that exist.
const layout = schema.layout;
const shown = layout.pages.flatMap(page => layout[page].sections.flatMap(section => layout[section].keys));
const defined = Object.keys(schema).filter(key => key !== 'layout');
check('every setting is shown once', [...shown].sort(), [...defined].sort());

check('custom commands only show with Custom…', [schema['agent-command'].dependency, schema['terminal-command'].dependency],
    ['agent=custom', 'terminal=custom']);
check('the pop and the sounds only switch with session colors on', [schema['session-pop'].dependency, schema['session-sounds'].dependency],
    ['session-colors', 'session-colors']);
const buttons = defined.filter(key => schema[key].type === 'button').map(key => schema[key].callback);
check("the buttons call the applet's methods", buttons.map(callback => new RegExp(`^    ${callback}\\(\\) \\{$`, 'm').test(applet)),
    buttons.map(() => true));
check('the version line is there for the installer to fill in', schema.version?.type, 'label');

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
