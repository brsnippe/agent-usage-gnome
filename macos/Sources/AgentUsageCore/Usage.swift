import Foundation

// Data shaping and formatting for the agent usage panel, ported from the GNOME
// extension's usage.js (itself a port of Omarchy's omarchy.agents widget).
// Foundation only, so the tests run anywhere Swift does.

public enum Usage {
    public static let alarmRatio = 0.9
    static let maxModels = 4
    static let maxTodayModels = 6
    static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func number(_ value: JSONValue?) -> Int {
        guard JS.truthy(value) else {
            return 0
        }
        let n = JS.number(value)
        return n.isFinite && abs(n) < 9e15 ? Int(JS.round(n)) : 0
    }

    public static func clamp(_ value: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        value.isNaN ? lo : max(lo, min(hi, value))
    }

    public static func formatTokens(_ value: Int) -> String {
        func scaled(_ divisor: Int, _ suffix: String) -> String {
            let tenths = (value * 10 + divisor / 2) / divisor
            return "\(tenths / 10).\(tenths % 10)\(suffix)"
        }
        if value >= 1_000_000_000 {
            return scaled(1_000_000_000, "B")
        }
        if value >= 1_000_000 {
            return scaled(1_000_000, "M")
        }
        if value >= 1_000 {
            return scaled(1_000, "K")
        }
        return String(value)
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else {
            return "now"
        }
        let minutes = Int((seconds / 60).rounded(.down))
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            return "\(days)d \(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(max(1, minutes))m"
    }

    public static func formatMoney(_ value: Double, currency: String) -> String {
        let code = (currency.isEmpty ? "USD" : currency).uppercased()
        let prefix = ["USD": "$", "EUR": "€", "GBP": "£"][code] ?? "\(code) "
        return prefix + String(format: "%.2f", value.isFinite ? value : 0)
    }

    public static func formatClock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // ------------------------------------------------------------------ time

    private static let isoTime = Pattern(
        #"^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?)?([Zz]|[+-]\d{2}:?\d{2})?$"#
    )

    /// An ISO 8601 timestamp, the way JavaScript's `Date.parse` reads the
    /// collectors' timestamps: to the millisecond, a date alone as UTC, a time
    /// without an offset as local time. Nil when it doesn't read.
    public static func parseTime(_ value: JSONValue?) -> Date? {
        parseTime(JS.text(value))
    }

    public static func parseTime(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groups = isoTime.groups(text) else {
            return nil
        }
        let field = { (index: Int) in groups[index].flatMap { Int($0) } }
        guard let year = field(0), let month = field(1), let day = field(2),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        let hasTime = groups[3] != nil
        let hour = field(3) ?? 0
        let minute = field(4) ?? 0
        let second = field(5) ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        if let offset = groups[7] {
            calendar.timeZone = TimeZone(secondsFromGMT: offsetSeconds(offset)) ?? TimeZone(identifier: "UTC")!
        } else {
            calendar.timeZone = hasTime ? TimeZone.current : TimeZone(identifier: "UTC")!
        }
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == day else {
            return nil
        }
        // Milliseconds, like JavaScript: the collectors write microseconds.
        let fraction = String((groups[6] ?? "").prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return date.addingTimeInterval(Double(Int(fraction) ?? 0) / 1000)
    }

    private static func offsetSeconds(_ text: String) -> Int {
        if text == "Z" || text == "z" {
            return 0
        }
        let digits = text.dropFirst().filter(\.isNumber)
        let hours = Int(digits.prefix(2)) ?? 0
        let minutes = Int(digits.dropFirst(2)) ?? 0
        return (text.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60)
    }

    public static func localDate(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let plainDate = Pattern(#"^(\d{4})-(\d{2})-(\d{2})$"#)

    /// Local midnight of a `YYYY-MM-DD` day.
    static func localMidnight(_ date: String, calendar: Calendar) -> Date? {
        guard let groups = plainDate.groups(date),
              let year = groups[0].flatMap({ Int($0) }), let month = groups[1].flatMap({ Int($0) }),
              let day = groups[2].flatMap({ Int($0) }), (1...12).contains(month), (1...31).contains(day),
              let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: midnight) == day else {
            return nil
        }
        return midnight
    }

    public static func dayName(_ date: String, calendar: Calendar = .current) -> String {
        guard let midnight = localMidnight(date, calendar: calendar) else {
            return date
        }
        return dayNames[calendar.component(.weekday, from: midnight) - 1]
    }

    // ---------------------------------------------------------------- models

    private static let claudePrefix = Pattern("^claude-")
    private static let dateSuffix = Pattern(#"-\d{8}$"#)

    /// Model ids arrive hyphenated with the version split across segments
    /// (`claude-opus-4-8`, `gpt-5.6-sol`). Rejoin the numeric run into one
    /// version and title-case the words around it.
    public static func friendlyModelName(_ id: String) -> String {
        guard !id.isEmpty else {
            return "Unknown"
        }
        let name = dateSuffix.replacingFirst(in: claudePrefix.replacingFirst(in: id, with: ""), with: "")
        var words: [String] = []
        var version: [String] = []
        for part in name.split(separator: "-", omittingEmptySubsequences: true).map(String.init) {
            if let first = part.first, first.isASCII, first.isNumber {
                version.append(part)
                continue
            }
            if !version.isEmpty {
                words.append(version.joined(separator: "."))
                version = []
            }
            switch part {
            case "gpt": words.append("GPT")
            case "deepseek": words.append("DeepSeek")
            default: words.append(part.prefix(1).uppercased() + part.dropFirst())
            }
        }
        if !version.isEmpty {
            words.append(version.joined(separator: "."))
        }
        return words.isEmpty ? "Unknown" : words.joined(separator: " ")
    }

    // ---------------------------------------------------------------- limits

    private static let hourSpan = Pattern(#"(\d+)\s*-?\s*h(?:our)?\b"#)
    private static let minuteSpan = Pattern(#"(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b"#)
    private static let parenthesized = Pattern(#"\s*\(.*\)\s*"#)

    /// Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
    /// them ("5h window", "30m window"). Both have to land on the same title.
    public static func windowTitle(_ label: String) -> String {
        let text = label.lowercased()
        if text.contains("month") {
            return "Monthly"
        }
        if ["week", "7-day", "seven", "month", "30-day"].contains(where: { text.contains($0) }) {
            return "Weekly"
        }
        if text.contains("session") || hourSpan.matches(text) || minuteSpan.matches(text) {
            return "Session"
        }
        let plain = parenthesized.replacingFirst(in: label, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? "Limit" : plain
    }

    // ------------------------------------------------------------- providers

    /// The agents with numbers to show, by id. An agent earns its place in the
    /// panel by having produced numbers.
    public static func visibleProviders(_ records: [AgentRecord]) -> [AgentRecord] {
        records.filter { !$0.id.isEmpty && $0.hasData }.sorted { $0.id < $1.id }
    }

    /// The fullest window across every agent: the number in the menu bar.
    public static func highestPercent(_ records: [AgentRecord]) -> Double? {
        records.flatMap(\.limitWindows).map(\.percent).max()
    }

    public static func lastUpdated(_ records: [AgentRecord]) -> Date? {
        records.compactMap { parseTime($0["updatedAt"]) }.max()
    }

    /// Whether two sets of records draw the same panel: everything but the
    /// timestamps every check rewrites.
    public static func sameDisplay(_ a: [AgentRecord], _ b: [AgentRecord]) -> Bool {
        a.map(\.displayed) == b.map(\.displayed)
    }

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count == 1 ? "" : "s")"
    }
}

// ----------------------------------------------------------------- records

public struct LimitWindow: Equatable {
    public var title: String
    public var percent: Double
    public var resetsAt: Date?

    public var alarming: Bool { percent >= Usage.alarmRatio }
}

public struct Balance: Equatable {
    public var remaining: Double
    public var funded: Double
    public var spent: Double
    public var currency: String
    public var estimated: Bool

    public var detail: String {
        guard funded > 0 else {
            return ""
        }
        let text = "\(Usage.formatMoney(spent, currency: currency)) spent of \(Usage.formatMoney(funded, currency: currency)) funded"
        return estimated ? "\(text) · estimated" : text
    }

    public var alarming: Bool {
        funded > 0 && remaining / funded <= 1 - Usage.alarmRatio
    }
}

public struct UsageDay: Equatable {
    public var date: String
    /// Tokens that day. The record calls it `messageCount`, after Omarchy's.
    public var tokens: Int
}

public struct ModelRow: Equatable {
    public var name: String
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public var total: Int { input + output + cacheRead + cacheWrite }

    public var detail: String {
        "\(name) · in \(Usage.formatTokens(input)) · out \(Usage.formatTokens(output)) · "
            + "cache \(Usage.formatTokens(cacheRead))/\(Usage.formatTokens(cacheWrite))"
    }
}

public struct TodayModelRow: Equatable {
    public var name: String
    public var total: Int
    /// Of the whole day, which can include models past the list's cap.
    public var share: Double
    public var dayTotal: Int

    public var detail: String {
        "\(name) · \(Int(JS.round(share * 100)))% of today's \(Usage.formatTokens(dayTotal))"
    }
}

/// One agent's record, as a collector wrote it.
public struct AgentRecord: Equatable {
    public var fields: [String: JSONValue]

    public init(_ fields: [String: JSONValue]) {
        self.fields = fields
    }

    /// A record file's contents: a JSON object with an id, or nil.
    public init?(data: Data) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let fields = value.objectValue, JS.truthy(fields["id"]) else {
            return nil
        }
        self.fields = fields
    }

    public subscript(key: String) -> JSONValue? { fields[key] }

    public var id: String { JS.text(fields["id"]) }

    public var name: String {
        let name = JS.text(fields["name"])
        return name.isEmpty ? id : name
    }

    public var limitWindows: [LimitWindow] {
        (fields["limits"]?.arrayValue ?? []).compactMap { item in
            guard let entry = item.objectValue else {
                return nil
            }
            let percent = JS.number(entry["percent"])
            guard percent.isFinite, percent >= 0 else {
                return nil
            }
            // A collector that already knows which window a limit belongs to
            // says so; that beats reading it back out of a label like
            // "Opus 5 (1M context)".
            let title = JS.text(entry["title"])
            return LimitWindow(
                title: title.isEmpty ? Usage.windowTitle(JS.text(entry["label"])) : title,
                percent: percent,
                resetsAt: Usage.parseTime(entry["resetsAt"])
            )
        }
    }

    /// Collectors that fall back to a cached reading (rate limited, offline,
    /// signed out) mark it stale and say when it was measured.
    public var limitsStale: Bool {
        fields["limitsStale"] == .bool(true) && !limitWindows.isEmpty
    }

    public func limitsTitle(calendar: Calendar = .current) -> String {
        guard limitsStale else {
            return "LIMITS"
        }
        guard let measured = Usage.parseTime(fields["limitsFetchedAt"]) else {
            return "LIMITS · NOT CURRENT"
        }
        return "LIMITS · AS OF \(Usage.formatClock(measured, calendar: calendar))"
    }

    public var limitsNote: String {
        let note = JS.text(fields["limitsNote"])
        return note.isEmpty ? "These limits are from an earlier check." : note
    }

    /// When the panel's numbers were last measured: the limits check if the
    /// collector reports one, otherwise the record itself.
    public var measuredAt: Date? {
        Usage.parseTime(fields["limitsFetchedAt"]) ?? Usage.parseTime(fields["updatedAt"])
    }

    public var balance: Balance? {
        guard let raw = fields["balance"]?.objectValue else {
            return nil
        }
        let remaining = JS.number(raw["remaining"])
        guard remaining.isFinite, remaining >= 0 else {
            return nil
        }
        let funded = JS.number(raw["funded"])
        let spent = JS.number(raw["spent"])
        let currency = JS.text(raw["currency"])
        return Balance(
            remaining: remaining,
            funded: funded.isFinite && funded > 0 ? funded : 0,
            spent: spent.isFinite ? max(0, spent) : 0,
            currency: currency.isEmpty ? "USD" : currency,
            estimated: raw["estimated"] == .bool(true)
        )
    }

    public var hasData: Bool {
        let counts = ["totalPrompts", "totalSessions", "activeDays", "todayPrompts", "todaySessions"]
        return counts.contains { Usage.number(fields[$0]) > 0 } || !limitWindows.isEmpty || balance != nil
    }

    public var isAlarming: Bool {
        limitWindows.contains(where: \.alarming) || balance?.alarming == true
    }

    /// The plan you pay for, or the problem that's in the way.
    public var heroMeta: String {
        let status = JS.text(fields["usageStatusText"])
        if !status.isEmpty {
            return status
        }
        let tier = JS.text(fields["tierLabel"])
        return tier.isEmpty ? "Subscription" : tier.prefix(1).uppercased() + tier.dropFirst()
    }

    /// The problem card: shown when the collector names a problem and says
    /// what to do about it.
    public var problem: String? {
        let help = JS.text(fields["authHelpText"])
        return JS.text(fields["usageStatusText"]).isEmpty || help.isEmpty ? nil : help
    }

    public var retryAdvised: Bool { fields["retryAdvised"] == .bool(true) }

    public var recentDays: [UsageDay] {
        (fields["recentDays"]?.arrayValue ?? []).compactMap { item in
            guard let day = item.objectValue else {
                return nil
            }
            return UsageDay(date: JS.text(day["date"]), tokens: Usage.number(day["messageCount"]))
        }
    }

    public func dayDetail(_ day: UsageDay, isToday: Bool, calendar: Calendar = .current) -> String {
        var label = day.date
        if let midnight = Usage.localMidnight(day.date, calendar: calendar) {
            let parts = calendar.dateComponents([.month, .day], from: midnight)
            label = "\(Usage.dayName(day.date, calendar: calendar)) \(parts.month ?? 0)/\(parts.day ?? 0)"
        }
        var text = "\(label) · \(Usage.formatTokens(day.tokens)) tokens"
        // Prompt and session counts only exist for today. Billing-API agents
        // never count prompts, and "0 prompts" would read as a quiet day, not
        // a gap.
        if isToday && fields["hasPromptStats"] != .bool(false) {
            text += " · \(Usage.plural(Usage.number(fields["todayPrompts"]), "prompt"))"
            text += " · \(Usage.plural(Usage.number(fields["todaySessions"]), "session"))"
        }
        return text
    }

    /// The heaviest models of all time. JSON objects have no order once
    /// decoded, so equal totals fall back to the model id.
    public var modelRows: [ModelRow] {
        let usage = fields["modelUsage"]?.objectValue ?? [:]
        let rows = usage.map { id, raw -> (String, ModelRow) in
            let bucket = raw.objectValue ?? [:]
            return (id, ModelRow(
                name: Usage.friendlyModelName(id),
                input: Usage.number(bucket["inputTokens"]),
                output: Usage.number(bucket["outputTokens"]),
                cacheRead: Usage.number(bucket["cacheReadInputTokens"]),
                cacheWrite: Usage.number(bucket["cacheCreationInputTokens"])
            ))
        }
        return rows
            .sorted { $0.1.total != $1.1.total ? $0.1.total > $1.1.total : $0.0 < $1.0 }
            .prefix(Usage.maxModels)
            .map(\.1)
    }

    /// Today's tokens per model. Collectors only total these per model,
    /// without the input/output/cache split the all-time rows carry.
    public var todayModelRows: [TodayModelRow] {
        guard let byModel = fields["todayTokensByModel"]?.objectValue else {
            return []
        }
        let rows = byModel
            .map { id, tokens in (id, Usage.friendlyModelName(id), Usage.number(tokens)) }
            .filter { $0.2 > 0 }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
        let dayTotal = max(Usage.number(fields["todayTotalTokens"]), rows.reduce(0) { $0 + $1.2 })
        return rows.prefix(Usage.maxTodayModels).map { _, name, total in
            TodayModelRow(name: name, total: total, share: dayTotal > 0 ? Double(total) / Double(dayTotal) : 0, dayTotal: dayTotal)
        }
    }

    /// Everything the panel draws, minus the timestamps every check rewrites.
    var displayed: [String: JSONValue] {
        fields.filter { $0.key != "updatedAt" && $0.key != "retryAdvised" }
    }
}
