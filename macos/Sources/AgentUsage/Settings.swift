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
                Stepper(value: $limits, in: 30...3600, step: 30) {
                    LabeledContent("Check limits every", value: "\(limits) seconds")
                }
                Stepper(value: $scan, in: 5...60) {
                    LabeledContent("Rescan local usage every", value: "\(scan) minutes")
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Changes apply right away. Limit checks keep the percentage in the menu bar current, and opening the panel always checks right away. Anthropic refuses checks that come too often; checking then pauses for 1 to 15 minutes. Rescans reread transcripts and OpenCode history for the token charts. The panel also refreshes after you unlock the screen and when the Mac wakes from sleep.")
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
                Text("What the terminal button in the panel, and right-clicking the menu bar icon, opens. In a custom terminal command, {command} is where the agent goes; without it, the agent goes at the end.")
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
                Toggle("Check daily for a new version", isOn: $checkUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("Asks GitHub for the newest release. The panel says when one is out.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit Agent Usage") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 720)
    }
}
