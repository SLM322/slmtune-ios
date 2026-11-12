import Foundation
import os

/// What the extension left behind when it died. A Go panic, an exit or a memory kill takes the whole process
/// (iOS then reports only "NEAgentErrorDomain 1"), so two things are kept on disk and picked up by the next
/// start, which shows them to the app instead of connecting (see PacketTunnelProvider.startTunnel):
///  - stderr.log / libbox's CrashReport-*.log — the Go cores' last words;
///  - stage.log — how far the start got, with the memory left at each step.
enum CrashCapture {
    private static var stderrFile: URL { AppGroup.workingDir.appendingPathComponent("stderr.log") }
    private static var stageFile: URL { AppGroup.workingDir.appendingPathComponent("stage.log") }
    private static let lock = NSLock()
    private static var ticker: DispatchSourceTimer?

    /// Everything Go prints before libbox installs its own crash output goes to stderr: keep it in a file.
    static func redirectStderr() {
        freopen(stderrFile.path, "w", stderr)
        setvbuf(stderr, nil, _IONBF, 0)
    }

    /// One line per step of the start, written at once (the process may die on the next line).
    static func stage(_ name: String) {
        let free = os_proc_available_memory() / 1_048_576
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let data = Data("\(f.string(from: Date())) \(name) · свободно \(free) МБ\n".utf8)
        lock.lock()
        defer { lock.unlock() }
        if let h = try? FileHandle(forWritingTo: stageFile) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: stageFile)
        }
    }

    /// The tunnel is up: note the memory every 5 s for the first minute (a kill for memory shows as a falling number).
    static func running() {
        stage("running")
        let started = Date()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler {
            let done = Date().timeIntervalSince(started) >= 58
            stage(done ? "stable" : "alive")
            if done { t.cancel() }
        }
        t.resume()
        ticker = t
    }

    /// The steps of the current run so far.
    static func stagesNow() -> String {
        lock.lock()
        defer { lock.unlock() }
        return ((try? String(contentsOf: stageFile, encoding: .utf8)) ?? "(нет)").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A normal end (stopped, or the start failed with an error the app is told about): nothing to report next time.
    static func finish() {
        ticker?.cancel()
        ticker = nil
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: stageFile)
    }

    /// What the previous run left, if it died: a panic text, or a start that never reached a stable tunnel.
    /// Removes the files.
    static func takePrevious() -> String? {
        let fm = FileManager.default
        let dir = AppGroup.workingDir
        var text = ""
        for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        where name == "stderr.log" || (name.hasPrefix("CrashReport") && !name.hasSuffix(".old")) {
            let url = dir.appendingPathComponent(name)
            if let d = try? Data(contentsOf: url), !d.isEmpty {
                text += String(decoding: d.prefix(16_000), as: UTF8.self) + "\n"
            }
            try? fm.removeItem(at: url)
        }
        let stages = ((try? String(contentsOf: stageFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        try? fm.removeItem(at: stageFile)

        // Ordinary warnings on stderr are not a crash.
        let marks = ["panic:", "fatal error:", "goroutine ", "SIGSEGV", "SIGBUS", "SIGABRT", "runtime."]
        let crashed = marks.contains(where: text.contains)
        // Died during the start or in the first minute; later than that the system may simply have stopped us.
        let unfinished = !stages.isEmpty && !stages.contains(" stable ")
        guard crashed || unfinished else { return nil }
        var report = ""
        if !stages.isEmpty { report += "Этапы запуска:\n" + stages + "\n" }
        if !text.isEmpty { report += "\nstderr:\n" + text }
        return report.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
