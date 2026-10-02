// Run with: gjs -m test/updates-test.js
import System from 'system';

import {UpdateQueue, updateArgv} from '../agent-usage@local/updates.js';
import {displayKey} from '../agent-usage@local/usage.js';

let failures = 0;
function check(name, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok)
        failures++;
    print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`);
}

let q = new UpdateQueue();
check('an idle queue starts the request', q.request('normal'), {kind: 'normal', agents: []});
check('then it is busy', q.busy, true);
check('a limits check during a full run is already covered', [q.request('limits'), q.pending], [null, null]);
check('a second full run during a full run is covered', [q.request('normal'), q.pending], [null, null]);
check('a forced refresh during a full run still queues', [q.request('force'), q.pending], [null, {kind: 'force', agents: []}]);
check('finishing starts the queued request', q.finish(), {kind: 'force', agents: []});
check('finishing with nothing queued goes idle', [q.finish(), q.busy], [null, false]);

// The bug this module exists for: with limits checks every 15 seconds, a
// limits check queued first must not swallow the 15-minute full rescan.
q = new UpdateQueue();
q.request('limits');
q.request('limits', ['claude']);
check('limits during limits is covered', q.pending, null);
q.request('normal');
check('a full rescan queued behind limits stays a full rescan', q.pending, {kind: 'normal', agents: []});
q.request('limits');
check('a later limits check does not downgrade it', q.pending, {kind: 'normal', agents: []});
check('so the rescan runs next', q.finish(), {kind: 'normal', agents: []});

// Retries name specific agents; merging widens rather than narrows.
q = new UpdateQueue();
q.request('limits', ['claude']);
q.request('limits', ['codex']);
check('a retry for another agent queues', q.pending, {kind: 'limits', agents: ['codex']});
q.request('limits', ['claude']);
check('a retry for the agent already being checked is covered', q.pending, {kind: 'limits', agents: ['codex']});
q.request('limits', ['fireworks']);
check('retries for several agents merge', q.pending, {kind: 'limits', agents: ['codex', 'fireworks']});
q.request('limits');
check('an all-agent check widens a named retry', q.pending, {kind: 'limits', agents: []});

q = new UpdateQueue();
q.request('limits', ['claude']);
check('an all-agent check is not covered by a one-agent run', [q.request('limits'), q.pending], [null, {kind: 'limits', agents: []}]);

check('argv for each kind', [
    updateArgv('/u', {kind: 'normal', agents: []}),
    updateArgv('/u', {kind: 'limits', agents: ['claude']}),
    updateArgv('/u', {kind: 'force', agents: []}),
], [['/u'], ['/u', '--limits-only', 'claude'], ['/u', '--force']]);

const a = {id: 'claude', updatedAt: '2026-10-02T09:00:00+00:00', limits: [{percent: 0.5}]};
const b = {...a, updatedAt: '2026-10-02T09:00:15+00:00', retryAdvised: true};
const c = {...b, limits: [{percent: 0.51}]};
check('a new timestamp alone does not change the display', displayKey([a]) === displayKey([b]), true);
check('a new number does', displayKey([b]) === displayKey([c]), false);

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
