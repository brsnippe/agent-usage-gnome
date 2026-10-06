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
