// Run with: gjs -m test/versions-test.js
import System from 'system';

import * as Terminals from '../agent-usage@local/terminals.js';
import {compareVersions, isNewer, parseVersion} from '../agent-usage@local/versions.js';

let failures = 0;
function check(name, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok)
        failures++;
    print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`);
}

check('parses plain, v-prefixed and dev versions',
    ['0.6.0', 'v0.6.1', '0.6.1-dev+3f2a1c', ' 1.10.2 ', 'main', ''].map(parseVersion),
    [[0, 6, 0], [0, 6, 1], [0, 6, 1], [1, 10, 2], null, null]);
check('compares numerically, not as text', [compareVersions('0.10.0', '0.9.0'), compareVersions('0.6.0', '0.6.0'), compareVersions('0.6.0', '0.6.1')], [1, 0, -1]);
check('a newer release is newer', isNewer('0.6.1', '0.6.0'), true);
check('the same release is not', isNewer('0.6.0', '0.6.0'), false);
check('an older release is not', isNewer('0.5.9', '0.6.0'), false);
check('a dev build is not behind its own release', isNewer('0.6.0', '0.6.0-dev+abc'), false);
check('but is behind the next one', isNewer('0.6.1', '0.6.0-dev+abc'), true);
check('an install without a version is behind any release', isNewer('0.6.0', ''), true);
check('garbage from the remote never counts as an update', isNewer('error: fatal', '0.6.0'), false);

// The Update button runs `agent-usage update` in the chosen terminal.
const find = name => ({ghostty: '/usr/bin/ghostty', 'gnome-terminal': '/usr/bin/gnome-terminal'})[name] ?? null;
const update = ['/home/me/.local/bin/agent-usage', 'update', '--pause'];
check('update command in Ghostty', Terminals.terminalArgv({terminal: 'ghostty'}, update, find).argv,
    ['/usr/bin/ghostty', '-e', ...update]);
check('update command with the automatic terminal', Terminals.terminalArgv({terminal: 'auto'}, update, find).argv,
    ['/usr/bin/gnome-terminal', '--', ...update]);
check('a missing terminal is an error', Terminals.terminalArgv({terminal: 'kitty'}, update, find), {error: "Kitty isn't installed."});

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
