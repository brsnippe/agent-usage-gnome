// Data shaping and formatting for the agent usage panel, ported from
// Omarchy's omarchy.agents widget (Main.qml and Panel.qml). It imports
// nothing from GNOME Shell, so the tests run it under plain `gjs -m`.

export const ALARM_RATIO = 0.9;
const MAX_MODELS = 4;
const MAX_TODAY_MODELS = 6;
const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export function number(value) {
    const n = Number(value || 0);
    return Number.isFinite(n) ? Math.round(n) : 0;
}

export function clamp(value, lo = 0, hi = 1) {
    return Math.max(lo, Math.min(hi, value));
}

export function formatTokens(value) {
    const n = number(value);
    if (n >= 1e9)
        return `${(n / 1e9).toFixed(1)}B`;
    if (n >= 1e6)
        return `${(n / 1e6).toFixed(1)}M`;
    if (n >= 1e3)
        return `${(n / 1e3).toFixed(1)}K`;
    return String(n);
}

export function formatDuration(ms) {
    if (!(ms > 0))
        return 'now';
    const minutes = Math.floor(ms / 60000);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    if (days > 0)
        return `${days}d ${hours % 24}h`;
    if (hours > 0)
        return `${hours}h ${minutes % 60}m`;
    return `${Math.max(1, minutes)}m`;
}

export function formatMoney(value, currency) {
    const code = String(currency || 'USD').toUpperCase();
    const prefix = {USD: '$', EUR: '€', GBP: '£'}[code] ?? `${code} `;
    const amount = Number(value);
    return prefix + (Number.isFinite(amount) ? amount : 0).toFixed(2);
}

export function formatClock(ms) {
    const date = new Date(ms);
    const pad = n => String(n).padStart(2, '0');
    return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function plural(count, word) {
    return `${count} ${word}${count === 1 ? '' : 's'}`;
}

// All-time counts run into the thousands; shorten them the way tokens are.
function compactPlural(count, word) {
    return `${formatTokens(count)} ${word}${count === 1 ? '' : 's'}`;
}

// Epoch milliseconds, or NaN. JS dates stop at milliseconds and the
// collectors write microseconds, so trim the fraction first.
export function parseTime(value) {
    const text = String(value || '').trim();
    if (!text)
        return NaN;
    return Date.parse(text.replace(/\.(\d{3})\d+/, '.$1'));
}

export function localDate(ms) {
    const date = new Date(ms);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function dayName(date) {
    const parsed = new Date(`${date}T00:00:00`);
    return Number.isNaN(parsed.getTime()) ? String(date || '') : DAY_NAMES[parsed.getDay()];
}

// Model ids arrive hyphenated with the version split across segments
// (`claude-opus-4-8`, `gpt-5.6-sol`). Rejoin the numeric run into one version
// and title-case the words around it.
export function friendlyModelName(id) {
    if (!id)
        return 'Unknown';
    const name = String(id).replace(/^claude-/, '').replace(/-\d{8}$/, '');
    const words = [];
    let version = [];
    for (const part of name.split('-')) {
        if (part === '')
            continue;
        if (/^\d/.test(part)) {
            version.push(part);
            continue;
        }
        if (version.length > 0) {
            words.push(version.join('.'));
            version = [];
        }
        if (part === 'gpt')
            words.push('GPT');
        else if (part === 'deepseek')
            words.push('DeepSeek');
        else
            words.push(part.charAt(0).toUpperCase() + part.slice(1));
    }
    if (version.length > 0)
        words.push(version.join('.'));
    return words.length > 0 ? words.join(' ') : 'Unknown';
}

// ------------------------------------------------------------------ limits

// Claude spells its windows out ("Session (5-hour)"), Codex abbreviates them
// ("5h window", "30m window"). Both have to land on the same title.
function windowIsLong(text) {
    return ['week', '7-day', 'seven', 'month', '30-day'].some(key => text.includes(key));
}

export function windowTitle(label) {
    const text = String(label || '').toLowerCase();
    if (text.includes('month'))
        return 'Monthly';
    if (windowIsLong(text))
        return 'Weekly';
    const spans = /(\d+)\s*-?\s*h(?:our)?\b/.test(text) || /(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/.test(text);
    if (text.includes('session') || spans)
        return 'Session';
    const plain = String(label || '').replace(/\s*\(.*\)\s*/, '').trim();
    return plain === '' ? 'Limit' : plain;
}

export function limitWindows(record) {
    const windows = [];
    for (const entry of record?.limits ?? []) {
        if (!entry || typeof entry !== 'object')
            continue;
        const percent = Number(entry.percent);
        if (!Number.isFinite(percent) || percent < 0)
            continue;
        // A collector that already knows which window a limit belongs to says
        // so; that beats reading it back out of a label like "Opus 5 (1M context)".
        const title = String(entry.title || '') !== '' ? String(entry.title) : windowTitle(entry.label);
        windows.push({title, percent, resetMs: parseTime(entry.resetsAt)});
    }
    return windows;
}

// Collectors that fall back to a cached reading (rate limited, offline,
// signed out) mark it stale and say when it was measured.
export function limitsStale(record) {
    return record?.limitsStale === true && limitWindows(record).length > 0;
}

export function limitsTitle(record) {
    if (!limitsStale(record))
        return 'LIMITS';
    const measured = parseTime(record.limitsFetchedAt);
    return Number.isFinite(measured) ? `LIMITS · AS OF ${formatClock(measured)}` : 'LIMITS · NOT CURRENT';
}

export function limitsNote(record) {
    return String(record?.limitsNote || '') || 'These limits are from an earlier check.';
}

// When the panel's numbers were last measured: the limits check if the
// collector reports one, otherwise the record itself.
export function updatedAt(record) {
    const limits = parseTime(record?.limitsFetchedAt);
    return Number.isFinite(limits) ? limits : parseTime(record?.updatedAt);
}

export function balanceValue(raw) {
    if (!raw || typeof raw !== 'object')
        return null;
    const remaining = Number(raw.remaining);
    if (!Number.isFinite(remaining) || remaining < 0)
        return null;
    const funded = Number(raw.funded);
    return {
        remaining,
        funded: Number.isFinite(funded) && funded > 0 ? funded : 0,
        spent: Math.max(0, Number(raw.spent) || 0),
        currency: String(raw.currency || 'USD'),
        estimated: raw.estimated === true,
    };
}

export function balanceDetail(balance) {
    if (!balance || !(balance.funded > 0))
        return '';
    const text = `${formatMoney(balance.spent, balance.currency)} spent of ${formatMoney(balance.funded, balance.currency)} funded`;
    return balance.estimated ? `${text} · estimated` : text;
}

export function balanceAlarming(balance) {
    return !!balance && balance.funded > 0 && balance.remaining / balance.funded <= 1 - ALARM_RATIO;
}

// --------------------------------------------------------------- providers

// An agent earns a place in the panel by having produced numbers. With none,
// the whole indicator stays out of the top bar.
export function hasData(record) {
    const counts = ['totalPrompts', 'totalSessions', 'activeDays', 'todayPrompts', 'todaySessions'];
    return counts.some(key => number(record?.[key]) > 0) ||
        limitWindows(record).length > 0 || balanceValue(record?.balance) !== null;
}

export function visibleProviders(records) {
    return records
        .filter(record => record && record.id && hasData(record))
        .sort((a, b) => String(a.id).localeCompare(String(b.id)));
}

export function isAlarming(record) {
    return limitWindows(record).some(window => window.percent >= ALARM_RATIO) ||
        balanceAlarming(balanceValue(record?.balance));
}

// The fullest window across every agent: the number in the top bar.
export function highestPercent(records) {
    let highest = null;
    for (const record of records) {
        for (const window of limitWindows(record))
            highest = highest === null ? window.percent : Math.max(highest, window.percent);
    }
    return highest;
}

// The number in the top bar: the fullest session window once it reaches
// `sessionFrom` percent, even when a weekly window is fuller; until then the
// fullest window. Compared as shown, so a session that reads "40%" counts as 40.
export function topBarPercent(records, sessionFrom) {
    let session = null;
    for (const record of records) {
        for (const window of limitWindows(record)) {
            if (window.title === 'Session')
                session = session === null ? window.percent : Math.max(session, window.percent);
        }
    }
    if (session !== null && Math.round(session * 100) >= sessionFrom)
        return session;
    return highestPercent(records);
}

// The plan you pay for, or the problem that's in the way.
export function heroMeta(record) {
    const status = String(record?.usageStatusText || '');
    if (status !== '')
        return status;
    const tier = String(record?.tierLabel || '');
    return tier === '' ? 'Subscription' : tier.charAt(0).toUpperCase() + tier.slice(1);
}

// When the problem is the sign-in, the problem card offers the fix: a
// command-line tool to run in the terminal. `pause` keeps the window open
// afterwards, so the outcome can be read.
const SIGN_IN = {
    claude: {
        statuses: ['Waiting for auth', 'Sign-in expired'],
        actions: [
            {label: 'Start Claude Code', command: ['claude'], pause: false},
            {label: 'Sign in', command: ['claude', 'auth', 'login'], pause: true},
        ],
    },
    codex: {
        statuses: ['Not signed in'],
        actions: [{label: 'Sign in', command: ['codex', 'login'], pause: true}],
    },
};

export function signInActions(record) {
    const known = SIGN_IN[String(record?.id || '')];
    if (!known || !known.statuses.includes(String(record?.usageStatusText || '')))
        return [];
    return known.actions;
}

export function recentDays(record) {
    return (record?.recentDays ?? []).filter(day => day && typeof day === 'object');
}

export function dayDetail(day, isToday, record) {
    const parsed = new Date(`${day.date}T00:00:00`);
    const label = Number.isNaN(parsed.getTime())
        ? String(day.date)
        : `${dayName(day.date)} ${parsed.getMonth() + 1}/${parsed.getDate()}`;
    let text = `${label} · ${formatTokens(day.messageCount)} tokens`;
    // Prompt and session counts only exist for today. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (isToday && record?.hasPromptStats !== false)
        text += ` · ${plural(number(record.todayPrompts), 'prompt')} · ${plural(number(record.todaySessions), 'session')}`;
    return text;
}

function allModelRows(record) {
    const rows = [];
    for (const [id, raw] of Object.entries(record?.modelUsage ?? {})) {
        const bucket = raw && typeof raw === 'object' ? raw : {};
        const row = {
            name: friendlyModelName(id),
            input: number(bucket.inputTokens),
            output: number(bucket.outputTokens),
            cacheRead: number(bucket.cacheReadInputTokens),
            cacheWrite: number(bucket.cacheCreationInputTokens),
        };
        row.total = row.input + row.output + row.cacheRead + row.cacheWrite;
        rows.push(row);
    }
    rows.sort((a, b) => b.total - a.total);
    return rows;
}

export function modelRows(record) {
    return allModelRows(record).slice(0, MAX_MODELS);
}

// Every model counts, also the ones past the list's cap.
export function allTimeTotal(record) {
    return allModelRows(record).reduce((sum, row) => sum + row.total, 0);
}

export function allTimeTitle(record) {
    return `ALL TIME BY MODEL · ${formatTokens(allTimeTotal(record))}`;
}

// The heading's hover: the all-time counts behind the total. Agents without
// prompt stats leave out prompts and sessions, as on the day rows; zeros are
// gaps, not counts.
export function allTimeDetail(record) {
    const parts = [];
    if (record?.hasPromptStats !== false) {
        const sessions = number(record?.totalSessions);
        const prompts = number(record?.totalPrompts);
        if (sessions > 0)
            parts.push(compactPlural(sessions, 'session'));
        if (prompts > 0)
            parts.push(compactPlural(prompts, 'prompt'));
    }
    const days = number(record?.activeDays);
    if (days > 0)
        parts.push(compactPlural(days, 'day'));
    return parts.length > 0 ? parts.join(' · ') : null;
}

// Today's tokens per model. Collectors only total these per model, without
// the input/output/cache split the all-time rows carry.
export function todayModelRows(record) {
    const byModel = record?.todayTokensByModel;
    if (!byModel || typeof byModel !== 'object')
        return [];
    const rows = Object.entries(byModel)
        .map(([id, tokens]) => ({name: friendlyModelName(id), total: number(tokens)}))
        .filter(row => row.total > 0)
        .sort((a, b) => b.total - a.total);
    // Shares are of the day's whole total, which can include models past the cap.
    const dayTotal = Math.max(number(record.todayTotalTokens), rows.reduce((sum, row) => sum + row.total, 0));
    for (const row of rows)
        row.share = dayTotal > 0 ? row.total / dayTotal : 0;
    return rows.slice(0, MAX_TODAY_MODELS).map(row => ({...row, dayTotal}));
}

export function todayModelDetail(row) {
    return `${row.name} · ${Math.round(row.share * 100)}% of today's ${formatTokens(row.dayTotal)}`;
}

export function modelDetail(row) {
    return `${row.name} · in ${formatTokens(row.input)} · out ${formatTokens(row.output)} · ` +
        `cache ${formatTokens(row.cacheRead)}/${formatTokens(row.cacheWrite)}`;
}

// Everything the panel draws, minus the timestamps every check rewrites: two
// records with the same key look identical on screen.
export function displayKey(records) {
    return JSON.stringify(records.map(({updatedAt, retryAdvised, ...shown}) => shown));
}

export function lastUpdated(records) {
    const times = records.map(record => parseTime(record.updatedAt)).filter(Number.isFinite);
    return times.length > 0 ? Math.max(...times) : NaN;
}
