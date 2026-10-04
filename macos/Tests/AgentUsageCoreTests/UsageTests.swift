import Foundation
import XCTest

@testable import AgentUsageCore

// Ported from test/usage-test.js, check for check.
final class UsageTests: XCTestCase {
    let now = Date()

    /// The collectors' timestamps: ISO 8601 with microseconds and an offset.
    func iso(_ date: Date) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .string(formatter.string(from: date).replacingOccurrences(of: "Z", with: "123+00:00"))
    }

    func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    var today: String { Usage.localDate(now) }

    var claude: AgentRecord {
        AgentRecord([
            "id": "claude", "name": "Claude Code", "tierLabel": "Max 5x", "usageStatusText": "", "totalPrompts": 74,
            "todayPrompts": 30, "todaySessions": 1, "hasPromptStats": true, "updatedAt": iso(now - 60),
            "limits": [
                ["label": "Session (5-hour)", "percent": 0.61, "resetsAt": iso(now + 23 * 60 + 5)],
                ["label": "Weekly (7-day)", "percent": 0.18, "resetsAt": iso(now + 5 * 86400 + 3600)],
                ["label": "Opus 5 (1M context)", "title": "Fable Weekly", "percent": 0, "resetsAt": ""],
                ["label": "broken", "percent": "n/a"],
            ],
            "recentDays": [["date": "2026-09-30", "messageCount": 42700], ["date": .string(today), "messageCount": 103_000_000]],
            "modelUsage": [
                "claude-opus-5-5": ["inputTokens": 168, "outputTokens": 50607, "cacheReadInputTokens": 5_013_231, "cacheCreationInputTokens": 289_404],
                "claude-sonnet-4-5-20250929": ["inputTokens": 10],
            ],
        ])
    }

    let codex = AgentRecord(["id": "codex", "name": "Codex", "usageStatusText": "Codex unavailable", "authHelpText": "codex not found in PATH", "totalPrompts": 3, "limits": []])
    let idle = AgentRecord(["id": "fireworks", "name": "Fireworks", "totalPrompts": 0, "limits": []])

    func testTimestamps() {
        XCTAssertEqual(Usage.parseTime("2026-10-02T07:59:59.615034+00:00")!.timeIntervalSince1970,
                       utc(2026, 10, 2, 7, 59, 59).timeIntervalSince1970 + 0.615, accuracy: 1e-6, "microsecond timestamps parse")
        XCTAssertEqual(Usage.parseTime("2026-10-07T08:00:00Z"), utc(2026, 10, 7, 8), "Z timestamps parse")
        XCTAssertEqual(Usage.parseTime("2026-10-07T10:00:00+02:00"), utc(2026, 10, 7, 8), "offsets apply")
        XCTAssertEqual(Usage.parseTime("2026-10-07"), utc(2026, 10, 7), "a date alone is UTC, as in JavaScript")
        XCTAssertEqual(Usage.parseTime("2026-10-07T08:00:00"), local(2026, 10, 7, 8), "a time without an offset is local")
        XCTAssertEqual([Usage.parseTime(""), Usage.parseTime("garbage"), Usage.parseTime("2026-02-30T00:00:00Z")], [nil, nil, nil], "bad timestamps")
        XCTAssertNil(Usage.parseTime(JSONValue?.none), "a missing timestamp")
    }

    func testFormatting() {
        XCTAssertEqual([0, 999, 42700, 103_000_000, 2_500_000_000].map(Usage.formatTokens), ["0", "999", "42.7K", "103.0M", "2.5B"])
        let durations: [TimeInterval] = [0, 59, 23 * 60 + 5, 3 * 3600 + 4 * 60, 5 * 86400 + 3600]
        XCTAssertEqual(durations.map(Usage.formatDuration), ["now", "1m", "23m", "3h 4m", "5d 1h"])
        XCTAssertEqual(Usage.formatDuration(.nan), "now")
        XCTAssertEqual([Usage.formatMoney(4, currency: "usd"), Usage.formatMoney(12.5, currency: "EUR"), Usage.formatMoney(1, currency: "chf")],
                       ["$4.00", "€12.50", "CHF 1.00"])
        XCTAssertEqual(Usage.formatClock(local(2026, 10, 2, 9, 5)), "09:05")
    }

    func testWindowsAndModels() {
        XCTAssertEqual(["Session (5-hour)", "5h window", "30m window", "Weekly (7-day)", "Monthly", "Something (else)", ""].map(Usage.windowTitle),
                       ["Session", "Session", "Session", "Weekly", "Monthly", "Something", "Limit"])
        XCTAssertEqual(claude.limitWindows.map(\.title), ["Session", "Weekly", "Fable Weekly"], "limits keep collector titles and skip junk")
        XCTAssertEqual(claude.limitWindows.map(\.percent), [0.61, 0.18, 0])
        XCTAssertEqual(["claude-opus-5-5", "gpt-5.6-sol", "claude-sonnet-4-5-20250929", "deepseek-v3", ""].map(Usage.friendlyModelName),
                       ["Opus 5.5", "GPT 5.6 Sol", "Sonnet 4.5", "DeepSeek V3", "Unknown"])
    }

    func testProviders() {
        XCTAssertEqual(Usage.visibleProviders([idle, codex, claude]).map(\.id), ["claude", "codex"], "only agents with data show, sorted")
        XCTAssertEqual(Usage.visibleProviders([idle]).count, 0, "nothing to show")
        XCTAssertEqual(Usage.highestPercent([claude, codex]), 0.61, "the menu bar percent is the fullest window")
        XCTAssertNil(Usage.highestPercent([codex]), "no limits, no percent")
        XCTAssertEqual([claude.isAlarming, AgentRecord(["limits": [["label": "5h", "percent": 0.9]]]).isAlarming], [false, true], "alarm at 90%")
        XCTAssertEqual([
            AgentRecord(["balance": ["remaining": 4, "funded": 50]]).isAlarming,
            AgentRecord(["balance": ["remaining": 20, "funded": 50]]).isAlarming,
        ], [true, false], "balance alarm at 10% left")
        XCTAssertEqual([claude.heroMeta, codex.heroMeta, AgentRecord([:]).heroMeta], ["Max 5x", "Codex unavailable", "Subscription"])
        XCTAssertEqual([claude.problem, codex.problem], [nil, "codex not found in PATH"], "the problem card needs a status and help")
    }

    func testSignInActions() {
        func actions(_ id: String, _ status: String) -> [SignInAction] {
            AgentRecord(["id": .string(id), "usageStatusText": .string(status)]).signInActions
        }
        XCTAssertEqual(actions("claude", "Sign-in expired").map(\.label), ["Start Claude Code", "Sign in"], "sign-in problems offer the fix")
        XCTAssertEqual(actions("claude", "Waiting for auth").map(\.command), [["claude"], ["claude", "auth", "login"]])
        XCTAssertEqual(actions("claude", "Waiting for auth").map(\.pause), [false, true])
        XCTAssertEqual(actions("codex", "Not signed in"), [SignInAction(label: "Sign in", command: ["codex", "login"], pause: true)])
        XCTAssertEqual([claude.signInActions.count, codex.signInActions.count, actions("claude", "Claude limits unavailable").count,
                        actions("fireworks", "Not signed in").count], [0, 0, 0, 0], "other problems offer none")
    }

    func testBalance() {
        let balance = AgentRecord(["balance": ["remaining": 12.5, "funded": 50, "spent": 37.5, "currency": "usd", "estimated": true]]).balance
        XCTAssertEqual(balance?.detail, "$37.50 spent of $50.00 funded · estimated")
        XCTAssertNil(AgentRecord(["balance": ["remaining": -1]]).balance, "a negative balance is no balance")
        XCTAssertEqual(AgentRecord(["balance": ["remaining": 3]]).balance?.detail, "", "no detail without funding")
    }

    func testModelRows() {
        XCTAssertEqual(claude.modelRows.map(\.name), ["Opus 5.5", "Sonnet 4.5"], "model rows sorted by total")
        XCTAssertEqual(claude.modelRows.map(\.total), [5_353_410, 10])
        XCTAssertEqual(claude.modelRows[0].detail, "Opus 5.5 · in 168 · out 50.6K · cache 5.0M/289.4K")

        let busyDay = AgentRecord([
            "todayTotalTokens": 188_400_000,
            "todayTokensByModel": ["claude-opus-5": 68_300_000, "claude-opus-5-5": 120_100_000, "claude-haiku-4-5": 0],
        ])
        XCTAssertEqual(busyDay.todayModelRows.map(\.name), ["Opus 5.5", "Opus 5"], "today's models, heaviest first, unused ones skipped")
        XCTAssertEqual(busyDay.todayModelRows[0].detail, "Opus 5.5 · 64% of today's 188.4M", "today's share is of the whole day")

        var many: [String: JSONValue] = [:]
        for n in 1...8 {
            many["claude-opus-4-\(n)"] = .number(Double(n * 1000))
        }
        let manyRows = AgentRecord(["todayTokensByModel": .object(many)]).todayModelRows
        XCTAssertEqual([manyRows.count == 6, manyRows[0].name == "Opus 4.8", manyRows[5].name == "Opus 4.3"], [true, true, true], "today's list stops at 6")
        XCTAssertEqual(manyRows[0].detail, "Opus 4.8 · 22% of today's 36.0K", "shares still count the models past the cap")
        XCTAssertEqual([
            AgentRecord(["todayTokensByModel": [:]]).todayModelRows.count,
            AgentRecord([:]).todayModelRows.count,
            AgentRecord(["todayTokensByModel": nil]).todayModelRows.count,
        ], [0, 0, 0], "no usage today, no rows")
    }

    func testDays() {
        let days = claude.recentDays
        let todayDetail = claude.dayDetail(days[1], isToday: true)
        XCTAssertTrue(todayDetail.hasSuffix(" · 103.0M tokens · 30 prompts · 1 session"), "day detail for today has prompts: \(todayDetail)")
        XCTAssertEqual(claude.dayDetail(days[0], isToday: false), "Wed 9/30 · 42.7K tokens", "day detail for other days")
        XCTAssertEqual(AgentRecord(["hasPromptStats": false]).dayDetail(days[1], isToday: true).contains("prompt"), false,
                       "agents without prompt counts don't claim 0 prompts")
        XCTAssertEqual(["2026-09-26", "2026-10-01", "nope"].map { Usage.dayName($0) }, ["Sat", "Thu", "nope"])
    }

    func testUpdatedAndStale() {
        XCTAssertEqual(Usage.lastUpdated([claude, codex]), Usage.parseTime(claude["updatedAt"]), "last updated")

        let at1321 = local(2026, 10, 2, 13, 21)
        let formatter = ISO8601DateFormatter()
        var staleFields = claude.fields
        staleFields["limitsStale"] = true
        staleFields["limitsFetchedAt"] = .string(formatter.string(from: at1321))
        staleFields["limitsNote"] = "Anthropic is rate limiting checks · next try 13:58"
        let stale = AgentRecord(staleFields)

        XCTAssertEqual([claude.limitsStale ? "stale" : "fresh", claude.limitsTitle()], ["fresh", "LIMITS"], "fresh limits keep the plain title")
        XCTAssertEqual([stale.limitsStale ? "stale" : "fresh", stale.limitsTitle()], ["stale", "LIMITS · AS OF 13:21"], "stale limits say when they were measured")
        XCTAssertEqual(stale.limitsNote, "Anthropic is rate limiting checks · next try 13:58", "and why")

        var noTime = staleFields
        noTime["limitsFetchedAt"] = ""
        noTime["limitsNote"] = ""
        XCTAssertEqual([AgentRecord(noTime).limitsTitle(), AgentRecord(noTime).limitsNote], ["LIMITS · NOT CURRENT", "These limits are from an earlier check."],
                       "stale without a time or reason still says so")
        XCTAssertFalse(AgentRecord(["limitsStale": true, "limits": []]).limitsStale, "a stale flag with no limits is ignored")
        XCTAssertEqual(stale.measuredAt, at1321, "\"updated\" uses the limits check when there is one")
        XCTAssertNil(codex.measuredAt, "…and is unknown without any timestamp")
        XCTAssertEqual(AgentRecord(["updatedAt": claude["updatedAt"]!]).measuredAt, Usage.parseTime(claude["updatedAt"]), "…and the record time otherwise")
    }

    func testDisplay() {
        let a = AgentRecord(["id": "claude", "updatedAt": "2026-10-02T09:00:00+00:00", "limits": [["percent": 0.5]]])
        var bFields = a.fields
        bFields["updatedAt"] = "2026-10-02T09:00:15+00:00"
        bFields["retryAdvised"] = true
        let b = AgentRecord(bFields)
        var cFields = bFields
        cFields["limits"] = [["percent": 0.51]]
        XCTAssertTrue(Usage.sameDisplay([a], [b]), "a new timestamp alone does not change the display")
        XCTAssertFalse(Usage.sameDisplay([b], [AgentRecord(cFields)]), "a new number does")
    }

    func testJavaScriptCoercions() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a": 1, "b": true, "c": null, "d": "x", "e": [1], "f": {}}"#.utf8))
        XCTAssertEqual(decoded, ["a": 1, "b": true, "c": nil, "d": "x", "e": [1], "f": [:]], "numbers stay numbers, booleans booleans")
        XCTAssertEqual([Usage.number("42"), Usage.number("x"), Usage.number(nil), Usage.number(true), Usage.number(2.5)], [42, 0, 0, 1, 3])
        XCTAssertEqual([JS.text(0), JS.text(5), JS.text(0.5), JS.text(false), JS.text("a")], ["", "5", "0.5", "", "a"])
        XCTAssertEqual([JS.round(2.5), JS.round(-2.5), JS.round(-2.6)], [3, -2, -3])
        XCTAssertEqual([JS.number(nil).isNaN, JS.number(.null) == 0, JS.number(" 7 ") == 7], [true, true, true])
        XCTAssertNil(AgentRecord(data: Data(#"{"name": "no id"}"#.utf8)), "a record needs an id")
        XCTAssertNil(AgentRecord(data: Data("[1]".utf8)), "a record is an object")
        XCTAssertEqual(AgentRecord(data: Data(#"{"id": "claude"}"#.utf8))?.name, "claude", "the name falls back to the id")
    }
}
