import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var status: StatusController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Assets.registerFonts()
        Settings.registerDefaults()

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot") {
            let folder = index + 1 < arguments.count ? arguments[index + 1] : "snapshots"
            do {
                try Snapshot.run(into: folder)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }

        MainMenu.install()
        LoginItem.enableOnFirstStart()

        let model = AppModel()
        let status = StatusController(model: model)
        let settings = SettingsWindowController(machine: { model.machine })
        model.onOpenSettings = { [weak status, weak settings] in
            status?.close()
            settings?.show()
        }
        self.model = model
        self.status = status
        self.settings = settings
        model.start()
        if arguments.contains("--settings") {
            settings.show()
        }
    }

    // Opening the app again (from Finder, Spotlight or `open`) while it runs
    // brings up its settings: there's no window otherwise.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return false
    }
}

// `agent-usage uninstall` asks the app to leave the login items before it
// deletes it; only the app itself can.
if CommandLine.arguments.contains("--unregister-login-item") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A menu bar app: no Dock icon, no menu bar of its own.
app.setActivationPolicy(.accessory)
app.run()
