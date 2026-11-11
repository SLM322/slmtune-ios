import Foundation
import Libbox
import NetworkExtension
import os

/// The VPN itself: sing-box (libbox) running inside the Network Extension process.
/// Lifecycle modelled on sing-box for Apple's ExtensionProvider (GPL-3.0).
///
/// The config is built here from the App Group settings, not passed in by the app: Connect On Demand
/// starts the tunnel without the app, and a reload after a settings change needs the same path.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "com.slmtune.ios", category: "tunnel")
    private var commandServer: LibboxCommandServer?
    private var platform: ExtensionPlatformInterface?
    private let backends = Backends()

    override func startTunnel(options: [String: NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        do {
            try? FileManager.default.removeItem(at: AppGroup.lastErrorFile)
            SharedLog.trim()
            // The last run died inside a Go core: don't run it again, hand its last words to the app.
            if let report = CrashCapture.takePrevious() {
                holdForReport(report, completionHandler)
                return
            }
            CrashCapture.redirectStderr()
            let stored = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
            if !AppGroup.isShared {
                AppGroup.secretOverride = stored?["secret"] as? String
                fetchListsIfMissing()
            }
            SharedLog.append("tunnel", "start: App Group \(AppGroup.isShared ? "shared" : "not shared (settings from the VPN profile)")")
            try setupLibbox()
            let config = try buildConfig()
            let platform = ExtensionPlatformInterface(self)
            self.platform = platform
            var error: NSError?
            guard let server = LibboxNewCommandServer(self, platform, &error) else {
                throw error ?? fail("libbox: command server")
            }
            try server.start()
            commandServer = server
            try server.startOrReloadService(config, options: LibboxOverrideOptions())
            completionHandler(nil)
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            SharedLog.append("error", error.localizedDescription)
            try? Data(error.localizedDescription.utf8).write(to: AppGroup.lastErrorFile, options: .atomic)
            stopLibbox()
            completionHandler(error)
        }
    }

    /// A crash report from the previous run, kept while the app fetches it ("crash" message).
    private var crashReport: String?

    /// "Connects" with settings that route nothing, so the app can ask for the report; gives up after a minute.
    private func holdForReport(_ report: String, _ completionHandler: @escaping (Error?) -> Void) {
        crashReport = report
        for line in report.split(separator: "\n").prefix(200) { SharedLog.append("crash", String(line)) }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        setTunnelNetworkSettings(settings) { [weak self] _ in
            completionHandler(nil)
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                if self?.crashReport != nil { self?.cancelTunnelWithError(self?.fail(L("Ядро аварийно завершилось при прошлом запуске."))) }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopLibbox()
        completionHandler()
    }

    /// Settings sent by the app when there is no shared App Group (see loadSettings).
    private var sentSettings: AppSettings?

    /// Messages from the app: "reload" (settings changed; without a shared App Group the settings JSON itself).
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        if messageData.first == UInt8(ascii: "{"), let s = SettingsFile.decode(messageData) {
            sentSettings = s
            do { try reload(); completionHandler?(Data("ok".utf8)) }
            catch { completionHandler?(Data(error.localizedDescription.utf8)) }
            return
        }
        switch String(decoding: messageData, as: UTF8.self) {
        case "reload":
            do { try reload(); completionHandler?(Data("ok".utf8)) }
            catch { completionHandler?(Data(error.localizedDescription.utf8)) }
        case "crash":
            completionHandler?(Data((crashReport ?? "").utf8))
        case "log":
            // Журнал without a shared App Group: "source\ttext" lines.
            let text = SharedLog.tail(maxBytes: 60_000).map { "\($0.source)\t\($0.text)" }.joined(separator: "\n")
            completionHandler?(Data(text.utf8))
        case "clear-log":
            SharedLog.clear()
            completionHandler?(Data("ok".utf8))
        default:
            completionHandler?(nil)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        commandServer?.pause()
        backends.sleep()
        completionHandler()
    }

    override func wake() {
        commandServer?.wake()
        backends.wake()
    }

    // MARK: - libbox

    private static var setupDone = false

    private func setupLibbox() throws {
        guard !Self.setupDone else { return }
        let o = LibboxSetupOptions()
        o.basePath = AppGroup.container.path
        o.workingPath = AppGroup.workingDir.path
        o.tempPath = AppGroup.tempDir.path
        o.logMaxLines = 2000
        // iOS kills a Network Extension above ~50 MB: keep Go's heap under the limit (GC tuned by libbox).
        o.oomKillerEnabled = true
        o.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        o.appMarketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var error: NSError?
        LibboxSetup(o, &error)
        if let error { throw error }
        Self.setupDone = true
    }

    /// The App Group file normally; without a shared group (re-signed with a profile that lacks it) the copy the app
    /// keeps in the VPN profile's providerConfiguration, or the newer one it sent with the last reload.
    private func loadSettings() -> AppSettings {
        if AppGroup.isShared { return SettingsFile.load() }
        if let s = sentSettings { return s }
        let stored = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["settings"] as? Data
        return SettingsFile.decode(stored) ?? SettingsFile.load()
    }

    /// Without a shared App Group the lists the app downloaded are out of reach: the extension gets its own.
    /// Waits a few seconds on the first start (the preset needs them), then finishes in the background.
    private func fetchListsIfMissing() {
        let s = loadSettings()
        let missing = Lists.presetLists(s.preset).contains { !Lists.has(Lists.ruleFile($0)) }
        let done = DispatchSemaphore(value: 0)
        Task.detached { [weak self] in
            let n = await Lists.update(s)
            done.signal()
            if n > 0 { try? self?.reload() } // no-op until sing-box runs: the first config is built after the wait
        }
        if missing { _ = done.wait(timeout: .now() + 8) }
    }

    private func buildConfig() throws -> String {
        let s = loadSettings()
        guard let server = s.activeServer else { throw fail(L("Нет сервера: добавьте его в приложении.")) }
        // Extra cores first (Xray, mihomo, TrustTunnel, Tor): sing-box points at their SOCKS ports.
        let ports = try backends.start(s, server)
        let config = try ConfigBuilder.build(s, server: server, backends: ports)
        // Kept for "Показать конфиг" in the app (passwords included — the App Group is private to the app).
        try? Data(config.utf8).write(to: AppGroup.lastConfigFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return config
    }

    private func reload() throws {
        guard let server = commandServer else { return }
        try server.startOrReloadService(try buildConfig(), options: LibboxOverrideOptions())
    }

    private func stopLibbox() {
        try? commandServer?.closeService()
        commandServer?.close()
        commandServer = nil
        platform?.reset()
        platform = nil
        backends.stop()
    }

    func fail(_ message: String) -> NSError {
        NSError(domain: "SLMtune", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - LibboxCommandServerHandler

extension PacketTunnelProvider: LibboxCommandServerHandlerProtocol {
    func serviceStop() throws {
        cancelTunnelWithError(nil)
    }

    func serviceReload() throws {
        try reload()
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let st = LibboxSystemProxyStatus()
        st.available = false
        st.enabled = false
        return st
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws {}

    func triggerNativeCrash() throws {}

    func writeDebugMessage(_ message: String?) {
        if let message { log.debug("\(message, privacy: .public)") }
    }

    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw fail("not supported")
    }
}
