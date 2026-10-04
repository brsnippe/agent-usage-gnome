import Foundation

// Which agent "Open …" starts, and in which terminal, or which desktop app it
// opens: the macOS counterpart of the GNOME extension's terminals.js. Shared
// by the panel and the settings window, so "Open" in the settings behaves
// exactly like the panel button.

/// An app found by its bundle id, or by its folder name in the usual places.
public protocol AppBundle {
    var bundleID: String { get }
    /// The bundle's folder name, for finding it without a bundle id lookup.
    var appName: String { get }
}

public struct DesktopApp: AppBundle, Equatable {
    public var bundleID: String
    public var appName: String
}

/// An agent has a command to run in a terminal, or is a desktop app.
public struct AgentChoice: Equatable {
    public var id: String
    public var name: String
    public var command: String?
    public var app: DesktopApp?

    public init(id: String, name: String, command: String? = nil, app: DesktopApp? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.app = app
    }
}

public struct TerminalApp: AppBundle, Equatable {
    public enum Style: Equatable {
        /// Opens a `.command` script, the way Finder does: no permission to
        /// script the terminal needed, and the user's own shell runs it.
        case commandFile
        /// Started with `open -na <app> --args <prefix> <command…>`.
        case arguments([String])
    }

    public var id: String
    public var name: String
    public var bundleID: String
    public var appName: String
    public var style: Style
}

/// One entry of a settings list: the id it stores, the label it shows.
public struct Choice: Equatable, Hashable {
    public var id: String
    public var label: String
}

public struct LaunchPrefs: Equatable {
    /// An agent's id (`opencode`, `claude-desktop`, …) or `custom`.
    public var agent: String
    public var agentCommand: String
    /// `auto`, a terminal's id, or `custom`.
    public var terminal: String
    public var terminalCommand: String

    public init(agent: String = "opencode", agentCommand: String = "", terminal: String = "auto", terminalCommand: String = "") {
        self.agent = agent
        self.agentCommand = agentCommand
        self.terminal = terminal
        self.terminalCommand = terminalCommand
    }
}

/// What a launch needs to know about this Mac. The tests pass a fake one.
public struct Machine {
    public var findProgram: (String) -> String?
    public var findApp: (any AppBundle) -> String?
    /// The user's login shell, which starts the agent so it gets the PATH the
    /// user has in a terminal.
    public var shell: String
    public var home: String

    public init(findProgram: @escaping (String) -> String?, findApp: @escaping (any AppBundle) -> String?, shell: String, home: String) {
        self.findProgram = findProgram
        self.findApp = findApp
        self.shell = shell
        self.home = home
    }

    public static func local(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        findApp: ((any AppBundle) -> String?)? = nil
    ) -> Machine {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let dirs = Programs.searchDirs(path: environment["PATH"] ?? "", home: home)
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        return Machine(
            findProgram: { Programs.find($0, in: dirs, home: home) },
            findApp: findApp ?? { Terminals.findAppInFolders($0, home: home) },
            shell: shell,
            home: home
        )
    }
}

public struct Launch: Equatable {
    /// The command to run. With a script, the script's path goes at the end.
    public var argv: [String]
    /// A `.command` script to write first, for terminals that open one.
    public var script: String?
    /// The agent's own command line, before the terminal wraps it.
    public var command: [String]
    public var agentName: String
    public var terminalName: String
    /// A desktop app rather than an agent in a terminal.
    public var opensApp = false

    /// The command line as a person would type it, for the settings window.
    public func display(home: String) -> String {
        script == nil
            ? Terminals.displayCommand(argv, home: home)
            : "\(terminalName): \(Terminals.displayCommand(command, home: home))"
    }
}

public struct LaunchError: Error, Equatable {
    public enum Reason: Equatable {
        /// Nothing to open: the panel hides its button.
        case agent
        /// Nowhere to open it: the button stays, and says what's wrong.
        case terminal
    }

    public var message: String
    public var reason: Reason
    public var agentName: String
}

public struct TerminalLaunch: Equatable {
    public var argv: [String]
    public var script: String?
    public var terminalName: String
}

public enum Terminals {
    public static let agents = [
        AgentChoice(id: "opencode", name: "OpenCode", command: "opencode"),
        AgentChoice(id: "opencode-desktop", name: "OpenCode (desktop app)", app: DesktopApp(bundleID: "ai.opencode.desktop", appName: "OpenCode.app")),
        AgentChoice(id: "claude", name: "Claude Code", command: "claude"),
        AgentChoice(id: "claude-desktop", name: "Claude (desktop app)",
                    app: DesktopApp(bundleID: "com.anthropic.claudefordesktop", appName: "Claude.app")),
        AgentChoice(id: "codex", name: "Codex", command: "codex"),
    ]

    public static let terminals = [
        TerminalApp(id: "terminal", name: "Terminal", bundleID: "com.apple.Terminal", appName: "Terminal.app", style: .commandFile),
        TerminalApp(id: "iterm2", name: "iTerm2", bundleID: "com.googlecode.iterm2", appName: "iTerm.app", style: .commandFile),
        TerminalApp(id: "ghostty", name: "Ghostty", bundleID: "com.mitchellh.ghostty", appName: "Ghostty.app", style: .arguments(["-e"])),
        TerminalApp(id: "kitty", name: "Kitty", bundleID: "net.kovidgoyal.kitty", appName: "kitty.app", style: .arguments([])),
        TerminalApp(id: "alacritty", name: "Alacritty", bundleID: "org.alacritty", appName: "Alacritty.app", style: .arguments(["-e"])),
        TerminalApp(id: "wezterm", name: "WezTerm", bundleID: "com.github.wez.wezterm", appName: "WezTerm.app", style: .arguments(["start", "--"])),
    ]

    /// "Automatic": every Mac has Terminal.
    static let automatic = ["terminal"]

    static let open = "/usr/bin/open"

    public static func installedTerminals(on machine: Machine) -> [TerminalApp] {
        terminals.filter { machine.findApp($0) != nil }
    }

    /// The settings window's agents: all of them, marked when this Mac
    /// doesn't have one.
    public static func agentChoices(on machine: Machine) -> [Choice] {
        agents.map { Choice(id: $0.id, label: isInstalled($0, on: machine) ? $0.name : "\($0.name) (not installed)") }
            + [Choice(id: "custom", label: "Custom…")]
    }

    public static func isInstalled(_ agent: AgentChoice, on machine: Machine) -> Bool {
        if let app = agent.app {
            return machine.findApp(app) != nil
        }
        return agent.command.flatMap(machine.findProgram) != nil
    }

    /// The settings window's terminals: the installed ones, plus the current
    /// choice if it has since been uninstalled, so the list can still show it.
    public static func terminalChoices(current: String, on machine: Machine) -> [Choice] {
        let installed = installedTerminals(on: machine)
        let listed = terminals.filter { installed.contains($0) || $0.id == current }
        return [Choice(id: "auto", label: "Automatic (Terminal)")]
            + listed.map { Choice(id: $0.id, label: installed.contains($0) ? $0.name : "\($0.name) (not installed)") }
            + [Choice(id: "custom", label: "Custom…")]
    }

    public static func findAppInFolders(_ app: any AppBundle, home: String) -> String? {
        let folders = ["/Applications", "/System/Applications/Utilities", "/System/Applications", "\(home)/Applications"]
        var isFolder: ObjCBool = false
        return folders.map { "\($0)/\(app.appName)" }.first {
            FileManager.default.fileExists(atPath: $0, isDirectory: &isFolder) && isFolder.boolValue
        }
    }

    public static func resolveLaunch(_ prefs: LaunchPrefs, on machine: Machine) -> Result<Launch, LaunchError> {
        let agentName: String
        let command: [String]
        let chosen = agents.first { $0.id == prefs.agent }
        if let chosen, let app = chosen.app {
            // `open -a` brings the app forward when it's already open.
            guard let path = machine.findApp(app) else {
                return .failure(LaunchError(message: "\(chosen.name) isn't installed.", reason: .agent, agentName: chosen.name))
            }
            return .success(Launch(argv: [open, "-a", path], script: nil, command: [], agentName: chosen.name, terminalName: "", opensApp: true))
        }
        if prefs.agent == "custom" {
            let words: [String]
            do {
                words = try ShellWords.split(prefs.agentCommand)
            } catch {
                return .failure(LaunchError(message: "The custom agent command can't be read: \(error)", reason: .agent, agentName: "agent"))
            }
            guard let first = words.first else {
                return .failure(LaunchError(message: "Enter a custom agent command in the settings.", reason: .agent, agentName: "agent"))
            }
            agentName = basename(first)
            guard let path = machine.findProgram(first) else {
                return .failure(LaunchError(message: "\(first) isn't installed.", reason: .agent, agentName: agentName))
            }
            command = [path] + words.dropFirst()
        } else {
            let agent = chosen ?? agents[0]
            let program = agent.command ?? agent.id
            agentName = agent.name
            guard let path = machine.findProgram(program) else {
                return .failure(LaunchError(message: "\(agent.name) isn't installed (no \(program) found).", reason: .agent, agentName: agentName))
            }
            command = [path]
        }

        switch terminalLaunch(prefs, command: command, on: machine) {
        case .failure(let error):
            return .failure(LaunchError(message: error.message, reason: .terminal, agentName: agentName))
        case .success(let terminal):
            return .success(Launch(argv: terminal.argv, script: terminal.script, command: command, agentName: agentName, terminalName: terminal.terminalName))
        }
    }

    /// The chosen terminal, running `command` (an argv) from the home folder.
    public static func terminalLaunch(_ prefs: LaunchPrefs, command: [String], on machine: Machine) -> Result<TerminalLaunch, LaunchError> {
        let failure = { (message: String) in
            Result<TerminalLaunch, LaunchError>.failure(LaunchError(message: message, reason: .terminal, agentName: ""))
        }
        // Terminals started through `open` get launchd's bare environment, so
        // the user's login shell starts the command, as a terminal window would.
        let inShell = [machine.shell, "-lic", "cd ~ && exec \(shellJoin(command))"]

        if prefs.terminal == "custom" {
            let argv: [String]
            switch fillTemplate(prefs.terminalCommand, command: inShell) {
            case .failure(let error): return failure(error.message)
            case .success(let filled): argv = filled
            }
            guard let program = machine.findProgram(argv[0]) else {
                return failure("\(argv[0]), from the custom terminal command, isn't installed.")
            }
            return .success(TerminalLaunch(argv: [program] + argv.dropFirst(), script: nil, terminalName: basename(argv[0])))
        }

        let chosen = terminals.first { $0.id == prefs.terminal }
        let candidates = chosen.map { [$0] } ?? terminals.filter { automatic.contains($0.id) }
        for terminal in candidates {
            guard let app = machine.findApp(terminal) else {
                continue
            }
            switch terminal.style {
            case .commandFile:
                return .success(TerminalLaunch(argv: [open, "-a", app], script: "#!/bin/sh\nexec \(shellJoin(command))\n", terminalName: terminal.name))
            case .arguments(let prefix):
                return .success(TerminalLaunch(argv: [open, "-na", app, "--args"] + prefix + inShell, script: nil, terminalName: terminal.name))
            }
        }
        // A terminal picked by name that has since gone missing is an error,
        // not a reason to quietly open something else.
        return failure(chosen.map { "\($0.name) isn't installed." } ?? "No terminal found. Pick one in the settings.")
    }

    /// The header button's tooltip, or nil when there's no agent to open. A
    /// missing terminal still gets the button, so clicking it says what's wrong.
    public static func buttonHint(_ launch: Result<Launch, LaunchError>) -> String? {
        switch launch {
        case .success(let launch): return launch.opensApp ? "Open \(launch.agentName)" : "Open \(launch.agentName) in \(launch.terminalName)"
        case .failure(let error): return error.reason == .agent ? nil : "Open \(error.agentName)"
        }
    }

    /// A command-line tool in the chosen terminal, such as `claude auth login`
    /// from the problem card. `pause` keeps the window open once it's done.
    public static func commandLaunch(_ prefs: LaunchPrefs, command: [String], pause: Bool = false, on machine: Machine) -> Result<TerminalLaunch, LaunchError> {
        let name = command.first ?? ""
        guard let path = machine.findProgram(name) else {
            return .failure(LaunchError(message: "\(name) isn't installed.", reason: .agent, agentName: ""))
        }
        let full = [path] + command.dropFirst()
        return terminalLaunch(prefs, command: pause ? withPause(full) : full, on: machine)
    }

    /// So the last words of a short command (signed in, or why not) can be
    /// read before the terminal closes.
    public static func withPause(_ command: [String]) -> [String] {
        ["/bin/sh", "-c", #""$@"; status=$?; printf "\nPress Enter to close this window. "; read -r _; exit $status"#, "sh"] + command
    }

    /// A custom terminal command. `{command}` on its own becomes the command's
    /// arguments; inside a longer argument (`--exec={command}`) it becomes one
    /// quoted string; with no `{command}` at all the command goes at the end.
    public static func fillTemplate(_ template: String, command: [String]) -> Result<[String], LaunchError> {
        let words: [String]
        do {
            words = try ShellWords.split(template)
        } catch {
            return .failure(LaunchError(message: "The custom terminal command can't be read: \(error)", reason: .terminal, agentName: ""))
        }
        guard !words.isEmpty else {
            return .failure(LaunchError(message: "Enter a custom terminal command in the settings.", reason: .terminal, agentName: ""))
        }
        var used = false
        var argv: [String] = []
        for word in words {
            if word == "{command}" {
                argv += command
                used = true
            } else if word.contains("{command}") {
                argv.append(word.replacingOccurrences(of: "{command}", with: shellJoin(command)))
                used = true
            } else {
                argv.append(word)
            }
        }
        if !used {
            argv += command
        }
        return .success(argv)
    }

    private static let plainWord = Pattern(#"^[\w@%+=:,./~-]+$"#)

    public static func displayCommand(_ argv: [String], home: String) -> String {
        argv.map { arg in
            let shown = arg.hasPrefix("\(home)/") ? "~" + arg.dropFirst(home.count) : arg
            return plainWord.matches(shown) ? shown : ShellWords.quote(shown)
        }.joined(separator: " ")
    }

    static func shellJoin(_ argv: [String]) -> String {
        argv.map(ShellWords.quote).joined(separator: " ")
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

// ------------------------------------------------------------------ programs

public enum Programs {
    /// Apps started at login get launchd's bare PATH, without Homebrew or the
    /// per-user folders CLIs install into.
    public static func searchDirs(path: String, home: String) -> [String] {
        let extra = [
            "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.opencode/bin", "\(home)/.npm-global/bin",
            "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.local/share/mise/shims",
        ]
        var dirs: [String] = []
        for dir in path.split(separator: ":").map(String.init) + extra where !dir.isEmpty && !dirs.contains(dir) {
            dirs.append(dir)
        }
        return dirs
    }

    public static func isProgram(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    public static func find(_ name: String, in dirs: [String], home: String, isProgram: (String) -> Bool = isProgram) -> String? {
        guard !name.isEmpty else {
            return nil
        }
        let expanded = name.hasPrefix("~/") ? home + name.dropFirst() : name
        if expanded.contains("/") {
            return isProgram(expanded) ? expanded : nil
        }
        return dirs.map { "\($0)/\(expanded)" }.first(where: isProgram)
    }
}

// --------------------------------------------------------------- shell words

/// Shell-style word splitting and quoting, as GLib's `g_shell_parse_argv` and
/// `g_shell_quote` do it for the GNOME extension: quotes and backslashes, no
/// expansions.
public enum ShellWords {
    public struct ParseError: Error, CustomStringConvertible, Equatable {
        public var description: String
    }

    public static func split(_ text: String) throws -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var chars = Array(text)[...]

        while let char = chars.popFirst() {
            switch char {
            case " ", "\t", "\n":
                if inWord {
                    words.append(word)
                    word = ""
                    inWord = false
                }
            case "#" where !inWord:
                while let next = chars.first, next != "\n" {
                    chars.removeFirst()
                }
            case "\\":
                inWord = true
                guard let next = chars.popFirst() else {
                    throw ParseError(description: "Text ended just after a “\\” character.")
                }
                if next != "\n" {
                    word.append(next)
                }
            case "'":
                inWord = true
                guard let end = chars.firstIndex(of: "'") else {
                    throw ParseError(description: "Text ended before matching quote was found for '.")
                }
                word += chars[..<end]
                chars = chars[(end + 1)...]
            case "\"":
                inWord = true
                var closed = false
                while let next = chars.popFirst() {
                    if next == "\"" {
                        closed = true
                        break
                    }
                    if next == "\\", let escaped = chars.first, "$`\"\\\n".contains(escaped) {
                        chars.removeFirst()
                        if escaped != "\n" {
                            word.append(escaped)
                        }
                    } else {
                        word.append(next)
                    }
                }
                if !closed {
                    throw ParseError(description: "Text ended before matching quote was found for \".")
                }
            default:
                inWord = true
                word.append(char)
            }
        }
        if inWord {
            words.append(word)
        }
        return words
    }

    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
