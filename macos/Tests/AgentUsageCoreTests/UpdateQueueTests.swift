import XCTest

@testable import AgentUsageCore

// Ported from test/updates-test.js and test/versions-test.js.
final class UpdateQueueTests: XCTestCase {
    func testQueue() {
        var q = UpdateQueue()
        XCTAssertEqual(q.request(.normal), UpdateRequest(kind: .normal), "an idle queue starts the request")
        XCTAssertTrue(q.busy, "then it is busy")
        XCTAssertNil(q.request(.limits), "a limits check during a full run is already covered")
        XCTAssertNil(q.pending)
        XCTAssertNil(q.request(.normal), "a second full run during a full run is covered")
        XCTAssertNil(q.pending)
        XCTAssertNil(q.request(.force), "a forced refresh during a full run still queues")
        XCTAssertEqual(q.pending, UpdateRequest(kind: .force))
        XCTAssertEqual(q.finish(), UpdateRequest(kind: .force), "finishing starts the queued request")
        XCTAssertNil(q.finish(), "finishing with nothing queued goes idle")
        XCTAssertFalse(q.busy)
    }

    // The bug the queue exists for: a limits check queued first must not
    // swallow the full rescan.
    func testRescanBehindLimits() {
        var q = UpdateQueue()
        _ = q.request(.limits)
        _ = q.request(.limits, agents: ["claude"])
        XCTAssertNil(q.pending, "limits during limits is covered")
        _ = q.request(.normal)
        XCTAssertEqual(q.pending, UpdateRequest(kind: .normal), "a full rescan queued behind limits stays a full rescan")
        _ = q.request(.limits)
        XCTAssertEqual(q.pending, UpdateRequest(kind: .normal), "a later limits check does not downgrade it")
        XCTAssertEqual(q.finish(), UpdateRequest(kind: .normal), "so the rescan runs next")
    }

    // Retries name specific agents; merging widens rather than narrows.
    func testRetries() {
        var q = UpdateQueue()
        _ = q.request(.limits, agents: ["claude"])
        _ = q.request(.limits, agents: ["codex"])
        XCTAssertEqual(q.pending, UpdateRequest(kind: .limits, agents: ["codex"]), "a retry for another agent queues")
        _ = q.request(.limits, agents: ["claude"])
        XCTAssertEqual(q.pending, UpdateRequest(kind: .limits, agents: ["codex"]), "a retry for the agent already being checked is covered")
        _ = q.request(.limits, agents: ["fireworks"])
        XCTAssertEqual(q.pending, UpdateRequest(kind: .limits, agents: ["codex", "fireworks"]), "retries for several agents merge")
        _ = q.request(.limits)
        XCTAssertEqual(q.pending, UpdateRequest(kind: .limits), "an all-agent check widens a named retry")

        var one = UpdateQueue()
        _ = one.request(.limits, agents: ["claude"])
        XCTAssertNil(one.request(.limits))
        XCTAssertEqual(one.pending, UpdateRequest(kind: .limits), "an all-agent check is not covered by a one-agent run")
    }

    func testFlags() {
        XCTAssertEqual([UpdateKind.normal.flags, UpdateKind.limits.flags, UpdateKind.force.flags], [[], ["--limits-only"], ["--force"]])
    }

    func testVersions() {
        XCTAssertEqual(["0.6.0", "v0.6.1", "0.6.1-dev+3f2a1c", " 1.10.2 ", "main", ""].map(Versions.parse),
                       [[0, 6, 0], [0, 6, 1], [0, 6, 1], [1, 10, 2], nil, nil], "parses plain, v-prefixed and dev versions")
        XCTAssertEqual([Versions.compare("0.10.0", "0.9.0"), Versions.compare("0.6.0", "0.6.0"), Versions.compare("0.6.0", "0.6.1")], [1, 0, -1],
                       "compares numerically, not as text")
        XCTAssertTrue(Versions.isNewer("0.6.1", than: "0.6.0"), "a newer release is newer")
        XCTAssertFalse(Versions.isNewer("0.6.0", than: "0.6.0"), "the same release is not")
        XCTAssertFalse(Versions.isNewer("0.5.9", than: "0.6.0"), "an older release is not")
        XCTAssertFalse(Versions.isNewer("0.6.0", than: "0.6.0-dev+abc"), "a dev build is not behind its own release")
        XCTAssertTrue(Versions.isNewer("0.6.1", than: "0.6.0-dev+abc"), "but is behind the next one")
        XCTAssertTrue(Versions.isNewer("0.6.0", than: ""), "an install without a version is behind any release")
        XCTAssertFalse(Versions.isNewer("error: fatal", than: "0.6.0"), "garbage from the remote never counts as an update")
    }
}
