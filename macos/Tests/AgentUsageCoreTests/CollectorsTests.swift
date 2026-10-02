import Foundation
import XCTest

@testable import AgentUsageCore

// Running the collectors, with shell scripts standing in for the Python ones.
final class CollectorsTests: XCTestCase {
    var dir = ""
    var bin: String { "\(dir)/bin" }
    var usage: String { "\(dir)/usage" }

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "agent-usage-collectors-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    func collector(_ name: String, _ body: String, executable: Bool = true) throws {
        let path = "\(bin)/\(name)"
        try body.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: path)
    }

    func read(_ agent: String) -> String? {
        try? String(contentsOfFile: "\(usage)/\(agent).json", encoding: .utf8)
    }

    func run(_ request: UpdateRequest, timeout: TimeInterval = 20) -> [CollectorOutcome] {
        Collectors.run(request, collectors: Collectors.find(in: bin), interpreter: "/bin/sh", environment: ["PATH": "/usr/bin:/bin"],
                       usageDir: usage, timeout: timeout)
    }

    func testFindsCollectorsButNotTheUpdater() throws {
        try collector("agent-usage-codex", "")
        try collector("agent-usage-claude", "")
        try collector("agent-usage-update", "")
        try collector("agent-usage-notes", "", executable: false)
        try collector("README", "")
        XCTAssertEqual(Collectors.find(in: bin).map(\.agent), ["claude", "codex"])
        XCTAssertEqual(Collectors.wanted(Collectors.find(in: bin), agents: ["codex"]).map(\.agent), ["codex"])
        XCTAssertEqual(Collectors.wanted(Collectors.find(in: bin), agents: []).map(\.agent), ["claude", "codex"], "no agents means every agent")
        XCTAssertEqual(Collectors.find(in: "\(dir)/missing"), [])
    }

    func testWritesEachRecordAndKeepsTheLastGoodOne() throws {
        try collector("agent-usage-claude", #"printf '  {"id": "claude", "flags": "%s"}\n\n' "$*""#)
        try collector("agent-usage-codex", "echo 'not json'")
        try collector("agent-usage-broken", "echo '{\"id\": \"broken\"}'; exit 3")
        try FileManager.default.createDirectory(atPath: usage, withIntermediateDirectories: true)
        try #"{"id": "codex", "old": true}"#.write(toFile: "\(usage)/codex.json", atomically: true, encoding: .utf8)

        let outcomes = run(UpdateRequest(kind: .force))
        XCTAssertEqual(outcomes, [
            CollectorOutcome(agent: "broken", failure: "exited with status 3"),
            CollectorOutcome(agent: "claude", failure: nil),
            CollectorOutcome(agent: "codex", failure: "printed no record"),
        ])
        XCTAssertEqual(read("claude"), #"{"id": "claude", "flags": "--force"}"# + "\n", "the record, trimmed, with a newline")
        XCTAssertEqual(read("codex"), #"{"id": "codex", "old": true}"#, "a failed collector leaves the last record alone")
        XCTAssertNil(read("broken"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: usage).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [], "no temporary files stay behind")
    }

    func testRunsOnlyTheRequestedAgentsWithTheirFlags() throws {
        try collector("agent-usage-claude", #"echo "{\"id\": \"claude\", \"flags\": \"$*\"}""#)
        try collector("agent-usage-codex", #"echo "{\"id\": \"codex\", \"flags\": \"$*\"}""#)
        XCTAssertEqual(run(UpdateRequest(kind: .limits, agents: ["claude"])).map(\.agent), ["claude"])
        XCTAssertEqual(Records.load(from: usage).map { JS.text($0["flags"]) }, ["--limits-only"])
        _ = run(UpdateRequest(kind: .normal))
        XCTAssertEqual(Records.load(from: usage).map { "\($0.id):\(JS.text($0["flags"]))" }, ["claude:", "codex:"])
    }

    func testRunsSideBySideAndStopsAHungCollector() throws {
        try collector("agent-usage-slow", "exec sleep 30")
        try collector("agent-usage-quick", #"echo '{"id": "quick"}'"#)
        let started = Date()
        let outcomes = run(UpdateRequest(kind: .normal), timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "the hung collector was stopped")
        XCTAssertEqual(outcomes, [
            CollectorOutcome(agent: "quick", failure: nil),
            CollectorOutcome(agent: "slow", failure: "took longer than 1 s and was stopped"),
        ])
    }

    func testAMissingInterpreterIsAFailureNotACrash() throws {
        try collector("agent-usage-claude", "")
        let outcomes = Collectors.run(UpdateRequest(kind: .normal), collectors: Collectors.find(in: bin), interpreter: "\(dir)/no-python",
                                      environment: [:], usageDir: usage)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes[0].failure?.hasPrefix("couldn't start") == true, outcomes[0].failure ?? "")
    }

    func testLoadsRecords() throws {
        try FileManager.default.createDirectory(atPath: usage, withIntermediateDirectories: true)
        let files = [
            "codex.json": #"{"id": "codex"}"#, "claude.json": #"{"id": "claude"}"#, ".claude.ABC123": #"{"id": "temp"}"#,
            ".hidden.json": #"{"id": "hidden"}"#, "broken.json": "{", "noid.json": #"{"name": "x"}"#, "notes.txt": #"{"id": "notes"}"#,
        ]
        for (name, text) in files {
            try text.write(toFile: "\(usage)/\(name)", atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(Records.load(from: usage).map(\.id), ["claude", "codex"])
        XCTAssertEqual(Records.load(from: "\(dir)/missing"), [])
    }

    func testPlaces() {
        XCTAssertEqual(Collectors.usageDirectory(environment: [:], home: "/Users/me"), "/Users/me/.local/state/omarchy/agents/usage")
        XCTAssertEqual(Collectors.usageDirectory(environment: ["XDG_STATE_HOME": ""], home: "/Users/me"), "/Users/me/.local/state/omarchy/agents/usage",
                       "an empty XDG_STATE_HOME counts as unset, as in the bash updater")
        XCTAssertEqual(Collectors.usageDirectory(environment: ["XDG_STATE_HOME": "/s"], home: "/Users/me"), "/s/omarchy/agents/usage")
        let path = Collectors.environment(base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/me"], home: "/Users/me")["PATH"] ?? ""
        XCTAssertTrue(path.hasPrefix("/usr/bin:/bin:/opt/homebrew/bin:"), path)
        XCTAssertTrue(path.contains("/Users/me/.local/bin"), path)
        XCTAssertEqual(Collectors.findPython { $0.hasPrefix("/opt/homebrew") || $0.hasPrefix("/usr/local") }, "/opt/homebrew/bin/python3",
                       "the first Python that's there")
        XCTAssertEqual(Collectors.findPython { $0.contains("CommandLineTools") || $0.hasPrefix("/opt") }, "/Library/Developer/CommandLineTools/usr/bin/python3",
                       "Apple's own comes first")
        XCTAssertNil(Collectors.findPython { _ in false })
        XCTAssertFalse(Collectors.pythonCandidates.contains("/usr/bin/python3"), "never the stub that asks to install the tools")
    }
}
