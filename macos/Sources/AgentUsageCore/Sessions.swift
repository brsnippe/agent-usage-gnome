import Foundation
#if canImport(Glibc)
import Glibc
#endif

// Which agent sessions want you, for the robot's colour: sessions.js from the
// GNOME extension. The agents' hooks (agent-usage-session for Claude Code,
// opencode-agent-usage.js for OpenCode) keep one small JSON file per session
// in ~/.local/state/omarchy/agents/sessions/; opening the panel writes the
// time to `.seen` there.

public enum SessionState: String {
    case idle, working, waiting, ready
}

/// What the robot shows: orange while a session waits for you, green once one
/// finished a turn you haven't looked at.
public enum TopBarSession: String, Equatable {
    case waiting, ready
}

public struct AgentSession: Equatable {
    public var agent: String
    public var session: String
    public var state: SessionState
    /// When it got to this state, and when its file was last written, in
    /// epoch milliseconds.
    public var since: Double
    public var updated: Double
    public var pid: Int32?
    /// A subagent's session: it only counts while it waits for you.
    public var parent: String?

    /// A session file's contents, or nil when it isn't one.
    public init?(_ value: JSONValue?) {
        guard let fields = value?.objectValue, case .string(let raw)? = fields["state"], let state = SessionState(rawValue: raw) else {
            return nil
        }
        self.state = state
        agent = JS.text(fields["agent"])
        session = JS.text(fields["session"])
        updated = Sessions.finite(fields["updated"])
        let since = Sessions.finite(fields["since"])
        self.since = since.isFinite ? since : updated
        if case .number(let n)? = fields["pid"], n > 0, n == n.rounded(), n <= Double(Int32.max) {
            pid = Int32(n)
        }
        let parent = JS.text(fields["parent"])
        self.parent = parent.isEmpty ? nil : parent
    }
}

public enum Sessions {
    public static let seenFile = ".seen"
    /// A session nobody has touched for this long is left out, whatever it says.
    public static let maxAge: Double = 24 * 60 * 60 * 1000
    /// Alerts this close after the last one, in milliseconds, merge into it.
    public static let alertMerge: Double = 3000

    public static func directory(environment: [String: String], home: String) -> String {
        let state = environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.local/state"
        return "\(state)/omarchy/agents/sessions"
    }

    /// The session files, by name. One mid-write or malformed is skipped
    /// until the next change.
    public static func load(from dir: String) -> [JSONValue] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .sorted()
            .compactMap { name in
                FileManager.default.contents(atPath: "\(dir)/\(name)").flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            }
    }

    /// The sessions that still count: their process is running, and they
    /// were touched in the last `maxAge`. A closed terminal leaves its file
    /// behind.
    public static func live(_ records: [JSONValue], now: Double, alive: (Int32) -> Bool) -> [AgentSession] {
        records.compactMap(AgentSession.init).filter { session in
            session.updated.isFinite && now - session.updated <= maxAge && (session.pid.map(alive) ?? true)
        }
    }

    /// Waiting while any session is blocked on you; ready when one finished
    /// a turn since you last looked (`seen`); otherwise nil, the usual colour.
    public static func topBar(_ records: [JSONValue], now: Double, seen: Double, alive: (Int32) -> Bool) -> TopBarSession? {
        let sessions = live(records, now: now, alive: alive)
        if sessions.contains(where: { $0.state == .waiting }) {
            return .waiting
        }
        if sessions.contains(where: { $0.state == .ready && $0.parent == nil && $0.since > seen }) {
            return .ready
        }
        return nil
    }

    /// Whether the robot pops and sounds: `.waiting` when a session has
    /// started waiting for you since the last look, `.ready` when one has
    /// finished a turn you haven't seen, otherwise nil. `marks` is what the
    /// last look returned: each session's state and since, so every state
    /// alerts once, also when the robot already has that colour (a second
    /// session finishing). The first look (`marks` nil) only takes note, so
    /// starting up is quiet. Nothing alerts within `alertMerge` of
    /// `lastAlert`, and waiting beats ready. The rules are the colours': a
    /// subagent alerts when it waits, not when it finishes.
    public static func alert(_ records: [JSONValue], now: Double, seen: Double, alive: (Int32) -> Bool,
                             marks: [String: String]?, lastAlert: Double) -> (alert: TopBarSession?, marks: [String: String]) {
        var next: [String: String] = [:]
        var alert: TopBarSession?
        for session in live(records, now: now, alive: alive) {
            let key = "\(session.agent)/\(session.session)"
            let mark = "\(session.state.rawValue)@\(session.since)"
            next[key] = mark
            guard let marks, marks[key] != mark else {
                continue
            }
            if session.state == .waiting {
                alert = .waiting
            } else if session.state == .ready, session.parent == nil, session.since > seen, alert == nil {
                alert = .ready
            }
        }
        if now >= lastAlert, now - lastAlert < alertMerge {
            alert = nil
        }
        return (alert, next)
    }

    /// `.seen`: the epoch milliseconds the panel was last opened, or 0.
    public static func parseSeen(_ text: String?) -> Double {
        let value = finite(.string(text ?? ""))
        return value.isFinite && value > 0 ? value : 0
    }

    public static func processRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// sessions.js's `finite`: a number, or NaN for null, "" and the rest.
    static func finite(_ value: JSONValue?) -> Double {
        switch value {
        case nil, .null?: return .nan
        case .string(let text)? where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: return .nan
        default:
            let n = JS.number(value)
            return n.isFinite ? n : .nan
        }
    }
}
