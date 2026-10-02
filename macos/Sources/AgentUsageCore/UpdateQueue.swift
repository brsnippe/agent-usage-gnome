// Which update to run next, ported from the GNOME extension's updates.js. The
// panel asks for updates from several timers and buttons at once; only one
// runs at a time, and requests that arrive meanwhile merge into a single
// follow-up.

public enum UpdateKind: Int, Comparable {
    /// Only the rate-limit probes, reusing recent local scans.
    case limits = 1
    /// Everything, reusing caches younger than the collectors' windows.
    case normal = 2
    /// Everything, rescanned from scratch (a person pressed refresh).
    case force = 3

    public static func < (a: UpdateKind, b: UpdateKind) -> Bool {
        a.rawValue < b.rawValue
    }

    /// The collectors' flag for this kind of update.
    public var flags: [String] {
        switch self {
        case .limits: return ["--limits-only"]
        case .normal: return []
        case .force: return ["--force"]
        }
    }
}

public struct UpdateRequest: Equatable {
    public var kind: UpdateKind
    /// The agents to update. Empty means every agent.
    public var agents: [String]

    public init(kind: UpdateKind, agents: [String] = []) {
        self.kind = kind
        self.agents = agents
    }

    func covers(_ other: UpdateRequest) -> Bool {
        if agents.isEmpty {
            return true
        }
        if other.agents.isEmpty {
            return false
        }
        return other.agents.allSatisfy { agents.contains($0) }
    }

    func merged(with other: UpdateRequest) -> UpdateRequest {
        var agents: [String] = []
        if !self.agents.isEmpty && !other.agents.isEmpty {
            for agent in self.agents + other.agents where !agents.contains(agent) {
                agents.append(agent)
            }
        }
        return UpdateRequest(kind: max(kind, other.kind), agents: agents)
    }
}

public struct UpdateQueue {
    public private(set) var running: UpdateRequest?
    public private(set) var pending: UpdateRequest?

    public init() {}

    public var busy: Bool { running != nil }

    /// Returns the request to start now, or nil when it was queued behind the
    /// running one (or is already being done by it).
    public mutating func request(_ kind: UpdateKind, agents: [String] = []) -> UpdateRequest? {
        let request = UpdateRequest(kind: kind, agents: agents)
        guard let running else {
            self.running = request
            return request
        }
        // A routine check that the running update already covers would only
        // repeat it. A forced refresh always gets its own fresh run.
        if kind != .force && running.kind >= kind && running.covers(request) {
            return nil
        }
        pending = pending.map { $0.merged(with: request) } ?? request
        return nil
    }

    /// The running update finished. Returns the next request to start, or nil.
    public mutating func finish() -> UpdateRequest? {
        running = pending
        pending = nil
        return running
    }
}
