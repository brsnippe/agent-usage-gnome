import Foundation
#if canImport(Glibc)
import Glibc
#endif

// Runs the collectors and keeps their records: the macOS counterpart of
// bin/agent-usage-update, which needs bash 4 and jq (a Mac has bash 3.2).

public struct Collector: Equatable {
    public var agent: String
    public var path: String
}

public struct CollectorOutcome: Equatable {
    public var agent: String
    /// Why the record wasn't updated, or nil when it was.
    public var failure: String?
}

public enum Collectors {
    /// Pythons that run the collectors, best first. `/usr/bin/python3` isn't
    /// one: without Apple's Command Line Tools it opens an "install the
    /// tools?" dialog instead of running, and this runs every few minutes.
    public static let pythonCandidates = [
        "/Library/Developer/CommandLineTools/usr/bin/python3",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
    ]

    public static func findPython(candidates: [String] = pythonCandidates, isProgram: (String) -> Bool = Programs.isProgram) -> String? {
        candidates.first(where: isProgram)
    }

    /// Where the records go: `~/.local/state/omarchy/agents/usage`. It keeps
    /// Omarchy's name, as on Linux, so the collectors stay as they are.
    public static func usageDirectory(environment: [String: String], home: String) -> String {
        let state = environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.local/state"
        return "\(state)/omarchy/agents/usage"
    }

    /// The environment the collectors run in: this app's, with a PATH that
    /// finds `codex` and `rg` where Homebrew and the installers put them.
    public static func environment(base: [String: String], home: String) -> [String: String] {
        var environment = base
        environment["PATH"] = Programs.searchDirs(path: base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin", home: home).joined(separator: ":")
        return environment
    }

    /// Every executable `agent-usage-<agent>` in `dir`, except the updater.
    public static func find(in dir: String) -> [Collector] {
        let prefix = "agent-usage-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.sorted().compactMap { name in
            let agent = String(name.dropFirst(prefix.count))
            guard name.hasPrefix(prefix), !agent.isEmpty, agent != "update", Programs.isProgram("\(dir)/\(name)") else {
                return nil
            }
            return Collector(agent: agent, path: "\(dir)/\(name)")
        }
    }

    public static func wanted(_ collectors: [Collector], agents: [String]) -> [Collector] {
        agents.isEmpty ? collectors : collectors.filter { agents.contains($0.agent) }
    }

    /// Runs the request's collectors side by side, each through `interpreter`,
    /// and writes each one's record to `<usageDir>/<agent>.json` in a single
    /// step, so the panel never reads half a file. Blocks until all are done.
    public static func run(
        _ request: UpdateRequest,
        collectors: [Collector],
        interpreter: String,
        environment: [String: String],
        usageDir: String,
        timeout: TimeInterval = 120,
        log: FileHandle? = nil
    ) -> [CollectorOutcome] {
        try? FileManager.default.createDirectory(atPath: usageDir, withIntermediateDirectories: true)
        let chosen = wanted(collectors, agents: request.agents)
        var outcomes = [CollectorOutcome?](repeating: nil, count: chosen.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: chosen.count) { index in
            let outcome = runOne(chosen[index], flags: request.kind.flags, interpreter: interpreter,
                                 environment: environment, usageDir: usageDir, timeout: timeout, log: log)
            lock.lock()
            outcomes[index] = outcome
            lock.unlock()
        }
        return outcomes.compactMap { $0 }
    }

    static func runOne(
        _ collector: Collector, flags: [String], interpreter: String, environment: [String: String],
        usageDir: String, timeout: TimeInterval, log: FileHandle?
    ) -> CollectorOutcome {
        let failed = { (reason: String) in CollectorOutcome(agent: collector.agent, failure: reason) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: interpreter)
        process.arguments = [collector.path] + flags
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: usageDir)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = log ?? FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        #if os(macOS)
        // Background work: the Mac runs it on its efficiency cores, out of
        // the way of what you're doing.
        process.qualityOfService = .utility
        #endif
        do {
            try process.run()
        } catch {
            return failed("couldn't start \(interpreter): \(error.localizedDescription)")
        }

        var timedOut = false
        let pid = process.processIdentifier
        let stop = DispatchWorkItem {
            guard process.isRunning else {
                return
            }
            timedOut = true
            process.terminate()
            // One that ignores the polite request gets the other kind.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()

        if timedOut {
            return failed("took longer than \(Int(timeout)) s and was stopped")
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            return failed("exited with status \(process.terminationStatus)")
        }
        guard let record = record(from: data) else {
            return failed("printed no record")
        }
        let target = "\(usageDir)/\(collector.agent).json"
        let temporary = "\(usageDir)/.\(collector.agent).\(UUID().uuidString)"
        do {
            try record.write(to: URL(fileURLWithPath: temporary))
        } catch {
            return failed("couldn't write its record: \(error.localizedDescription)")
        }
        guard rename(temporary, target) == 0 else {
            try? FileManager.default.removeItem(atPath: temporary)
            return failed("couldn't write its record")
        }
        return CollectorOutcome(agent: collector.agent, failure: nil)
    }

    /// A collector's output as a record file: one JSON object, then a newline.
    static func record(from output: Data) -> Data? {
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data), value.objectValue != nil else {
            return nil
        }
        return Data((text + "\n").utf8)
    }
}

public enum Records {
    /// The records in the usage folder, by file name. A record mid-write or
    /// malformed is skipped until the next change.
    public static func load(from dir: String) -> [AgentRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .sorted()
            .compactMap { name in
                FileManager.default.contents(atPath: "\(dir)/\(name)").flatMap(AgentRecord.init(data:))
            }
    }
}
