import Foundation

/// What the Go cores wrote when the extension died. A Go panic kills the whole process (iOS then reports only
/// "NEAgentErrorDomain 1"), so the text is kept on disk and picked up by the next start, which shows it to the
/// app instead of connecting (see PacketTunnelProvider.startTunnel).
enum CrashCapture {
    private static var stderrFile: URL { AppGroup.workingDir.appendingPathComponent("stderr.log") }

    /// Everything Go prints before libbox installs its own crash output goes to stderr: keep it in a file.
    static func redirectStderr() {
        freopen(stderrFile.path, "w", stderr)
        setvbuf(stderr, nil, _IONBF, 0)
    }

    /// The previous run's panic text, if it left one (libbox's CrashReport-*.log or our stderr.log). Removes the files.
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
        // Ordinary warnings on stderr are not a crash.
        let marks = ["panic:", "fatal error:", "goroutine ", "SIGSEGV", "SIGBUS", "SIGABRT", "runtime."]
        guard marks.contains(where: text.contains) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
