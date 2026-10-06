// Run with: gjs -m test/sessions-test.js
import System from 'system';

import * as Sessions from '../agent-usage@local/sessions.js';

let failures = 0;
function check(name, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok)
        failures++;
    print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`);
}

const now = 1_790_000_000_000;
const minute = 60_000;
const session = (state, extra = {}) => ({agent: 'claude', session: `s-${state}`, state, since: now - 5 * minute, updated: now - 5 * minute, pid: 100, ...extra});
const running = new Set([100, 200]);
const alive = pid => running.has(pid);
const robot = (records, seen = 0) => Sessions.topBarSession(records, {now, seen, alive});

check('nothing going on', robot([]), null);
check('working and idle sessions keep the usual color', robot([session('working'), session('idle')]), null);
check('a waiting session is orange', robot([session('waiting')]), 'waiting');
check('a finished turn is green', robot([session('ready')]), 'ready');
check('waiting beats ready', robot([session('ready'), session('waiting', {pid: 200})]), 'waiting');

check('opening the panel after the turn finished clears green', robot([session('ready')], now - minute), null);
check('a turn that finished after the panel was opened is green again', robot([session('ready', {since: now})], now - minute), 'ready');
check('opening the panel never clears orange', robot([session('waiting')], now), 'waiting');

check('a session whose agent is gone is left out', robot([session('waiting', {pid: 300})]), null);
check('one nobody touched for a day is left out', robot([session('waiting', {updated: now - Sessions.MAX_AGE_MS - 1})]), null);
check('without a pid, only its age counts', robot([session('ready', {pid: undefined})]), 'ready');

check("a subagent's finished turn isn't green", robot([session('ready', {parent: 'root'})]), null);
check('a subagent waiting for you is orange', robot([session('waiting', {parent: 'root'})]), 'waiting');

check('junk is skipped', robot([null, 'text', {state: 'sleeping', updated: now}, {state: 'waiting'}, session('ready')]), 'ready');
check('since falls back to updated', Sessions.parseSession({state: 'ready', updated: 5}).since, 5);
check('pids have to be whole and positive', [-1, 0, 1.5, '7', 7].map(pid => Sessions.parseSession({state: 'idle', updated: 1, pid}).pid),
    [null, null, null, null, 7]);
check('.seen parses', ['1790000000000\n', '', 'garbage', '-5'].map(Sessions.parseSeen), [1790000000000, 0, 0, 0]);

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
