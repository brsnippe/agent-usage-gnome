import Foundation
import XCTest

@testable import AgentUsageCore

final class PanelTests: XCTestCase {
    let claude = AgentRecord(["id": "claude", "totalPrompts": 3, "limits": [["label": "5h", "percent": 0.614]]])
    let codex = AgentRecord(["id": "codex", "totalPrompts": 1, "retryAdvised": true])
    let pi = AgentRecord(["id": "pi", "totalPrompts": 1])

    func testMenuBar() {
        XCTAssertEqual(Panel.menuBarText([claude, codex], sessionFrom: 40), "61%")
        XCTAssertNil(Panel.menuBarText([codex], sessionFrom: 40), "no limits, no percentage")
        let busyWeek = AgentRecord(["limits": [["label": "Session (5-hour)", "percent": 0.45], ["label": "Weekly (7-day)", "percent": 0.8]]])
        XCTAssertEqual([Panel.menuBarText([busyWeek], sessionFrom: 40), Panel.menuBarText([busyWeek], sessionFrom: 50)], ["45%", "80%"],
                       "the session from the setting on")
        XCTAssertEqual([Panel.percentText(0.005), Panel.percentText(0.9), Panel.percentText(1)], ["1%", "90%", "100%"])
        XCTAssertFalse(Panel.menuBarAlarming([claude]))
        XCTAssertTrue(Panel.menuBarAlarming([AgentRecord(["limits": [["percent": 0.95]]])]))
        XCTAssertTrue(Panel.menuBarStale([AgentRecord(["limitsStale": true, "limits": [["percent": 0.2]]])]))
        XCTAssertFalse(Panel.menuBarStale([claude]))
    }

    func testSelection() {
        let providers = [claude, codex, pi]
        XCTAssertEqual(Panel.selection("codex", in: providers), "codex", "the selection follows the agent")
        XCTAssertEqual(Panel.selection("gone", in: providers), "claude", "a vanished agent falls back to the first")
        XCTAssertEqual(Panel.selection("claude", in: []), "")
        XCTAssertEqual(Panel.step(from: "claude", by: 1, in: providers), "codex")
        XCTAssertEqual(Panel.step(from: "claude", by: -1, in: providers), "pi", "← wraps around")
        XCTAssertEqual(Panel.step(from: "pi", by: 1, in: providers), "claude", "→ wraps around")
        XCTAssertEqual(Panel.step(from: "x", by: 1, in: []), "x")
        XCTAssertEqual(Panel.retryAgents([claude, codex]), ["codex"])
    }

    func testCountdownsAndBars() {
        let now = Date()
        XCTAssertEqual(Panel.resetText(now + 3 * 3600 + 4 * 60 + 30, now: now), "Resets in 3h 4m")
        XCTAssertEqual([Panel.resetText(now - 1, now: now), Panel.resetText(nil, now: now)], ["", ""], "nothing to count down to")
        XCTAssertTrue(Panel.isToday(UsageDay(date: Usage.localDate(now), tokens: 1), now: now))
        XCTAssertFalse(Panel.isToday(UsageDay(date: "2001-01-01", tokens: 1), now: now))
        XCTAssertEqual(Panel.dayBarValues([UsageDay(date: "a", tokens: 50), UsageDay(date: "b", tokens: 100), UsageDay(date: "c", tokens: 0)]), [0.5, 1, 0])
        XCTAssertEqual(Panel.dayBarValues([UsageDay(date: "a", tokens: 0)]), [0], "an idle week has empty bars, not a division by zero")
        XCTAssertEqual(Panel.modelBarValues([200, 50]), [1, 0.25], "the heaviest model fills its row")
    }

    func testFooter() {
        let measured = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 13, minute: 21))!
        let record = AgentRecord(["id": "claude", "updatedAt": .string(ISO8601DateFormatter().string(from: measured))])
        XCTAssertEqual(Panel.footerText(hover: "Opus 5.5 · in 1K", running: UpdateRequest(kind: .force), record: record, newRelease: "0.7.0"),
                       "Opus 5.5 · in 1K", "the row under the pointer takes over")
        XCTAssertEqual(Panel.footerText(hover: nil, running: UpdateRequest(kind: .normal), record: record, newRelease: nil), "Refreshing…")
        XCTAssertEqual(Panel.footerText(hover: nil, running: UpdateRequest(kind: .limits), record: record, newRelease: nil), "Updated 13:21",
                       "the quick limits checks aren't called out")
        XCTAssertEqual(Panel.footerText(hover: nil, running: nil, record: record, newRelease: "0.7.0"), "Updated 13:21 · v0.7.0 available")
        XCTAssertEqual(Panel.footerText(hover: nil, running: nil, record: nil, newRelease: nil), "")
    }
}
