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

// ---- the pop and the sound
// Looks at `steps` one after another, as the panel does, and says what each
// look alerts. A step is the records, or {records, seen, at} (at: minutes
// after now).
function alerts(...steps) {
    let marks = null;
    let lastAlert = 0;
    return steps.map(step => {
        const {records, seen = 0, at = 0} = Array.isArray(step) ? {records: step} : step;
        const result = Sessions.sessionAlert(records, {now: now + at * minute, seen, alive, marks, lastAlert});
        marks = result.marks;
        if (result.alert)
            lastAlert = now + at * minute;
        return result.alert;
    });
}
const later = (state, minutes, extra = {}) => session(state, {session: 's', since: now + minutes * minute, updated: now + minutes * minute, ...extra});

check('the first look is quiet, whatever is there', alerts([session('waiting'), session('ready')]), [null]);
check('a session starting to wait alerts', alerts([later('working', 0)], {records: [later('waiting', 1)], at: 1}), [null, 'waiting']);
check('a session finishing its turn alerts', alerts([later('working', 0)], {records: [later('ready', 1)], at: 1}), [null, 'ready']);
check('a new session that already waits alerts', alerts([], {records: [later('waiting', 1)], at: 1}), [null, 'waiting']);
check('the same wait alerts once', alerts([], {records: [later('waiting', 1)], at: 1}, {records: [later('waiting', 1, {updated: now + 2 * minute})], at: 2}),
    [null, 'waiting', null]);
check('waiting again after working alerts again',
    alerts([], {records: [later('waiting', 1)], at: 1}, {records: [later('working', 2)], at: 2}, {records: [later('waiting', 3)], at: 3}),
    [null, 'waiting', null, 'waiting']);
check('a second session finishing alerts while the robot is already green',
    alerts([later('working', 0), later('working', 0, {session: 't', pid: 200})],
        {records: [later('ready', 1), later('working', 0, {session: 't', pid: 200})], at: 1},
        {records: [later('ready', 1), later('ready', 2, {session: 't', pid: 200})], at: 2}),
    [null, 'ready', 'ready']);
check('a turn already seen is quiet', alerts([later('working', 0)], {records: [later('ready', 1)], seen: now + 2 * minute, at: 2}), [null, null]);
check('opening the panel alerts nothing', alerts([later('ready', 0)], {records: [later('ready', 0)], seen: now + minute, at: 1}), [null, null]);
check("a subagent finishing is quiet", alerts([], {records: [later('ready', 1, {parent: 'root'})], at: 1}), [null, null]);
check('a subagent waiting for you alerts', alerts([], {records: [later('waiting', 1, {parent: 'root'})], at: 1}), [null, 'waiting']);
check('waiting beats ready', alerts([], {records: [later('ready', 1), later('waiting', 1, {session: 't', pid: 200})], at: 1}), [null, 'waiting']);
check("a session whose agent is gone is quiet", alerts([], {records: [later('waiting', 1, {pid: 300})], at: 1}), [null, null]);
check('alerts within 3 seconds merge into one',
    alerts([], {records: [later('ready', 1)], at: 1}, {records: [later('ready', 1), later('waiting', 1.02, {session: 't', pid: 200})], at: 1.02}),
    [null, 'ready', null]);
check('and after that they alert again',
    alerts([], {records: [later('ready', 1)], at: 1}, {records: [later('ready', 1), later('waiting', 1.1, {session: 't', pid: 200})], at: 1.1}),
    [null, 'ready', 'waiting']);
check('the marks are each live session, with its state and since',
    Sessions.sessionAlert([later('waiting', 1), later('idle', 0, {pid: 300})], {now, alive}).marks, {'claude/s': `waiting@${now + minute}`});

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
