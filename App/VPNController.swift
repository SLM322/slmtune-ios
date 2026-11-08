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
        if c.status == .disconnected, let e = try? String(contentsOf: AppGroup.lastErrorFile, encoding: .utf8), !e.isEmpty {
            lastError = e
        }
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
    func reload() async {
        guard let session = manager?.connection as? NETunnelProviderSession, status == .connected else { return }
        try? session.sendProviderMessage(Data("reload".utf8)) { _ in }
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
