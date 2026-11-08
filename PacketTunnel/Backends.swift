import Foundation
import Libbox
import os
#if canImport(VpnClientFramework)
import VpnClientFramework
#endif
#if canImport(CTor)
import CTor
import TorCore
#endif

/// Starts the extra cores in this process before sing-box and stops them after (see Shared/Engines.swift).
/// Each listens on 127.0.0.1; the returned map (server id → port) goes into ConfigBuilder.build.
final class Backends {
    private let log = Logger(subsystem: "com.slmtune.ios", category: "cores")
    private var started: [String: Int] = [:]
    private var signature = ""
    #if canImport(VpnClientFramework)
    private var tt: [String: TTSocksClient] = [:]
    #endif

    /// Starts what the connection needs; a reload with the same servers keeps the running cores.
    func start(_ settings: AppSettings, _ server: Server) throws -> [String: Int] {
        let list = Engines.backends(settings, server)
        let sig = list.map { "\($0.id)|\($0.link)|\($0.params.sorted { $0.key < $1.key })" }.joined(separator: ";")
        if sig == signature { return started }
        stop()
        guard !list.isEmpty else { return [:] }
        SlmcoreSetLogWriter(CoreLog.shared)

        var ports: [String: Int] = [:]
        var mihomo: [(server: Server, port: Int)] = []
        for s in list {
            let port = try freePort()
            switch Engines.engine(s) {
            case .xray:
                var error: NSError?
                SlmcoreStartXray(s.id, Engines.xrayConfig(s, port: port, logLevel: settings.logLevel), &error)
                if let error { throw wrap("Xray", s, error) }
            case .mihomo:
                mihomo.append((s, port))
            case .trusttunnel:
                try startTrustTunnel(s, port: port)
            case .tor:
                try startTor(s, port: port)
            case nil:
                continue
            }
            ports[s.id] = port
        }
        if !mihomo.isEmpty {
            let home = AppGroup.workingDir.appendingPathComponent("mihomo", isDirectory: true)
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            var error: NSError?
            SlmcoreStartMihomo(home.path, Engines.mihomoConfig(mihomo, logLevel: settings.logLevel), &error)
            if let error { throw wrap("mihomo", mihomo[0].server, error) }
        }
        started = ports
        signature = sig
        return ports
    }

    func stop() {
        SlmcoreStopAllXray()
        SlmcoreStopMihomo()
        #if canImport(VpnClientFramework)
        for c in tt.values { c.stop() }
        tt = [:]
        #endif
        // Tor can run only once per process and stops with the extension; its transports stay up with it.
        started = [:]
        signature = ""
    }

    func sleep() {
        #if canImport(VpnClientFramework)
        for c in tt.values { c.notifySleep() }
        #endif
    }

    func wake() {
        #if canImport(VpnClientFramework)
        for c in tt.values { c.notifyWake() }
        #endif
    }

    private func freePort() throws -> Int {
        var port: Int32 = 0
        var error: NSError?
        SlmcoreFreePort(&port, &error)
        if let error { throw error }
        return Int(port)
    }

    private func wrap(_ core: String, _ s: Server, _ e: Error) -> NSError {
        NSError(domain: "SLMtune", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(core) · \(s.title): \(e.localizedDescription)"])
    }

    private func fail(_ m: String) -> NSError {
        NSError(domain: "SLMtune", code: 3, userInfo: [NSLocalizedDescriptionKey: m])
    }

    // MARK: TrustTunnel

    private func startTrustTunnel(_ s: Server, port: Int) throws {
        #if canImport(VpnClientFramework)
        let connected = DispatchSemaphore(value: 0)
        var lastState = -1
        guard let client = TTSocksClient(config: Engines.ttConfig(s, port: port), stateHandler: { state in
            lastState = Int(state)
            // VPN_SS_CONNECTED = 2 in vpn/vpn.h (DISCONNECTED 0, CONNECTING 1, CONNECTED 2, …).
            if state == 2 { connected.signal() }
        }) else { throw fail(L("TrustTunnel: конфигурация не принята.")) }
        guard client.start() else { throw fail(L("TrustTunnel: не удалось подключиться к %@.", s.server)) }
        tt[s.id] = client
        if connected.wait(timeout: .now() + 20) == .timedOut {
            log.warning("TrustTunnel: not connected after 20 s (state \(lastState))")
        }
        #else
        throw fail(L("TrustTunnel не входит в эту сборку: соберите scripts/build-trusttunnel.sh."))
        #endif
    }

    // MARK: Tor

    #if canImport(CTor)
    private static var torSocksPort = 0
    private static var torThread: TorThread?
    #endif

    private func startTor(_ s: Server, port: Int) throws {
        #if canImport(CTor)
        // Only one tor per process: a second Tor server (or a reload) reuses the running one.
        if Self.torThread != nil {
            CoreLog.shared.writeLog("tor: already running on \(Self.torSocksPort)")
            return
        }
        let bridges = try Engines.torBridges(s)
        var transportPorts: [String: Int] = [:]
        let ptDir = AppGroup.workingDir.appendingPathComponent("pt").path
        for name in Set(bridges.map(Engines.bridgeTransport).filter { !$0.isEmpty }) {
            var p: Int32 = 0
            var error: NSError?
            SlmcoreStartTransport(name, ptDir, &p, &error)
            if let error { throw wrap("Tor/\(name)", s, error) }
            transportPorts[name] = Int(p)
        }
        let data = AppGroup.workingDir.appendingPathComponent("tor", isDirectory: true)
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let control = data.appendingPathComponent("control")
        try? FileManager.default.removeItem(at: control)
        var args = Engines.torArguments(socksPort: port, dataDir: data.path, logFile: SharedLog.torLogFile.path,
                                        bridges: bridges, transportPorts: transportPorts)
        args += ["--ControlSocket", control.path, "--CookieAuthentication", "1"]
        let thread = TorThread(arguments: args) // argv[0] "tor" is added by TorThread
        thread.start()
        Self.torThread = thread
        Self.torSocksPort = port
        waitForCircuit(control: control, cookie: data.appendingPathComponent("control_auth_cookie"))
        #else
        throw fail(L("Tor не входит в эту сборку: добавьте пакет Tor.framework (см. README)."))
        #endif
    }

    #if canImport(CTor)
    /// Holds the start until Tor has a circuit (up to 2 minutes): otherwise the first pages would just fail.
    private func waitForCircuit(control: URL, cookie: URL) {
        let deadline = Date().addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: control.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        let controller = TorController(socketURL: control)
        guard (try? controller.connect()) != nil, let cookieData = try? Data(contentsOf: cookie) else { return }
        let done = DispatchSemaphore(value: 0)
        var token: Any?
        controller.authenticate(with: cookieData) { ok, _ in
            guard ok else { done.signal(); return }
            token = controller.addObserver(forCircuitEstablished: { established in
                if established { done.signal() }
            })
            _ = controller.addObserver(forStatusEvents: { _, _, action, args in
                if action == "BOOTSTRAP", let p = args?["PROGRESS"] { CoreLog.shared.writeLog("tor: \(p)% \(args?["SUMMARY"] ?? "")") }
                return false
            })
        }
        _ = done.wait(timeout: .now() + max(1, deadline.timeIntervalSinceNow))
        controller.removeObserver(token)
    }
    #endif
}

/// The cores' log lines go to the shared log file the app shows (Журнал).
final class CoreLog: NSObject, SlmcoreLogWriterProtocol {
    static let shared = CoreLog()
    func writeLog(_ line: String?) {
        guard let line else { return }
        SharedLog.append("core", line)
    }
}
