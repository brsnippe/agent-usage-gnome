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
    /// A session started waiting for you, or finished its turn: the robot's
    /// pop and sound.
    var onSessionAlert: ((TopBarSession) -> Void)?
    var onOpenSettings: (() -> Void)?

    private(set) var providers: [AgentRecord] = []
    /// What the agent sessions want, for the robot's colour.
    private(set) var session: TopBarSession?
    private var records: [AgentRecord] = []
    private var queue = UpdateQueue()
    private let home: String
    private let usageDir: String
    private let sessionsDir: String
    private let sessionHooks: String?
    private let collectors: [Collector]
    private let python: String?
    private let environment: [String: String]
    /// Utility priority: background work, which the Mac puts on its efficiency
    /// cores and out of the way of what you're doing.
    private let worker = DispatchQueue(label: "agent-usage.collectors", qos: .utility)
    private var watcher: DispatchSourceFileSystemObject?
    private var sessionsWatcher: DispatchSourceFileSystemObject?
    private var reloadScheduled = false
    private var sessionsReloadScheduled = false
    private var sessionsTimer: Timer?
    /// What the sessions were doing at the last look, and when the robot last
    /// popped or sounded (Sessions.alert).
    private var alertMarks: [String: String]?
    private var lastAlert: Double = 0
    private var appliedSessionColors = true
    private var timers: [Timer] = []
    private var retryTimer: Timer?
    private var releaseTimer: Timer?
    private var lastReleaseCheck: Date?
    private var signInTimer: Timer?
    private var signInChecksLeft = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var appliedSettings: [String] = []
    private var appliedSessionThreshold = 0
    /// GNOME switches extensions off while the screen is locked; here the
    /// timers just don't check then.
    private var locked = false

    static let retrySeconds: TimeInterval = 30
    /// After waking from sleep, give the network a moment before checking.
    static let wakeDelaySeconds: TimeInterval = 5
    /// New releases: every hour, starting a minute after launch, and after
    /// waking or unlocking unless the last check was recent. The hourly timer
    /// doesn't run while the Mac sleeps.
    static let releaseCheckSeconds: TimeInterval = 3600
    static let firstReleaseCheckSeconds: TimeInterval = 60
    static let wakeReleaseCheckSeconds: TimeInterval = 15 * 60
    /// After a sign-in button: check that agent's limits this often, this
    /// many times, until the problem is gone.
    static let signInCheckSeconds: TimeInterval = 15
    static let signInChecks = 20
    /// While there are session files: look again this often, since an agent
    /// that goes away doesn't change any file.
    static let sessionsCheckSeconds: TimeInterval = 30

    init() {
        let base = ProcessInfo.processInfo.environment
        home = base["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        usageDir = Collectors.usageDirectory(environment: base, home: home)
        sessionsDir = Sessions.directory(environment: base, home: home)
        sessionHooks = Bundle.main.resourceURL?.appendingPathComponent("hooks/agent-usage-session").path
        collectors = Collectors.find(in: Bundle.main.resourceURL?.appendingPathComponent("bin").path ?? "")
        python = Collectors.findPython()
        environment = Collectors.environment(base: base, home: home)

        panel.state.pythonMissing = python == nil
        panel.actions = PanelActions(
            refresh: { [weak self] in self?.runUpdate(.force) },
            openAgent: { [weak self] in self?.launchAgent() },
            openSettings: { [weak self] in self?.onOpenSettings?() },
            // Easy to undo on a Mac: it starts again at login, or from Spotlight.
            quit: { NSApp.terminate(nil) },
            select: { [weak self] in self?.select($0) },
            footer: { [weak self] in self?.onOpenSettings?() },
            signIn: { [weak self] in self?.signIn($0, $1) },
            signInHint: { [weak self] in self?.signInHint($0) ?? "" }
        )
        Log.write("started \(AppInfo.version): python \(python ?? "missing"), collectors \(collectors.map(\.agent)), records in \(usageDir)")
    }

    func start() {
        try? FileManager.default.createDirectory(atPath: usageDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        reload()
        loadSessions()
        watcher = watch(usageDir) { [weak self] in self?.scheduleReload() }
        sessionsWatcher = watch(sessionsDir) { [weak self] in self?.scheduleSessions() }
        observeSystem()
        appliedSettings = settingsKey
        appliedSessionThreshold = UserDefaults.standard.integer(forKey: Settings.sessionThreshold)
        appliedSessionColors = UserDefaults.standard.bool(forKey: Settings.sessionColors)
        // Every start, so an agent installed since gets its hooks too.
        applySessionHooks()
        runUpdate(.normal)
        restartTimers()
        restartReleaseChecks()
    }

    // ------------------------------------------------------------ data

    private func watch(_ dir: String, _ handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let descriptor = open(dir, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
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

    /// The timers' updates, which wait while the screen is locked.
    private func runScheduled(_ kind: UpdateKind, agents: [String] = []) {
        if !locked {
            runUpdate(kind, agents: agents)
        }
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

    // ------------------------------------------------------------ sessions

    /// A hook writes its file through a temporary one; look once.
    private func scheduleSessions() {
        guard !sessionsReloadScheduled else {
            return
        }
        sessionsReloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.sessionsReloadScheduled = false
            self?.loadSessions()
        }
    }

    private func loadSessions() {
        let colors = UserDefaults.standard.bool(forKey: Settings.sessionColors)
        let records = colors ? Sessions.load(from: sessionsDir) : []
        let seen = Sessions.parseSeen(try? String(contentsOfFile: "\(sessionsDir)/\(Sessions.seenFile)", encoding: .utf8))
        let now = Date().timeIntervalSince1970 * 1000
        let next = Sessions.topBar(records, now: now, seen: seen, alive: Sessions.processRunning)
        sessionsTimer?.invalidate()
        sessionsTimer = nil
        if !records.isEmpty {
            sessionsTimer = Timer.lenient(Self.sessionsCheckSeconds, repeats: false) { [weak self] in
                self?.loadSessions()
            }
        }
        if next != session {
            session = next
            onRecordsChange?()
        }
        // After the colour, so the robot pops in its new one. With the colours
        // off there are no sessions to follow; switched back on, the first
        // look is quiet again.
        if colors {
            alertSessions(records, now: now, seen: seen)
        } else {
            alertMarks = nil
        }
    }

    /// The pop and the sound, when a session starts waiting for you or
    /// finishes its turn. Quiet while the screen is locked, as on GNOME,
    /// which switches extensions off then.
    private func alertSessions(_ records: [JSONValue], now: Double, seen: Double) {
        let result = Sessions.alert(records, now: now, seen: seen, alive: Sessions.processRunning, marks: alertMarks, lastAlert: lastAlert)
        alertMarks = result.marks
        guard let alert = result.alert, !locked else {
            return
        }
        lastAlert = now
        Log.write("session alert: \(alert.rawValue)")
        onSessionAlert?(alert)
    }

    /// You looked: the turns that finished so far stop turning the robot green.
    private func acknowledgeSessions() {
        let now = String(Int64(Date().timeIntervalSince1970 * 1000))
        try? now.write(toFile: "\(sessionsDir)/\(Sessions.seenFile)", atomically: true, encoding: .utf8)
        loadSessions()
    }

    /// The hooks in Claude Code and the plugin in OpenCode follow the setting.
    private func applySessionHooks() {
        guard let python, let script = sessionHooks, FileManager.default.fileExists(atPath: script) else {
            return
        }
        let action = UserDefaults.standard.bool(forKey: Settings.sessionColors) ? "install" : "uninstall"
        let environment = self.environment
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script, action, "--quiet"]
            process.environment = environment
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            do {
                try process.run()
                let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    DispatchQueue.main.async { Log.write("session hooks: \(message)") }
                }
            } catch {
                DispatchQueue.main.async { Log.write("session hooks: \(error.localizedDescription)") }
            }
        }
    }

    /// A collector that couldn't reach its limits endpoint at all (typically
    /// right after login, before the network is up) asks to be rerun sooner.
    private func scheduleRetry() {
        let agents = Panel.retryAgents(records)
        guard !agents.isEmpty, retryTimer == nil else {
            return
        }
        retryTimer = Timer.lenient(Self.retrySeconds, repeats: false) { [weak self] in
            self?.retryTimer = nil
            self?.runScheduled(.limits, agents: agents)
        }
    }

    /// Two cadences: the cheap limits check keeps the menu bar percentage
    /// live, and the slower full pass rescans transcripts for the token charts.
    private func restartTimers() {
        timers.forEach { $0.invalidate() }
        let defaults = UserDefaults.standard
        let limits = max(30, defaults.integer(forKey: Settings.limitsInterval))
        let scan = 60 * max(5, defaults.integer(forKey: Settings.scanInterval))
        timers = [
            Timer.lenient(TimeInterval(limits), repeats: true) { [weak self] in self?.runScheduled(.limits) },
            Timer.lenient(TimeInterval(scan), repeats: true) { [weak self] in self?.runScheduled(.normal) },
        ]
    }

    // ------------------------------------------------------------ system

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.woke() }
        // Undocumented, but what every Mac app that cares uses.
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.locked = false
            self?.runUpdate(.normal)
            self?.checkForReleaseAfterWake()
        }
        observe(NotificationCenter.default, UserDefaults.didChangeNotification) { [weak self] in self?.settingsChanged() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        observers.append((center, token))
    }

    private func woke() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeDelaySeconds) { [weak self] in
            self?.runScheduled(.normal)
            self?.checkForReleaseAfterWake()
        }
    }

    // ------------------------------------------------------------ settings

    private var settingsKey: [String] {
        let defaults = UserDefaults.standard
        return [Settings.limitsInterval, Settings.scanInterval, Settings.checkUpdates].map { "\(defaults.object(forKey: $0) ?? "")" }
    }

    /// Changes apply right away, as in GNOME's settings.
    private func settingsChanged() {
        refreshLaunchHint()
        let sessionThreshold = UserDefaults.standard.integer(forKey: Settings.sessionThreshold)
        if sessionThreshold != appliedSessionThreshold {
            appliedSessionThreshold = sessionThreshold
            onRecordsChange?()
        }
        let sessionColors = UserDefaults.standard.bool(forKey: Settings.sessionColors)
        if sessionColors != appliedSessionColors {
            appliedSessionColors = sessionColors
            applySessionHooks()
            loadSessions()
        }
        let key = settingsKey
        guard key != appliedSettings else {
            return
        }
        appliedSettings = key
        restartTimers()
        restartReleaseChecks()
    }

    private func restartReleaseChecks() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        guard UserDefaults.standard.bool(forKey: Settings.checkUpdates), AppInfo.repository != nil else {
            panel.state.newRelease = nil
            return
        }
        releaseTimer = Timer.lenient(Self.firstReleaseCheckSeconds, repeats: false) { [weak self] in
            self?.checkForRelease()
            self?.releaseTimer = Timer.lenient(Self.releaseCheckSeconds, repeats: true) { [weak self] in
                self?.checkForRelease()
            }
        }
    }

    /// The wall clock, unlike the timers, counts the time spent asleep.
    private func checkForReleaseAfterWake() {
        guard releaseTimer != nil else {
            return
        }
        if let last = lastReleaseCheck, Date().timeIntervalSince(last) < Self.wakeReleaseCheckSeconds {
            return
        }
        checkForRelease()
    }

    private func checkForRelease() {
        lastReleaseCheck = Date()
        ReleaseChecker.latest { [weak self] result in
            switch result {
            case .success(let latest):
                self?.panel.state.newRelease = Versions.isNewer(latest, than: AppInfo.version) ? latest : nil
            case .failure(let error):
                Log.write("release check: \(error.message)")
            }
        }
    }

    // ------------------------------------------------------------ panel

    func panelOpened() {
        acknowledgeSessions()
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

    var machine: Machine {
        let home = self.home
        return Machine.local(findApp: { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path
                ?? Terminals.findAppInFolders(app, home: home)
        })
    }

    private func refreshLaunchHint() {
        let launch = Terminals.resolveLaunch(Settings.launchPrefs, on: machine)
        let hint = Terminals.buttonHint(launch)
        let opensApp = (try? launch.get())?.opensApp ?? false
        if panel.state.launchHint != hint || panel.state.launchOpensApp != opensApp {
            panel.state.launchHint = hint
            panel.state.launchOpensApp = opensApp
        }
    }

    func launchAgent() {
        // Going to your agent is looking at it.
        acknowledgeSessions()
        switch Terminals.resolveLaunch(Settings.launchPrefs, on: machine) {
        case .success(let launch):
            do {
                try Launcher.run(argv: launch.argv, script: launch.script, name: launch.agentName)
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

    // ------------------------------------------------------------ sign-in

    private func signInLaunch(_ action: SignInAction) -> Result<TerminalLaunch, LaunchError> {
        Terminals.commandLaunch(Settings.launchPrefs, command: action.command, pause: action.pause, on: machine)
    }

    func signInHint(_ action: SignInAction) -> String {
        switch signInLaunch(action) {
        case .success(let terminal): return "Runs \(action.command.joined(separator: " ")) in \(terminal.terminalName)"
        case .failure(let error): return error.message
        }
    }

    /// The problem card's buttons: a command-line tool in the chosen terminal.
    func signIn(_ id: String, _ action: SignInAction) {
        let name = action.command.joined(separator: " ")
        switch signInLaunch(action) {
        case .success(let terminal):
            do {
                try Launcher.run(argv: terminal.argv, script: terminal.script, name: name)
                followSignIn(id)
            } catch {
                show("Couldn't start \(name): \(error.localizedDescription)")
            }
        case .failure(let error):
            show(error.message)
        }
    }

    /// Signing in happens in a browser or another window; keep checking that
    /// agent's limits until the problem is gone, so the panel catches up on
    /// its own.
    private func followSignIn(_ id: String) {
        signInTimer?.invalidate()
        signInChecksLeft = Self.signInChecks
        signInTimer = Timer.lenient(Self.signInCheckSeconds, repeats: true) { [weak self] in
            self?.checkSignIn(id)
        }
    }

    private func checkSignIn(_ id: String) {
        let signedOut = records.first { $0.id == id }?.signInActions.isEmpty == false
        guard signInChecksLeft > 0, signedOut else {
            signInTimer?.invalidate()
            signInTimer = nil
            return
        }
        signInChecksLeft -= 1
        runUpdate(.limits, agents: [id])
    }
}

/// Timers with a tenth of their interval as tolerance, so macOS can fire them
/// together with other wake-ups and let the CPU sleep in between.
extension Timer {
    static func lenient(_ interval: TimeInterval, repeats: Bool, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in block() }
        timer.tolerance = interval / 10
        return timer
    }
}

/// Starts a launch, writing its `.command` script first for the terminals
/// that open one.
enum Launcher {
    static func run(argv: [String], script: String?, name: String) throws {
        var argv = argv
        if let script {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentUsage")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            // The file name is what the terminal window's title shows.
            let file = caches.appendingPathComponent("\(name).command")
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
