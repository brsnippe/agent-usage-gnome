// Run with: gjs -m test/usage-test.js
import System from 'system';

import * as Usage from '../agent-usage@local/usage.js';

let failures = 0;
function check(name, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok)
        failures++;
    print(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n     got      ${JSON.stringify(actual)}\n     expected ${JSON.stringify(expected)}`}`);
}

const now = Date.now();
const iso = ms => new Date(ms).toISOString().replace('Z', '123+00:00');
const today = Usage.localDate(now);

const claude = {
    id: 'claude', name: 'Claude Code', tierLabel: 'Max 5x', usageStatusText: '', totalPrompts: 74,
    todayPrompts: 30, todaySessions: 1, hasPromptStats: true, updatedAt: iso(now - 60000),
    limits: [
        {label: 'Session (5-hour)', percent: 0.61, resetsAt: iso(now + 23 * 60000 + 5000)},
        {label: 'Weekly (7-day)', percent: 0.18, resetsAt: iso(now + 5 * 86400000 + 3600000)},
        {label: 'Opus 5 (1M context)', title: 'Fable Weekly', percent: 0, resetsAt: ''},
        {label: 'broken', percent: 'n/a'},
    ],
    recentDays: [{date: '2026-09-30', messageCount: 42700}, {date: today, messageCount: 103000000}],
    modelUsage: {
        'claude-opus-5-5': {inputTokens: 168, outputTokens: 50607, cacheReadInputTokens: 5013231, cacheCreationInputTokens: 289404},
        'claude-sonnet-4-5-20250929': {inputTokens: 10},
    },
};
const codex = {id: 'codex', name: 'Codex', usageStatusText: 'Codex unavailable', authHelpText: 'codex not found in PATH', totalPrompts: 3, limits: []};
const idle = {id: 'fireworks', name: 'Fireworks', totalPrompts: 0, limits: []};

check('microsecond timestamps parse', Usage.parseTime('2026-10-02T07:59:59.615034+00:00'), Date.parse('2026-10-02T07:59:59.615Z'));
check('Z timestamps parse', Usage.parseTime('2026-10-07T08:00:00Z'), Date.parse('2026-10-07T08:00:00Z'));
check('bad timestamps are NaN', [Usage.parseTime(''), Usage.parseTime('garbage')].map(Number.isNaN), [true, true]);
check('token formatting', [0, 999, 42700, 103000000, 2.5e9].map(Usage.formatTokens), ['0', '999', '42.7K', '103.0M', '2.5B']);
check('durations', [0, 59000, 23 * 60000 + 5000, 3 * 3600000 + 4 * 60000, 5 * 86400000 + 3600000].map(Usage.formatDuration),
    ['now', '1m', '23m', '3h 4m', '5d 1h']);
check('window titles', ['Session (5-hour)', '5h window', '30m window', 'Weekly (7-day)', 'Monthly', 'Something (else)'].map(Usage.windowTitle),
    ['Session', 'Session', 'Session', 'Weekly', 'Monthly', 'Something']);
check('limits keep collector titles and skip junk', Usage.limitWindows(claude).map(w => [w.title, w.percent]),
    [['Session', 0.61], ['Weekly', 0.18], ['Fable Weekly', 0]]);
check('model names', ['claude-opus-5-5', 'gpt-5.6-sol', 'claude-sonnet-4-5-20250929', 'deepseek-v3', ''].map(Usage.friendlyModelName),
    ['Opus 5.5', 'GPT 5.6 Sol', 'Sonnet 4.5', 'DeepSeek V3', 'Unknown']);
check('only agents with data show, sorted', Usage.visibleProviders([idle, codex, claude]).map(r => r.id), ['claude', 'codex']);
check('nothing to show', Usage.visibleProviders([idle]).length, 0);
check('top-bar percent is the fullest window', Usage.highestPercent([claude, codex]), 0.61);
check('no limits, no percent', Usage.highestPercent([codex]), null);
check('alarm at 90%', [Usage.isAlarming(claude), Usage.isAlarming({limits: [{label: '5h', percent: 0.9}]})], [false, true]);
check('balance alarm at 10% left', [
    Usage.isAlarming({balance: {remaining: 4, funded: 50}}),
    Usage.isAlarming({balance: {remaining: 20, funded: 50}}),
], [true, false]);
check('hero meta', [Usage.heroMeta(claude), Usage.heroMeta(codex), Usage.heroMeta({})], ['Max 5x', 'Codex unavailable', 'Subscription']);
check('sign-in problems offer the fix', [
    Usage.signInActions({id: 'claude', usageStatusText: 'Sign-in expired'}).map(action => action.label),
    Usage.signInActions({id: 'claude', usageStatusText: 'Waiting for auth'}).map(action => [action.command.join(' '), action.pause]),
    Usage.signInActions({id: 'codex', usageStatusText: 'Not signed in'}).map(action => [action.label, action.command.join(' ')]),
], [['Start Claude Code', 'Sign in'], [['claude', false], ['claude auth login', true]], [['Sign in', 'codex login']]]);
check('other problems offer none', [
    claude, codex, {id: 'claude', usageStatusText: 'Claude limits unavailable'}, {id: 'fireworks', usageStatusText: 'Not signed in'}, undefined,
].map(record => Usage.signInActions(record).length), [0, 0, 0, 0, 0]);
check('model rows sorted by total', Usage.modelRows(claude).map(r => [r.name, r.total]), [['Opus 5.5', 5353410], ['Sonnet 4.5', 10]]);
check('model detail', Usage.modelDetail(Usage.modelRows(claude)[0]), 'Opus 5.5 · in 168 · out 50.6K · cache 5.0M/289.4K');
check('day detail for today has prompts', Usage.dayDetail(claude.recentDays[1], true, claude).replace(/^\w+ \d+\/\d+/, 'DAY'),
    'DAY · 103.0M tokens · 30 prompts · 1 session');
check('day detail for other days', Usage.dayDetail(claude.recentDays[0], false, claude), 'Wed 9/30 · 42.7K tokens');
check('day names', ['2026-09-26', '2026-10-01', 'nope'].map(Usage.dayName), ['Sat', 'Thu', 'nope']);

const busyDay = {
    todayTotalTokens: 188400000,
    todayTokensByModel: {'claude-opus-5': 68300000, 'claude-opus-5-5': 120100000, 'claude-haiku-4-5': 0},
};
check("today's models, heaviest first, unused ones skipped", Usage.todayModelRows(busyDay).map(row => [row.name, row.total]),
    [['Opus 5.5', 120100000], ['Opus 5', 68300000]]);
check("today's share is of the whole day", Usage.todayModelDetail(Usage.todayModelRows(busyDay)[0]), "Opus 5.5 · 64% of today's 188.4M");
const manyModels = {todayTokensByModel: Object.fromEntries([1, 2, 3, 4, 5, 6, 7, 8].map(n => [`claude-opus-4-${n}`, n * 1000]))};
const manyRows = Usage.todayModelRows(manyModels);
check("today's list stops at 6", [manyRows.length, manyRows[0].name, manyRows[5].name], [6, 'Opus 4.8', 'Opus 4.3']);
check('shares still count the models past the cap', Usage.todayModelDetail(manyRows[0]), "Opus 4.8 · 22% of today's 36.0K");
check('no usage today, no rows', [
    Usage.todayModelRows({todayTokensByModel: {}}).length,
    Usage.todayModelRows({}).length,
    Usage.todayModelRows({todayTokensByModel: null}).length,
], [0, 0, 0]);
check('last updated', Usage.lastUpdated([claude, codex]), Usage.parseTime(claude.updatedAt));

const at1321 = new Date(2026, 9, 2, 13, 21).getTime();
const stale = {...claude, limitsStale: true, limitsFetchedAt: new Date(at1321).toISOString(), limitsNote: 'Anthropic is rate limiting checks · next try 13:58'};
check('fresh limits keep the plain title', [Usage.limitsStale(claude), Usage.limitsTitle(claude)], [false, 'LIMITS']);
check('stale limits say when they were measured', [Usage.limitsStale(stale), Usage.limitsTitle(stale)], [true, 'LIMITS · AS OF 13:21']);
check('and why', Usage.limitsNote(stale), 'Anthropic is rate limiting checks · next try 13:58');
check('stale without a time or reason still says so', [Usage.limitsTitle({...stale, limitsFetchedAt: ''}), Usage.limitsNote({...stale, limitsNote: ''})],
    ['LIMITS · NOT CURRENT', 'These limits are from an earlier check.']);
check('a stale flag with no limits is ignored', Usage.limitsStale({limitsStale: true, limits: []}), false);
check('"updated" uses the limits check when there is one', Usage.updatedAt(stale), at1321);
check('…and is unknown without any timestamp', Number.isNaN(Usage.updatedAt(codex)), true);
check('…and the record time otherwise', Usage.updatedAt({updatedAt: claude.updatedAt}), Usage.parseTime(claude.updatedAt));
check('clock', Usage.formatClock(new Date(2026, 9, 2, 9, 5).getTime()), '09:05');

print(failures === 0 ? '\nall passed' : `\n${failures} failed`);
if (failures)
    System.exit(1);
