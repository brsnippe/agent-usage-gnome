import XCTest

@testable import AgentUsageCore

// The macOS counterpart of test/terminals-test.js.
final class TerminalsTests: XCTestCase {
    static let home = "/Users/me"

    /// A fake Mac: which programs and terminal apps exist.
    func machine(programs: [String] = ["opencode", "claude"], apps: [String] = ["Terminal.app", "Ghostty.app"]) -> Machine {
        Machine(
            findProgram: { name in
                if name.hasPrefix("/") {
                    return programs.contains { "/opt/homebrew/bin/\($0)" == name } ? name : nil
                }
                return programs.contains(name) ? "/opt/homebrew/bin/\(name)" : nil
            },
            findApp: { terminal in apps.contains(terminal.appName) ? "/Applications/\(terminal.appName)" : nil },
            shell: "/bin/zsh",
            home: Self.home
        )
    }

    func launch(_ prefs: LaunchPrefs = LaunchPrefs(), on mac: Machine? = nil) -> Result<Launch, LaunchError> {
        Terminals.resolveLaunch(prefs, on: mac ?? machine())
    }

    func argv(_ result: Result<Launch, LaunchError>) -> [String]? {
        try? result.get().argv
    }

    func error(_ result: Result<Launch, LaunchError>) -> LaunchError? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }

    /// The agent, started by the login shell from the home folder.
    func inShell(_ command: String) -> [String] {
        ["/bin/zsh", "-lic", "cd ~ && exec \(command)"]
    }

    func testAutomaticOpensTerminalWithACommandFile() throws {
        let result = try launch().get()
        XCTAssertEqual(result.argv, ["/usr/bin/open", "-a", "/Applications/Terminal.app"])
        XCTAssertEqual(result.script, "#!/bin/sh\nexec '/opt/homebrew/bin/opencode'\n")
        XCTAssertEqual([result.agentName, result.terminalName], ["OpenCode", "Terminal"])
        XCTAssertEqual(result.display(home: Self.home), "Terminal: /opt/homebrew/bin/opencode")
    }

    func testEveryTerminalBuildsItsOwnCommandLine() {
        let every = machine(apps: Terminals.terminals.map(\.appName))
        let lines = Terminals.terminals.map { terminal -> String in
            let result = try! launch(LaunchPrefs(terminal: terminal.id), on: every).get()
            return (result.argv.dropFirst(2).map { $0.replacingOccurrences(of: "/Applications/", with: "") } + [result.script == nil ? "" : "+ script"])
                .joined(separator: " ")
        }
        let shell = "/bin/zsh -lic cd ~ && exec '/opt/homebrew/bin/opencode'"
        XCTAssertEqual(lines, [
            "Terminal.app + script",
            "iTerm.app + script",
            "Ghostty.app --args -e \(shell) ",
            "kitty.app --args \(shell) ",
            "Alacritty.app --args -e \(shell) ",
            "WezTerm.app --args start -- \(shell) ",
        ])
        XCTAssertEqual(launch(LaunchPrefs(terminal: "ghostty"), on: every).map(\.argv).map { Array($0.prefix(2)) }, .success(["/usr/bin/open", "-na"]),
                       "open-args terminals get a new instance each time")
    }

    func testMissingPieces() {
        XCTAssertEqual(error(launch(LaunchPrefs(terminal: "kitty"))), LaunchError(message: "Kitty isn't installed.", reason: .terminal, agentName: "OpenCode"),
                       "a chosen terminal that is missing is an error, not a fallback")
        XCTAssertEqual(error(launch(on: machine(apps: [])))?.message, "No terminal found. Pick one in the settings.")
        XCTAssertEqual(error(launch(LaunchPrefs(agent: "codex"))), LaunchError(message: "Codex isn't installed (no codex found).", reason: .agent, agentName: "Codex"),
                       "a missing agent hides the button")
    }

    func testAgents() throws {
        XCTAssertEqual(argv(launch(LaunchPrefs(agent: "claude", terminal: "ghostty"))),
                       ["/usr/bin/open", "-na", "/Applications/Ghostty.app", "--args", "-e"] + inShell("'/opt/homebrew/bin/claude'"))
        XCTAssertEqual(try launch(LaunchPrefs(agent: "claude")).get().agentName, "Claude Code")
        XCTAssertEqual(try launch(LaunchPrefs(agent: "custom", agentCommand: "claude --continue")).get().script,
                       "#!/bin/sh\nexec '/opt/homebrew/bin/claude' '--continue'\n", "custom agent with arguments")
        XCTAssertEqual(try launch(LaunchPrefs(agent: "custom", agentCommand: "claude --continue")).get().agentName, "claude")
        XCTAssertEqual(error(launch(LaunchPrefs(agent: "custom")))?.message, "Enter a custom agent command in the settings.")
        XCTAssertEqual(error(launch(LaunchPrefs(agent: "custom", agentCommand: "aider --yes")))?.message, "aider isn't installed.")
        XCTAssertEqual(error(launch(LaunchPrefs(agent: "custom", agentCommand: #"claude "--x"#)))?.reason, .agent, "custom agent with broken quoting")
    }

    func testCustomTerminal() {
        let mac = machine(programs: ["opencode", "claude", "open", "alacritty"])
        func custom(_ template: String, agent: String = "opencode", agentCommand: String = "") -> Result<Launch, LaunchError> {
            launch(LaunchPrefs(agent: agent, agentCommand: agentCommand, terminal: "custom", terminalCommand: template), on: mac)
        }
        XCTAssertEqual(argv(custom("open -na Ghostty --args --window-decoration=false -e {command}", agent: "custom", agentCommand: "claude --continue")),
                       ["/opt/homebrew/bin/open", "-na", "Ghostty", "--args", "--window-decoration=false", "-e"]
                           + inShell("'/opt/homebrew/bin/claude' '--continue'"),
                       "{command} as its own word")
        XCTAssertEqual(argv(custom("alacritty -e")), ["/opt/homebrew/bin/alacritty", "-e"] + inShell("'/opt/homebrew/bin/opencode'"),
                       "without {command} the command goes at the end")
        XCTAssertEqual(argv(custom("alacritty --command={command}")),
                       ["/opt/homebrew/bin/alacritty", #"--command='/bin/zsh' '-lic' 'cd ~ && exec '\''/opt/homebrew/bin/opencode'\'''"#],
                       "{command} inside a word becomes one quoted string")
        XCTAssertEqual(argv(custom("alacritty --title='Agent usage' -e {command}"))?.prefix(3).map { $0 },
                       ["/opt/homebrew/bin/alacritty", "--title=Agent usage", "-e"], "quoted arguments stay together")
        XCTAssertEqual(error(custom(""))?.message, "Enter a custom terminal command in the settings.")
        XCTAssertEqual(error(custom("tilix -e {command}"))?.message, "tilix, from the custom terminal command, isn't installed.")
        XCTAssertEqual(error(custom("tilix -e {command}"))?.reason, .terminal)
    }

    func testButtonHint() {
        XCTAssertEqual(Terminals.buttonHint(launch()), "Open OpenCode in Terminal")
        XCTAssertEqual(Terminals.buttonHint(launch(LaunchPrefs(terminal: "kitty"))), "Open OpenCode", "a missing terminal keeps the button")
        XCTAssertNil(Terminals.buttonHint(launch(LaunchPrefs(agent: "codex"))), "a missing agent hides it")
    }

    // The Update button runs `agent-usage update` in the chosen terminal.
    func testUpdateCommand() {
        let update = ["\(Self.home)/.local/bin/agent-usage", "update", "--pause"]
        let ghostty = Terminals.terminalLaunch(LaunchPrefs(terminal: "ghostty"), command: update, on: machine())
        XCTAssertEqual(ghostty.map(\.argv), .success(["/usr/bin/open", "-na", "/Applications/Ghostty.app", "--args", "-e"]
                + inShell("'/Users/me/.local/bin/agent-usage' 'update' '--pause'")))
        XCTAssertEqual(Terminals.terminalLaunch(LaunchPrefs(), command: update, on: machine()).map(\.script),
                       .success("#!/bin/sh\nexec '/Users/me/.local/bin/agent-usage' 'update' '--pause'\n"))
        XCTAssertEqual(Terminals.terminalLaunch(LaunchPrefs(terminal: "kitty"), command: update, on: machine()).map(\.argv),
                       .failure(LaunchError(message: "Kitty isn't installed.", reason: .terminal, agentName: "")))
    }

    func testInstalledAndDisplay() {
        XCTAssertEqual(Terminals.installedTerminals(on: machine(apps: ["Ghostty.app", "Terminal.app"])).map(\.name), ["Terminal", "Ghostty"],
                       "installed terminals, in list order")
        XCTAssertEqual(Terminals.displayCommand(["/usr/bin/open", "--title=Agent usage", "-e", "\(Self.home)/.local/bin/opencode"], home: Self.home),
                       "/usr/bin/open '--title=Agent usage' -e ~/.local/bin/opencode", "display command shortens home and quotes spaces")
    }

    func testShellWords() throws {
        XCTAssertEqual(try ShellWords.split(#"a 'b c' "d \"e\" \n" f\ g ''"#), ["a", "b c", #"d "e" \n"#, "f g", ""])
        XCTAssertEqual(try ShellWords.split("  one\ttwo  # a comment\nthree"), ["one", "two", "three"])
        XCTAssertEqual(try ShellWords.split("x#y"), ["x#y"], "# inside a word is no comment")
        XCTAssertThrowsError(try ShellWords.split(#"claude "--x"#))
        XCTAssertThrowsError(try ShellWords.split("it's"))
        XCTAssertThrowsError(try ShellWords.split("trailing\\"))
        XCTAssertEqual(ShellWords.quote("it's"), #"'it'\''s'"#)
    }

    func testPrograms() {
        let dirs = Programs.searchDirs(path: "/usr/bin:/bin:/usr/bin::/opt/homebrew/bin", home: Self.home)
        XCTAssertEqual(Array(dirs.prefix(4)), ["/usr/bin", "/bin", "/opt/homebrew/bin", "/usr/local/bin"], "PATH first, without repeats, then Homebrew")
        XCTAssertTrue(dirs.contains("\(Self.home)/.opencode/bin"))
        XCTAssertEqual(Programs.find("~/bin/tool", in: [], home: Self.home) { $0 == "/Users/me/bin/tool" }, "/Users/me/bin/tool", "~/ expands")
        XCTAssertEqual(Programs.find("tool", in: ["/a", "/b"], home: Self.home) { $0 == "/b/tool" }, "/b/tool")

        // The real lookup on this machine.
        let real = Programs.searchDirs(path: ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin", home: Self.home)
        XCTAssertNotNil(Programs.find("sh", in: real, home: Self.home), "finds sh on the real PATH")
        XCTAssertNil(Programs.find("/usr", in: real, home: Self.home), "a folder isn't a program")
        XCTAssertNil(Programs.find("surely-not-a-program", in: real, home: Self.home))
        XCTAssertEqual(Machine.local(environment: ["HOME": "/Users/x"]).shell, "/bin/zsh", "zsh, macOS's default, without SHELL")
    }
}
