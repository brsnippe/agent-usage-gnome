import AgentUsageCore
import AppKit
import ServiceManagement
import SwiftUI

/// The settings window: the GNOME extension's preferences, plus starting at
/// login and quitting, which a menu bar app has to offer itself.
final class SettingsWindowController {
    private let model: SettingsModel
    private(set) var window: NSWindow?

    init(machine: @escaping () -> Machine) {
        model = SettingsModel(machine: machine)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Agent Usage Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsModel: ObservableObject {
    @Published var versionLine = ""
    @Published var updateAvailable = false
    @Published var updateNote: String?
    @Published var login = LoginItem.State.off
    @Published var loginError: String?
    @Published var tryNote: String?
    let machine: () -> Machine

    init(machine: @escaping () -> Machine) {
        self.machine = machine
    }

    var shownVersion: String { AppInfo.version.isEmpty ? "an unknown version" : "v\(AppInfo.version)" }

    func refresh() {
        login = LoginItem.state
        loginError = nil
        tryNote = nil
        updateNote = nil
        versionLine = "\(shownVersion) · checking for a newer version…"
        updateAvailable = false
        ReleaseChecker.latest { [weak self] result in
            let status = Releases.status(installed: AppInfo.version, latest: result)
            self?.versionLine = status.text
            self?.updateAvailable = status.updateAvailable
        }
    }

    func setLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = "Couldn't change it: \(error.localizedDescription)"
        }
        login = LoginItem.state
    }

    func tryLaunch(_ launch: Launch) {
        do {
            try Launcher.run(argv: launch.argv, script: launch.script, name: launch.agentName)
            tryNote = nil
        } catch {
            tryNote = "Couldn't start it: \(error.localizedDescription)"
        }
    }

    /// In a terminal, so the progress is visible.
    func runUpdate() {
        guard let command = AppInfo.command else {
            updateNote = "This copy can't update itself. Install it with get.sh (see the README)."
            return
        }
        switch Terminals.terminalLaunch(Settings.launchPrefs, command: [command, "update", "--pause"], on: machine()) {
        case .failure(let error):
            updateNote = error.message
        case .success(let terminal):
            do {
                try Launcher.run(argv: terminal.argv, script: terminal.script, name: "Update Agent Usage")
                updateNote = "Updating in \(terminal.terminalName). Agent Usage restarts when it's done."
                updateAvailable = false
            } catch {
                updateNote = "Couldn't start the update: \(error.localizedDescription)"
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Settings.limitsInterval) private var limits = 300
    @AppStorage(Settings.scanInterval) private var scan = 15
    @AppStorage(Settings.sessionThreshold) private var sessionFrom = 40
    @AppStorage(Settings.agent) private var agent = "opencode"
    @AppStorage(Settings.agentCommand) private var agentCommand = ""
    @AppStorage(Settings.terminal) private var terminal = "auto"
    @AppStorage(Settings.terminalCommand) private var terminalCommand = ""
    @AppStorage(Settings.checkUpdates) private var checkUpdates = true

    var body: some View {
        let machine = model.machine()
        let prefs = LaunchPrefs(agent: agent, agentCommand: agentCommand, terminal: terminal, terminalCommand: terminalCommand)
        let launch = Terminals.resolveLaunch(prefs, on: machine)

        Form {
            Section {
                LabeledContent("Check limits every") {
                    HStack {
                        Text("\(limits) seconds").foregroundColor(.secondary)
                        Stepper("Check limits every", value: $limits, in: 30...3600, step: 30).labelsHidden()
                    }
                }
                LabeledContent("Rescan local usage every") {
                    HStack {
                        Text("\(scan) minutes").foregroundColor(.secondary)
                        Stepper("Rescan local usage every", value: $scan, in: 5...60).labelsHidden()
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                note("Changes apply right away. Opening the panel always checks limits too, and so do unlocking and waking the Mac. Anthropic refuses checks that come too often; checking then pauses for 1 to 15 minutes. Rescans reread transcripts and OpenCode history for the token charts.")
            }

            Section {
                LabeledContent("Show the session limit from") {
                    HStack {
                        Text("\(sessionFrom)%").foregroundColor(.secondary)
                        Stepper("Show the session limit from", value: $sessionFrom, in: 0...100, step: 5).labelsHidden()
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                note("Once the 5-hour session limit is this full, the menu bar shows it, even when the weekly limit is fuller. Below it, the menu bar shows the fullest limit. 0% always shows the session limit.")
            }

            Section {
                Picker("Agent", selection: $agent) {
                    ForEach(Terminals.agentChoices(on: machine), id: \.id) { Text($0.label).tag($0.id) }
                }
                if agent == "custom" {
                    TextField("Custom agent command", text: $agentCommand, prompt: Text("claude --continue"))
                }
                Picker("Terminal", selection: $terminal) {
                    ForEach(Terminals.terminalChoices(current: terminal, on: machine), id: \.id) { Text($0.label).tag($0.id) }
                }
                if terminal == "custom" {
                    TextField("Custom terminal command", text: $terminalCommand, prompt: Text("open -na Ghostty --args -e {command}"))
                }
                LabeledContent("Try it") {
                    HStack(alignment: .firstTextBaseline) {
                        switch launch {
                        case .success(let ready):
                            Text(model.tryNote ?? ready.display(home: machine.home))
                                .textSelection(.enabled)
                                .foregroundColor(.secondary)
                            Button("Open") { model.tryLaunch(ready) }
                        case .failure(let error):
                            Text(error.message).foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Open agent")
            } footer: {
                note("What the panel's open button, and right-clicking the menu bar icon, opens: an agent in a terminal, or a desktop app. Signing in and updating use the terminal too. In a custom terminal command, {command} is where the agent goes; without it, the agent goes at the end.")
            }

            Section {
                Toggle("Start at login", isOn: Binding(get: { model.login == .on }, set: { model.setLogin($0) }))
                if model.login == .needsApproval {
                    LabeledContent("macOS is waiting for you to allow it") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = model.loginError {
                    Text(error).foregroundColor(.red)
                }
                LabeledContent("Agent Usage keeps running in the menu bar") {
                    Button("Quit") { NSApp.terminate(nil) }
                }
            } header: {
                Text("Startup")
            }

            Section {
                LabeledContent("Version") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.updateNote ?? model.versionLine)
                            .textSelection(.enabled)
                            .foregroundColor(.secondary)
                        if model.updateAvailable {
                            Button("Update") { model.runUpdate() }
                        }
                    }
                }
                Toggle("Check for new versions", isOn: $checkUpdates)
            } header: {
                Text("Updates")
            } footer: {
                note("Every hour, and after waking or unlocking the Mac. Asks GitHub for the newest release. The panel says when one is out.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 760)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
