import Foundation

// The panel's decisions that don't need a screen, from the GNOME extension's
// extension.js: what the menu bar says, which agent is selected, the footer
// and the countdowns.

public enum Panel {
    public static let emptyText = "No AI coding subscriptions found.\nAgents show up here once you've used them."

    public static let noPythonText =
        "Agent Usage needs Python 3 to collect usage. It comes with Apple's Command Line Tools: run `xcode-select --install` in Terminal."

    /// How far a stale menu bar number is dimmed: GNOME's opacity 140 of 255.
    public static let staleOpacity = 140.0 / 255.0

    public static func percentText(_ ratio: Double) -> String {
        "\(Int(JS.round(ratio * 100)))%"
    }

    /// The menu bar's label: the fullest limit, or nil with no limits at all.
    public static func menuBarText(_ providers: [AgentRecord]) -> String? {
        Usage.highestPercent(providers).map(percentText)
    }

    public static func menuBarAlarming(_ providers: [AgentRecord]) -> Bool {
        providers.contains(where: \.isAlarming)
    }

    /// A percentage from an earlier check fades, so it doesn't pass for live.
    public static func menuBarStale(_ providers: [AgentRecord]) -> Bool {
        providers.contains(where: \.limitsStale)
    }

    /// The selection follows the agent, not its slot, so a second agent's
    /// first scan doesn't swap out what you were reading.
    public static func selection(_ current: String, in providers: [AgentRecord]) -> String {
        providers.contains { $0.id == current } ? current : (providers.first?.id ?? "")
    }

    /// The agent `delta` tabs away, wrapping around (←/→, h/l).
    public static func step(from current: String, by delta: Int, in providers: [AgentRecord]) -> String {
        guard !providers.isEmpty else {
            return current
        }
        let index = providers.firstIndex { $0.id == current } ?? -1
        let count = providers.count
        return providers[(((index + delta) % count) + count) % count].id
    }

    /// Agents whose collector couldn't reach its limits endpoint at all
    /// (typically right after login, before the network is up). They're
    /// rerun sooner than the regular interval.
    public static func retryAgents(_ records: [AgentRecord]) -> [String] {
        records.filter(\.retryAdvised).map(\.id)
    }

    public static func resetText(_ resetsAt: Date?, now: Date) -> String {
        guard let resetsAt, resetsAt > now else {
            return ""
        }
        return "Resets in \(Usage.formatDuration(resetsAt.timeIntervalSince(now)))"
    }

    public static func isToday(_ day: UsageDay, now: Date, calendar: Calendar = .current) -> Bool {
        day.date == Usage.localDate(now, calendar: calendar)
    }

    /// Each day's bar, scaled to the busiest day shown.
    public static func dayBarValues(_ days: [UsageDay]) -> [Double] {
        let peak = Double(max(1, days.map(\.tokens).max() ?? 0))
        return days.map { Usage.clamp(Double($0.tokens) / peak) }
    }

    /// Each model row's bar, scaled to the heaviest model, so the top row is
    /// always full.
    public static func modelBarValues(_ totals: [Int]) -> [Double] {
        let heaviest = Double(max(1, totals.first ?? 0))
        return totals.map { Usage.clamp(Double($0) / heaviest) }
    }

    /// The bottom line. Details of the row under the pointer take it over;
    /// otherwise it says when the numbers were measured, and whether a new
    /// release is out.
    public static func footerText(
        hover: String?, running: UpdateRequest?, record: AgentRecord?, newRelease: String?, calendar: Calendar = .current
    ) -> String {
        if let hover {
            return hover
        }
        // The quick limits checks run every few minutes; only the slower
        // refreshes are worth calling out.
        if let running, running.kind != .limits {
            return "Refreshing…"
        }
        var parts: [String] = []
        if let measured = record?.measuredAt {
            parts.append("Updated \(Usage.formatClock(measured, calendar: calendar))")
        }
        if let newRelease {
            parts.append("v\(newRelease) available")
        }
        return parts.joined(separator: " · ")
    }
}
