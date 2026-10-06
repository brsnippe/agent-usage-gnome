import Foundation
import XCTest

@testable import AgentUsageCore

/// The same cases as test/sessions-test.js.
final class SessionsTests: XCTestCase {
    let now: Double = 1_790_000_000_000
    let minute: Double = 60_000
    let running: Set<Int32> = [100, 200]

    func session(_ state: String, _ extra: [String: JSONValue] = [:]) -> JSONValue {
        var fields: [String: JSONValue] = ["agent": "claude", "session": .string("s-\(state)"), "state": .string(state),
                                           "since": .number(now - 5 * minute), "updated": .number(now - 5 * minute), "pid": 100]
        fields.merge(extra) { _, new in new }
        return .object(fields)
    }

    func robot(_ records: [JSONValue], seen: Double = 0) -> TopBarSession? {
        Sessions.topBar(records, now: now, seen: seen, alive: { self.running.contains($0) })
    }

    func testColours() {
        XCTAssertNil(robot([]), "nothing going on")
        XCTAssertNil(robot([session("working"), session("idle")]), "working and idle sessions keep the usual colour")
        XCTAssertEqual(robot([session("waiting")]), .waiting)
        XCTAssertEqual(robot([session("ready")]), .ready)
        XCTAssertEqual(robot([session("ready"), session("waiting", ["pid": 200])]), .waiting, "waiting beats ready")
    }

    func testOpeningThePanel() {
        XCTAssertNil(robot([session("ready")], seen: now - minute), "opening the panel after the turn finished clears green")
        XCTAssertEqual(robot([session("ready", ["since": .number(now)])], seen: now - minute), .ready, "a later turn is green again")
        XCTAssertEqual(robot([session("waiting")], seen: now), .waiting, "opening the panel never clears orange")
    }

    func testLeftBehind() {
        XCTAssertNil(robot([session("waiting", ["pid": 300])]), "a session whose agent is gone is left out")
        XCTAssertNil(robot([session("waiting", ["updated": .number(now - Sessions.maxAge - 1)])]), "one nobody touched for a day")
        XCTAssertEqual(robot([session("ready", ["pid": nil])]), .ready, "without a pid, only its age counts")
    }

    func testSubagents() {
        XCTAssertNil(robot([session("ready", ["parent": "root"])]), "a subagent's finished turn isn't green")
        XCTAssertEqual(robot([session("waiting", ["parent": "root"])]), .waiting, "a subagent waiting for you is orange")
    }

    func testParsing() {
        XCTAssertEqual(robot([nil, "text", ["state": "sleeping", "updated": .number(now)], ["state": "waiting"], session("ready")]), .ready,
                       "junk is skipped")
        XCTAssertEqual(AgentSession(["state": "ready", "updated": 5])?.since, 5, "since falls back to updated")
        XCTAssertEqual([-1, 0, 1.5, "7", 7].map { AgentSession(["state": "idle", "updated": 1, "pid": $0])?.pid }, [nil, nil, nil, nil, 7],
                       "pids have to be whole and positive")
        XCTAssertEqual(["1790000000000\n", "", "garbage", "-5", nil].map(Sessions.parseSeen), [1_790_000_000_000, 0, 0, 0, 0])
    }

    // ---- the pop and the sound

    struct Look {
        var records: [JSONValue]
        var seen: Double = 0
        /// Minutes after `now`.
        var at: Double = 0
    }

    /// Looks one after another, as the panel does, and says what each alerts.
    func alerts(_ looks: Look...) -> [TopBarSession?] {
        var marks: [String: String]?
        var lastAlert: Double = 0
        return looks.map { look in
            let at = now + look.at * minute
            let result = Sessions.alert(look.records, now: at, seen: look.seen, alive: { self.running.contains($0) }, marks: marks, lastAlert: lastAlert)
            marks = result.marks
            if result.alert != nil {
                lastAlert = at
            }
            return result.alert
        }
    }

    func later(_ state: String, _ minutes: Double, _ extra: [String: JSONValue] = [:]) -> JSONValue {
        session(state, ["session": "s", "since": .number(now + minutes * minute), "updated": .number(now + minutes * minute)].merging(extra) { _, new in new })
    }

    func testAlerts() {
        XCTAssertEqual(alerts(Look(records: [session("waiting"), session("ready")])), [nil], "the first look is quiet, whatever is there")
        XCTAssertEqual(alerts(Look(records: [later("working", 0)]), Look(records: [later("waiting", 1)], at: 1)), [nil, .waiting],
                       "a session starting to wait alerts")
        XCTAssertEqual(alerts(Look(records: [later("working", 0)]), Look(records: [later("ready", 1)], at: 1)), [nil, .ready],
                       "a session finishing its turn alerts")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("waiting", 1)], at: 1)), [nil, .waiting],
                       "a new session that already waits alerts")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("waiting", 1)], at: 1),
                              Look(records: [later("waiting", 1, ["updated": .number(now + 2 * minute)])], at: 2)),
                       [nil, .waiting, nil], "the same wait alerts once")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("waiting", 1)], at: 1), Look(records: [later("working", 2)], at: 2),
                              Look(records: [later("waiting", 3)], at: 3)),
                       [nil, .waiting, nil, .waiting], "waiting again after working alerts again")
        let other: [String: JSONValue] = ["session": "t", "pid": 200]
        XCTAssertEqual(alerts(Look(records: [later("working", 0), later("working", 0, other)]),
                              Look(records: [later("ready", 1), later("working", 0, other)], at: 1),
                              Look(records: [later("ready", 1), later("ready", 2, other)], at: 2)),
                       [nil, .ready, .ready], "a second session finishing alerts while the robot is already green")
    }

    func testQuietAlerts() {
        XCTAssertEqual(alerts(Look(records: [later("working", 0)]), Look(records: [later("ready", 1)], seen: now + 2 * minute, at: 2)), [nil, nil],
                       "a turn already seen is quiet")
        XCTAssertEqual(alerts(Look(records: [later("ready", 0)]), Look(records: [later("ready", 0)], seen: now + minute, at: 1)), [nil, nil],
                       "opening the panel alerts nothing")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("ready", 1, ["parent": "root"])], at: 1)), [nil, nil],
                       "a subagent finishing is quiet")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("waiting", 1, ["parent": "root"])], at: 1)), [nil, .waiting],
                       "a subagent waiting for you alerts")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("ready", 1), later("waiting", 1, ["session": "t", "pid": 200])], at: 1)),
                       [nil, .waiting], "waiting beats ready")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("waiting", 1, ["pid": 300])], at: 1)), [nil, nil],
                       "a session whose agent is gone is quiet")
    }

    func testMergedAlerts() {
        let other: [String: JSONValue] = ["session": "t", "pid": 200]
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("ready", 1)], at: 1),
                              Look(records: [later("ready", 1), later("waiting", 1.02, other)], at: 1.02)),
                       [nil, .ready, nil], "alerts within 3 seconds merge into one")
        XCTAssertEqual(alerts(Look(records: []), Look(records: [later("ready", 1)], at: 1),
                              Look(records: [later("ready", 1), later("waiting", 1.1, other)], at: 1.1)),
                       [nil, .ready, .waiting], "and after that they alert again")
        let marks = Sessions.alert([later("waiting", 1), later("idle", 0, ["pid": 300])], now: now, seen: 0, alive: { self.running.contains($0) },
                                   marks: nil, lastAlert: 0).marks
        XCTAssertEqual(marks, ["claude/s": "waiting@\(now + minute)"], "the marks are each live session, with its state and since")
    }

    func testFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"state": "waiting", "updated": 1}"#.write(to: dir.appendingPathComponent("claude-a.json"), atomically: true, encoding: .utf8)
        try "{ half".write(to: dir.appendingPathComponent("claude-b.json"), atomically: true, encoding: .utf8)
        try "1".write(to: dir.appendingPathComponent(".seen"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Sessions.load(from: dir.path), [["state": "waiting", "updated": 1]], "the files, without broken ones or .seen")
        XCTAssertEqual(Sessions.directory(environment: [:], home: "/Users/me"), "/Users/me/.local/state/omarchy/agents/sessions")
        XCTAssertTrue(Sessions.processRunning(getpid()))
    }
}
