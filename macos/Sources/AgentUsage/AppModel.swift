import AgentUsageCore
import AppKit

/// The app's state: the records on disk, the collectors that refresh them,
/// and the panel's view of both. Everything here runs on the main thread;
/// only the collectors run on their own.
final class AppModel {
    let panel = PanelModel()
    /// The menu bar needs redrawing.
    var onRecordsChange: (() -> Void)?
    /// Something went wrong that the panel should show, even when it's closed.
    var onNotice: (() -> Void)?

    private(set) var providers: [AgentRecord] = []
    private var records: [AgentRecord] = []
    private var queue = UpdateQueue()
    private let home: String
    private let usageDir: String
    private let collectors: [Collector]
    private let python: String?
    private let environment: [String: String]
    private let worker = DispatchQueue(label: "agent-usage.collectors")
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadScheduled = false
    private var timers: [Timer] = []
    private var retryTimer: Timer?

    static let retrySeconds: TimeInterval = 30

    init() {
        let base = ProcessInfo.processInfo.environment
        home = base["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        usageDir = Collectors.usageDirectory(environment: base, home: home)
        collectors = Collectors.find(in: Bundle.main.resourceURL?.appendingPathComponent("bin").path ?? "")
        python = Collectors.findPython()
        environment = Collectors.environment(base: base, home: home)

        panel.state.pythonMissing = python == nil
        panel.actions = PanelActions(
            refresh: { [weak self] in self?.runUpdate(.force) },
            openAgent: { [weak self] in self?.launchAgent() },
            select: { [weak self] in self?.select($0) },
            footer: {}
        )
        Log.write("started: python \(python ?? "missing"), collectors \(collectors.map(\.agent)), records in \(usageDir)")
    }

    func start() {
        try? FileManager.default.createDirectory(atPath: usageDir, withIntermediateDirectories: true)
        reload()
        watch()
        runUpdate(.normal)
        restartTimers()
    }

    // ------------------------------------------------------------ data

    private func watch() {
        let descriptor = open(usageDir, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// One update writes several files in quick succession; reload once.
    private func scheduleReload() {
        guard !reloadScheduled else {
            return
        }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.reloadScheduled = false
            self?.reload()
        }
    }

    func reload() {
        let loaded = Records.load(from: usageDir)
        // Every check rewrites the records' timestamps, which only the footer
        // shows; the rest follows when something on screen changed.
        let changed = !Usage.sameDisplay(loaded, records)
        records = loaded
        providers = Usage.visibleProviders(records)
        panel.state.providers = providers
        if changed {
            panel.state.selectedID = Panel.selection(panel.state.selectedID, in: providers)
            refreshLaunchHint()
            onRecordsChange?()
        }
        scheduleRetry()
    }

    func runUpdate(_ kind: UpdateKind, agents: [String] = []) {
        guard python != nil else {
            return
        }
        if let request = queue.request(kind, agents: agents) {
            start(request)
        }
        panel.state.running = queue.running
    }

    private func start(_ request: UpdateRequest) {
        guard let python else {
            return
        }
        let (collectors, environment, usageDir) = (self.collectors, self.environment, self.usageDir)
        panel.state.running = request
        worker.async { [weak self] in
            let outcomes = Collectors.run(request, collectors: collectors, interpreter: python, environment: environment,
                                          usageDir: usageDir, log: Log.handle)
            DispatchQueue.main.async {
                self?.finished(outcomes)
            }
        }
    }

    private func finished(_ outcomes: [CollectorOutcome]) {
        for outcome in outcomes {
            if let failure = outcome.failure {
                Log.write("\(outcome.agent) collector \(failure)")
            }
        }
        let next = queue.finish()
        panel.state.running = next
        reload()
        if let next {
            start(next)
        }
    }

    /// A collector that couldn't reach its limits endpoint at all (typically
    /// right after login, before the network is up) asks to be rerun sooner.
    private func scheduleRetry() {
        let agents = Panel.retryAgents(records)
        guard !agents.isEmpty, retryTimer == nil else {
            return
        }
        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retrySeconds, repeats: false) { [weak self] _ in
            self?.retryTimer = nil
            self?.runUpdate(.limits, agents: agents)
        }
    }

    /// Two cadences: the cheap limits check keeps the menu bar percentage
    /// live, and the slower full pass rescans transcripts for the token charts.
    func restartTimers() {
        timers.forEach { $0.invalidate() }
        let defaults = UserDefaults.standard
        let limits = max(30, defaults.object(forKey: "limitsInterval") as? Int ?? 300)
        let scan = 60 * max(5, defaults.object(forKey: "scanInterval") as? Int ?? 15)
        timers = [
            Timer.scheduledTimer(withTimeInterval: TimeInterval(limits), repeats: true) { [weak self] _ in self?.runUpdate(.limits) },
            Timer.scheduledTimer(withTimeInterval: TimeInterval(scan), repeats: true) { [weak self] _ in self?.runUpdate(.normal) },
        ]
    }

    // ------------------------------------------------------------ panel

    func panelOpened() {
        // Opening wants the numbers that go stale on the wire, not another walk
        // over every transcript on disk.
        runUpdate(.limits)
        panel.state.now = Date()
        refreshLaunchHint()
    }

    func panelClosed() {
        panel.state.hoveredRow = nil
        panel.state.hoverText = nil
        panel.state.notice = nil
    }

    func tick() {
        panel.state.now = Date()
    }

    func select(_ id: String) {
        panel.state.selectedID = id
    }

    func step(_ delta: Int) {
        if providers.count > 1 {
            select(Panel.step(from: panel.state.selectedID, by: delta, in: providers))
        }
    }

    // ------------------------------------------------------------ agent

    var launchPrefs: LaunchPrefs {
        let defaults = UserDefaults.standard
        return LaunchPrefs(
            agent: defaults.string(forKey: "agent") ?? "opencode",
            agentCommand: defaults.string(forKey: "agentCommand") ?? "",
            terminal: defaults.string(forKey: "terminal") ?? "auto",
            terminalCommand: defaults.string(forKey: "terminalCommand") ?? ""
        )
    }

    var machine: Machine {
        let home = self.home
        return Machine.local(findApp: { terminal in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID)?.path
                ?? Terminals.findAppInFolders(terminal, home: home)
        })
    }

    private func refreshLaunchHint() {
        panel.state.launchHint = Terminals.buttonHint(Terminals.resolveLaunch(launchPrefs, on: machine))
    }

    func launchAgent() {
        switch Terminals.resolveLaunch(launchPrefs, on: machine) {
        case .success(let launch):
            do {
                try Launcher.run(launch)
            } catch {
                show("Couldn't open \(launch.agentName): \(error.localizedDescription)")
            }
        case .failure(let error):
            show(error.message)
        }
    }

    private func show(_ notice: String) {
        Log.write(notice)
        panel.state.notice = notice
        onNotice?()
    }
}

/// Starts a launch: writes its `.command` script first, for the terminals
/// that open one.
enum Launcher {
    static func run(_ launch: Launch) throws {
        var argv = launch.argv
        if let script = launch.script {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentUsage")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            // The file name is what the terminal window's title shows.
            let file = caches.appendingPathComponent("\(launch.agentName).command")
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            argv.append(file.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        try process.run()
    }
}

/// `~/Library/Logs/AgentUsage/agent-usage.log`, for `agent-usage diagnose`.
/// The collectors' own complaints go there too.
enum Log {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/AgentUsage/agent-usage.log")

    static let handle: FileHandle? = {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Start over once it passes a megabyte; the last run's lines are kept.
        if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000 {
            let previous = url.appendingPathExtension("1")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = handle?.seekToEndOfFile()
        return handle
    }()

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        handle?.write(Data("\(stamp) agent-usage: \(message)\n".utf8))
    }
}
