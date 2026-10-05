import AgentUsageCore
import AppKit
import ServiceManagement

/// What build-app.sh wrote into Info.plist.
enum AppInfo {
    /// `0.6.0` on a release, `0.6.0-dev+3f2a1c` otherwise.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "AgentUsageVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// `owner/name` of the GitHub repository releases come from.
    static var repository: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AgentUsageRepository") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The `agent-usage` command inside the app, which installs updates.
    static var command: String? {
        let path = Bundle.main.resourceURL?.appendingPathComponent("bin/agent-usage").path
        return path.flatMap { Programs.isProgram($0) ? $0 : nil }
    }

    static var inApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}

/// Starting at login, through macOS's own login items (macOS 13 and up).
enum LoginItem {
    enum State {
        case on, off, needsApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// On the first start from an Applications folder, turn it on. A copy
    /// opened from Downloads or a build folder is left alone.
    static func enableOnFirstStart() {
        let defaults = UserDefaults.standard
        guard AppInfo.inApplicationsFolder, !defaults.bool(forKey: Settings.loginItemConfigured) else {
            return
        }
        defaults.set(true, forKey: Settings.loginItemConfigured)
        do {
            try set(true)
            Log.write("start at login: on")
        } catch {
            Log.write("start at login: \(error.localizedDescription)")
        }
    }
}

/// Asks GitHub for the newest release: its API, or the release page when the
/// API's hourly limit for this network has run out.
enum ReleaseChecker {
    static func latest(_ done: @escaping (Result<String, ReleaseCheckError>) -> Void) {
        let finish = { (result: Result<String, ReleaseCheckError>) in DispatchQueue.main.async { done(result) } }
        guard let repository = AppInfo.repository, let api = Releases.latestURL(repository: repository),
              let page = Releases.pageURL(repository: repository) else {
            finish(.failure(ReleaseCheckError("this build doesn't know where its releases are")))
            return
        }
        var request = URLRequest(url: api, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("agent-usage/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                finish(.failure(ReleaseCheckError(error.localizedDescription)))
            } else if status == 404 {
                finish(.failure(ReleaseCheckError("no releases yet")))
            } else if status == 200, let data, let version = Releases.latestVersion(fromAPI: data) {
                finish(.success(version))
            } else {
                fromPage(page, apiStatus: status, finish)
            }
        }.resume()
    }

    private static func fromPage(_ page: URL, apiStatus: Int, _ finish: @escaping (Result<String, ReleaseCheckError>) -> Void) {
        var request = URLRequest(url: page, timeoutInterval: 20)
        request.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let final = response?.url, let version = Releases.latestVersion(fromPage: final) {
                finish(.success(version))
            } else {
                finish(.failure(ReleaseCheckError(error?.localizedDescription ?? "GitHub answered with status \(apiStatus)")))
            }
        }.resume()
    }
}

/// The settings' keys and defaults, the GNOME schema's.
enum Settings {
    static let limitsInterval = "limitsInterval"
    static let scanInterval = "scanInterval"
    static let sessionThreshold = "sessionThreshold"
    static let agent = "agent"
    static let agentCommand = "agentCommand"
    static let terminal = "terminal"
    static let terminalCommand = "terminalCommand"
    static let checkUpdates = "checkUpdates"
    static let loginItemConfigured = "loginItemConfigured"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            limitsInterval: 300, scanInterval: 15, sessionThreshold: 40, agent: "opencode", agentCommand: "",
            terminal: "auto", terminalCommand: "", checkUpdates: true,
        ])
    }

    static var launchPrefs: LaunchPrefs {
        let defaults = UserDefaults.standard
        return LaunchPrefs(
            agent: defaults.string(forKey: agent) ?? "opencode",
            agentCommand: defaults.string(forKey: agentCommand) ?? "",
            terminal: defaults.string(forKey: terminal) ?? "auto",
            terminalCommand: defaults.string(forKey: terminalCommand) ?? ""
        )
    }
}

/// An app without a Dock icon shows no menu bar of its own, but its key
/// equivalents still work: copy and paste in the settings' text fields,
/// Cmd-W to close the window, Cmd-Q to quit.
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Agent Usage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Agent Usage")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: window, title: "Window")

        NSApp.mainMenu = main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
