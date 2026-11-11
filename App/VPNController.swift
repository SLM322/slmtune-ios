import Foundation
import NetworkExtension
import WidgetKit

/// The system VPN profile ("SLMtune" in Settings → VPN) and the connect / disconnect button.
///
/// iOS counterparts of Windows features live here:
/// - kill switch → `includeAllNetworks` (nothing leaves outside the tunnel, even while it reconnects);
/// - Wi-Fi rules ("Дома без VPN") → Connect On Demand rules by SSID, run by the system itself.
@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var connectedSince: Date?
    @Published var lastError: String?

    static let extensionBundleId: String = (Bundle.main.bundleIdentifier ?? "com.slmtune.ios") + ".PacketTunnel"

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isOn: Bool { status == .connected || status == .connecting || status == .reasserting }

    func load(_ s: AppSettings) async {
        let all = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.extensionBundleId }
        observe()
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let m = manager else { status = .invalid; return }
        refresh(m.connection)
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: m.connection, queue: .main) { [weak self] n in
            guard let c = n.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.refresh(c) }
        }
    }

    private func refresh(_ c: NEVPNConnection) {
        if status != c.status { WidgetCenter.shared.reloadAllTimelines() }
        status = c.status
        connectedSince = c.status == .connected ? c.connectedDate : nil
        if c.status == .connected { askForCrashReport(c) }
        guard c.status == .disconnected, crashReport == nil else { return }
        if let e = try? String(contentsOf: AppGroup.lastErrorFile, encoding: .utf8), !e.isEmpty {
            lastError = e
        } else {
            // No shared App Group (re-signed build), or the extension died before writing the file:
            // ask the system why the tunnel stopped.
            c.fetchLastDisconnectError { [weak self] error in
                guard let error = error as NSError? else { return } // nil when the user stopped it
                Task { @MainActor in self?.lastError = Self.describe(error) }
            }
        }
    }

    /// The whole text of the core's crash at the previous start, for "Поделиться" on the main screen.
    @Published var crashReport: String?

    /// After a core crashed, the next start only holds its report (PacketTunnelProvider.holdForReport): fetch it,
    /// show it and stop that placeholder tunnel.
    private func askForCrashReport(_ c: NEVPNConnection) {
        guard let session = c as? NETunnelProviderSession else { return }
        try? session.sendProviderMessage(Data("crash".utf8)) { data in
            let text = String(decoding: data ?? Data(), as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.crashReport = text
                self?.lastError = L("Ядро аварийно завершилось при прошлом запуске:") + "\n" + String(text.prefix(700))
                session.stopVPNTunnel()
            }
        }
    }

    private static func describe(_ e: NSError) -> String {
        var text = e.localizedDescription
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError { text += " — " + u.localizedDescription }
        return text + " (\(e.domain) \(e.code))"
    }

    /// Журнал without a shared App Group: the running extension sends its own log files.
    func fetchLog() async -> [LogLine]? {
        guard !AppGroup.isShared else { return nil }
        guard let session = manager?.connection as? NETunnelProviderSession, status == .connected else { return [] }
        return await withCheckedContinuation { done in
            do {
                try session.sendProviderMessage(Data("log".utf8)) { data in
                    let text = String(decoding: data ?? Data(), as: UTF8.self)
                    done.resume(returning: text.split(separator: "\n").map { l in
                        let p = l.split(separator: "\t", maxSplits: 1)
                        return LogLine(source: String(p.first ?? ""), text: String(p.last ?? ""))
                    })
                }
            } catch { done.resume(returning: []) }
        }
    }

    func clearLog() {
        SharedLog.clear()
        if !AppGroup.isShared { try? (manager?.connection as? NETunnelProviderSession)?.sendProviderMessage(Data("clear-log".utf8)) { _ in } }
    }

    /// Creates or updates the profile (the first time iOS asks "Allow SLMtune to add VPN configurations?").
    private func prepare(_ s: AppSettings) async throws -> NETunnelProviderManager {
        let m = manager ?? NETunnelProviderManager()
        let p = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        p.providerBundleIdentifier = Self.extensionBundleId
        p.serverAddress = "SLMtune"
        p.disconnectOnSleep = false
        p.includeAllNetworks = s.killSwitch
        p.excludeLocalNetworks = s.excludeLocalNetworks
        if #available(iOS 16.4, *) {
            // With the kill switch on, still let the phone's own push / cellular services work.
            p.excludeCellularServices = true
            p.excludeAPNs = true
        }
        if #available(iOS 17.4, *) { p.excludeDeviceCommunication = true }
        p.enforceRoutes = false
        // A copy of the settings for an extension that can't see the App Group (re-signed builds).
        p.providerConfiguration = AppGroup.isShared ? nil : ["settings": SettingsFile.encoded(s), "secret": AppGroup.clashSecret]
        m.protocolConfiguration = p
        m.localizedDescription = "SLMtune"
        m.isEnabled = true
        m.onDemandRules = OnDemand.rules(s)
        m.isOnDemandEnabled = s.onDemandOn
        try await m.saveToPreferences()
        try await m.loadFromPreferences() // required after the first save, or startVPNTunnel fails
        manager = m
        observe()
        return m
    }

    func connect(_ s: AppSettings) async {
        lastError = nil
        crashReport = nil
        guard s.activeServer != nil else { lastError = L("Сначала добавьте сервер."); return }
        do {
            let m = try await prepare(s)
            try m.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        guard let m = manager else { return }
        // With Connect On Demand on, iOS would bring the tunnel straight back: a manual "off" pauses it.
        if m.isOnDemandEnabled {
            m.isOnDemandEnabled = false
            try? await m.saveToPreferences()
        }
        m.connection.stopVPNTunnel()
    }

    /// Settings → on-demand / kill switch changed: rewrite the profile (only if it exists already).
    func applyOnDemand(_ s: AppSettings) async {
        guard manager != nil else { return }
        do { _ = try await prepare(s) } catch { lastError = error.localizedDescription }
    }

    /// Settings changed while connected: the extension rebuilds the config and reloads sing-box in place.
    func reload(_ s: AppSettings) async {
        guard let session = manager?.connection as? NETunnelProviderSession, status == .connected else { return }
        // Without a shared App Group the extension can't read settings.json: send the settings themselves.
        let message = AppGroup.isShared ? Data("reload".utf8) : SettingsFile.encoded(s)
        try? session.sendProviderMessage(message) { _ in }
        if !AppGroup.isShared { _ = try? await prepare(s) } // and keep the profile's copy current for the next start
    }

    func removeProfile() async {
        try? await manager?.removeFromPreferences()
        manager = nil
        status = .invalid
    }
}

/// Connect On Demand: the iOS version of the Android/Windows Wi-Fi rules.
enum OnDemand {
    static func rules(_ s: AppSettings) -> [NEOnDemandRule] {
        var rules: [NEOnDemandRule] = []
        let home = s.wifiHome.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !home.isEmpty {
            let r = NEOnDemandRuleDisconnect()
            r.interfaceTypeMatch = .wiFi
            r.ssidMatch = home
            rules.append(r)
        }
        let wifi: NEOnDemandRule = s.wifiOtherConnect ? NEOnDemandRuleConnect() : NEOnDemandRuleIgnore()
        wifi.interfaceTypeMatch = .wiFi
        rules.append(wifi)
        let cell: NEOnDemandRule = s.cellularConnect ? NEOnDemandRuleConnect() : NEOnDemandRuleIgnore()
        cell.interfaceTypeMatch = .cellular
        rules.append(cell)
        return rules
    }
}
