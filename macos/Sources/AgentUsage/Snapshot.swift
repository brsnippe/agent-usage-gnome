import AgentUsageCore
import AppKit
import SwiftUI

/// `AgentUsage --snapshot <folder>`: draws the panel from sample records to
/// PNGs, so the look can be checked without a Mac at hand. CI saves them with
/// each build.
enum Snapshot {
    @MainActor
    static func run(into folder: String) throws {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let now = Date()
        let samples = Samples(now: now)

        var scenes: [(String, PanelState)] = []
        var state = PanelState(providers: [samples.claude, samples.codex], selectedID: "claude", now: now)
        state.launchHint = "Open OpenCode in Terminal"
        scenes.append(("panel-claude", state))

        state.selectedID = "codex"
        scenes.append(("panel-codex-problem", state))

        var signIn = PanelState(providers: [samples.claudeSignedOut], selectedID: "claude", now: now)
        signIn.launchHint = "Open Claude (desktop app)"
        signIn.launchOpensApp = true
        scenes.append(("panel-claude-sign-in", signIn))

        var stale = PanelState(providers: [samples.claudeStale], selectedID: "claude", now: now)
        stale.hoveredRow = "day-6"
        stale.hoverText = samples.claudeStale.dayDetail(samples.claudeStale.recentDays[6], isToday: true)
        stale.launchHint = "Open OpenCode in Terminal"
        scenes.append(("panel-stale-alarm-hover", stale))

        var release = PanelState(providers: [samples.claude], selectedID: "claude", now: now)
        release.newRelease = "0.7.0"
        release.notice = "Kitty isn't installed."
        release.launchHint = "Open OpenCode"
        scenes.append(("panel-update-notice", release))

        scenes.append(("panel-empty", PanelState(now: now)))
        scenes.append(("panel-no-python", PanelState(pythonMissing: true, now: now)))

        for (name, state) in scenes {
            let model = PanelModel()
            model.state = state
            try write(PanelWindowView(model: model), to: "\(folder)/\(name).png")
        }
        try write(MenuBarSamples(), to: "\(folder)/menubar.png")
        try settings(to: "\(folder)/settings.png")
    }

    /// The settings window, as it is: its switches, lists and text fields
    /// are AppKit's, which ImageRenderer can't draw, so this one is put on
    /// screen and captured.
    @MainActor
    private static func settings(to path: String) throws {
        let controller = SettingsWindowController(machine: { Machine.local() })
        controller.show()
        // Long enough for the release check to answer.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        guard let view = controller.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(bitmap.pixelsWide)×\(bitmap.pixelsHigh))")
    }

    @MainActor
    private static func write<V: View>(_ view: V, to path: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(image.width)×\(image.height))")
    }
}

/// The menu bar label in its four states, on a dark and a light menu bar.
/// macOS draws the real one; this is how it's meant to come out.
struct MenuBarSamples: View {
    var body: some View {
        HStack(spacing: 0) {
            bar(dark: true)
            bar(dark: false)
        }
    }

    private func bar(dark: Bool) -> some View {
        let text = dark ? Color.white : Color.black
        return VStack(alignment: .leading, spacing: 6) {
            label("61%", color: text)
            label("94%", color: Theme.urgent)
            label("61%", color: text, faded: true)
            label(nil, color: text)
        }
        .padding(10)
        .background(dark ? Color(hex: 0x2A2A2E) : Color(hex: 0xECECEC))
    }

    private func label(_ text: String?, color: Color, faded: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(nsImage: Assets.robot).renderingMode(.template).foregroundColor(color)
            if let text {
                Text(text)
                    .font(.system(size: NSFont.systemFontSize).monospacedDigit())
                    .foregroundColor(color.opacity(faded ? Panel.staleOpacity : 1))
            }
        }
        .frame(height: 22)
    }
}

/// Sample records shaped like the collectors' output.
struct Samples {
    let claude: AgentRecord
    let claudeStale: AgentRecord
    let claudeSignedOut: AgentRecord
    let codex: AgentRecord

    init(now: Date) {
        let iso = ISO8601DateFormatter()
        func at(_ offset: TimeInterval) -> JSONValue { .string(iso.string(from: now + offset)) }
        let days: JSONValue = .array((0..<7).map { back in
            let day = Calendar.current.date(byAdding: .day, value: back - 6, to: now)!
            let tokens = [42_700, 1_250_000, 0, 18_400_000, 7_900_000, 64_300_000, 103_000_000][back]
            return ["date": .string(Usage.localDate(day)), "messageCount": .number(Double(tokens))]
        })
        let models: JSONValue = [
            "claude-opus-5-5": ["inputTokens": 168, "outputTokens": 50607, "cacheReadInputTokens": 5_013_231, "cacheCreationInputTokens": 289_404],
            "claude-opus-5": ["inputTokens": 98, "outputTokens": 31200, "cacheReadInputTokens": 2_904_112, "cacheCreationInputTokens": 120_000],
            "claude-sonnet-4-5-20250929": ["inputTokens": 1200, "outputTokens": 40100, "cacheReadInputTokens": 880_000],
            "claude-haiku-4-5": ["inputTokens": 900, "outputTokens": 12000],
            "claude-opus-4-8": ["inputTokens": 10],
        ]
        var fields: [String: JSONValue] = [
            "id": "claude", "name": "Claude Code", "tierLabel": "Max 5x", "usageStatusText": "", "authHelpText": "",
            "totalPrompts": 74, "todayPrompts": 30, "todaySessions": 2, "hasPromptStats": true, "updatedAt": at(-60),
            "limits": [
                ["label": "Session (5-hour)", "percent": 0.61, "resetsAt": at(23 * 60 + 5)],
                ["label": "Weekly (7-day)", "percent": 0.18, "resetsAt": at(5 * 86400 + 3600)],
                ["label": "Opus 5 (1M context)", "title": "Fable Weekly", "percent": 0.04, "resetsAt": at(2 * 86400)],
            ],
            "recentDays": days,
            "todayTotalTokens": 103_000_000,
            "todayTokensByModel": ["claude-opus-5-5": 71_000_000, "claude-opus-5": 26_500_000, "claude-haiku-4-5": 5_500_000],
            "modelUsage": models,
        ]
        claude = AgentRecord(fields)

        fields["limits"] = [
            ["label": "Session (5-hour)", "percent": 0.94, "resetsAt": at(12 * 60)],
            ["label": "Weekly (7-day)", "percent": 0.52, "resetsAt": at(3 * 86400)],
        ]
        fields["limitsStale"] = true
        fields["limitsFetchedAt"] = at(-37 * 60)
        fields["limitsNote"] = "Anthropic is rate limiting checks · next try 14:02"
        claudeStale = AgentRecord(fields)

        fields["usageStatusText"] = "Sign-in expired"
        fields["authHelpText"] = "Claude Code's saved sign-in expired — showing the last known limits. Start Claude Code, or run `claude auth login`, to refresh it."
        fields["limitsNote"] = "Claude Code's saved sign-in expired"
        claudeSignedOut = AgentRecord(fields)

        codex = AgentRecord([
            "id": "codex", "name": "Codex", "tierLabel": "", "usageStatusText": "Codex unavailable",
            "authHelpText": "codex not found in PATH", "totalPrompts": 3, "limits": [], "updatedAt": at(-60),
            "recentDays": days, "modelUsage": ["gpt-5.6-sol": ["inputTokens": 120_000, "outputTokens": 9000]],
        ])
    }
}
