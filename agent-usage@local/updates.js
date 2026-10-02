// Which update to run next. The panel asks for updates from several timers
// and buttons at once; only one runs at a time, and requests that arrive
// meanwhile merge into a single follow-up. No GNOME imports, so the tests
// run it under plain `gjs -m`.

// limits: only the rate-limit probes, reusing recent local scans.
// normal: everything, reusing caches younger than the collectors' windows.
// force:  everything, rescanned from scratch (a person pressed refresh).
const RANK = {limits: 1, normal: 2, force: 3};

// An empty agent list means every agent.
function covers(a, b) {
    if (a.agents.length === 0)
        return true;
    if (b.agents.length === 0)
        return false;
    return b.agents.every(agent => a.agents.includes(agent));
}

function merge(a, b) {
    return {
        kind: RANK[b.kind] > RANK[a.kind] ? b.kind : a.kind,
        agents: a.agents.length === 0 || b.agents.length === 0 ? [] : [...new Set([...a.agents, ...b.agents])],
    };
}

export class UpdateQueue {
    constructor() {
        this.running = null;
        this.pending = null;
    }

    get busy() {
        return this.running !== null;
    }

    // Returns the request to start now, or null when it was queued behind the
    // running one (or is already being done by it).
    request(kind, agents = []) {
        const request = {kind, agents: [...agents]};
        if (!this.running) {
            this.running = request;
            return request;
        }
        // A routine check that the running update already covers would only
        // repeat it. A forced refresh always gets its own fresh run.
        if (kind !== 'force' && RANK[this.running.kind] >= RANK[kind] && covers(this.running, request))
            return null;
        this.pending = this.pending ? merge(this.pending, request) : request;
        return null;
    }

    // The running update finished. Returns the next request to start, or null.
    finish() {
        this.running = this.pending;
        this.pending = null;
        return this.running;
    }
}

export function updateArgv(updater, {kind, agents}) {
    const argv = [updater];
    if (kind === 'force')
        argv.push('--force');
    else if (kind === 'limits')
        argv.push('--limits-only');
    return argv.concat(agents);
}
