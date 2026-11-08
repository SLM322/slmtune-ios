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

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopLibbox()
        completionHandler()
    }

    /// Messages from the app: "reload" (settings changed), "error" (last start error).
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        switch String(decoding: messageData, as: UTF8.self) {
        case "reload":
            do { try reload(); completionHandler?(Data("ok".utf8)) }
            catch { completionHandler?(Data(error.localizedDescription.utf8)) }
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
        o.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        o.appMarketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var error: NSError?
        LibboxSetup(o, &error)
        if let error { throw error }
        Self.setupDone = true
    }

    private func buildConfig() throws -> String {
        let s = SettingsFile.load()
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
