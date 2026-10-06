// Which agent sessions want you, for the robot's color. The agents' hooks
// (hooks/agent-usage-session for Claude Code, hooks/opencode-agent-usage.js
// for OpenCode) keep one small JSON file per session in
// ~/.local/state/omarchy/agents/sessions/:
//
//   {"agent": "claude", "session": "…", "state": "waiting", "since": …,
//    "updated": …, "pid": 4321, "cwd": "…"}
//
// `state` is idle, working, waiting (blocked on you: a permission, a
// question) or ready (finished its turn). `since` is when it got there, in
// epoch milliseconds. Opening the panel writes the time to `.seen` there, and
// turns that finished before it no longer count. Like usage.js, this imports
// nothing from GNOME Shell, so the tests run it under plain `gjs -m`.

export const STATES = ['idle', 'working', 'waiting', 'ready'];
export const SEEN_FILE = '.seen';
// A session nobody has touched for this long is left out, whatever it says.
export const MAX_AGE_MS = 24 * 60 * 60 * 1000;

function finite(value) {
    const n = Number(value);
    return value !== null && value !== '' && Number.isFinite(n) ? n : NaN;
}

// A session file's contents, or null when it isn't one.
export function parseSession(record) {
    if (!record || typeof record !== 'object')
        return null;
    const state = String(record.state ?? '');
    if (!STATES.includes(state))
        return null;
    const updated = finite(record.updated);
    const since = finite(record.since);
    return {
        agent: String(record.agent ?? ''),
        session: String(record.session ?? ''),
        state,
        since: Number.isFinite(since) ? since : updated,
        updated,
        pid: Number.isInteger(record.pid) && record.pid > 0 ? record.pid : null,
        // A subagent's session: it only counts while it waits for you.
        parent: record.parent ? String(record.parent) : null,
    };
}

// The sessions that still count: their process is running, and they were
// touched in the last MAX_AGE_MS. A closed terminal leaves its file behind.
export function liveSessions(records, {now = Date.now(), alive = () => true} = {}) {
    return records.map(parseSession).filter(session => session !== null &&
        Number.isFinite(session.updated) && now - session.updated <= MAX_AGE_MS &&
        (session.pid === null || alive(session.pid)));
}

// What the robot shows: 'waiting' while any session is blocked on you,
// 'ready' when one finished a turn since you last looked (`seen`), otherwise
// null for its usual color.
export function topBarSession(records, {now = Date.now(), seen = 0, alive = () => true} = {}) {
    const sessions = liveSessions(records, {now, alive});
    if (sessions.some(session => session.state === 'waiting'))
        return 'waiting';
    if (sessions.some(session => session.state === 'ready' && session.parent === null && session.since > seen))
        return 'ready';
    return null;
}

// `.seen`: the epoch milliseconds the panel was last opened, or 0.
export function parseSeen(text) {
    const n = finite(String(text ?? '').trim());
    return Number.isFinite(n) && n > 0 ? n : 0;
}
