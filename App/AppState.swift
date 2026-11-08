import Foundation
import SwiftUI

/// The app's settings and everything views need; every change is saved to the App Group at once and the
/// running tunnel is told to reload (the extension rebuilds the sing-box config from the file).
@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { changed(old: oldValue) }
    }
    @Published var toast: String?
    @Published var pendingSubscriptionURL: String?
    @Published var listsUpdating = false

    let vpn = VPNController()
    private var saveTask: Task<Void, Never>?

    init() {
        settings = SettingsFile.load()
        Task { await vpn.load(settings) }
    }

    private func changed(old: AppSettings) {
        SettingsFile.save(settings)
        // Reload the tunnel after a short pause, so dragging a slider doesn't restart sing-box ten times.
        saveTask?.cancel()
        let s = settings
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            if Self.needsSystemUpdate(old, s) { await self.vpn.applyOnDemand(s) }
            if Self.needsReload(old, s) { await self.vpn.reload(s) }
            if old.preset != s.preset || old.blockLists != s.blockLists { await self.updateLists() }
        }
    }

    /// Ping results and the subscription list don't change the config.
    private static func needsReload(_ a: AppSettings, _ b: AppSettings) -> Bool {
        var a2 = a, b2 = b
        a2.servers = a2.servers.map { var x = $0; x.pingMs = -1; return x }
        b2.servers = b2.servers.map { var x = $0; x.pingMs = -1; return x }
        a2.subscriptions = []; b2.subscriptions = []
        return (try? JSONEncoder().encode(a2)) != (try? JSONEncoder().encode(b2))
    }

    private static func needsSystemUpdate(_ a: AppSettings, _ b: AppSettings) -> Bool {
        a.onDemandOn != b.onDemandOn || a.wifiHome != b.wifiHome || a.wifiOtherConnect != b.wifiOtherConnect
            || a.cellularConnect != b.cellularConnect || a.killSwitch != b.killSwitch || a.excludeLocalNetworks != b.excludeLocalNetworks
    }

    func show(_ text: String) {
        toast = text
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if toast == text { toast = nil } }
    }

    // MARK: servers

    var activeServer: Server? { settings.activeServer }

    func select(_ s: Server) {
        settings.activeId = s.id
    }

    func add(_ list: [Server]) {
        settings.servers += list
        if settings.activeId.isEmpty, let f = settings.servers.first { settings.activeId = f.id }
    }

    func remove(_ ids: Set<String>) {
        settings.servers.removeAll { ids.contains($0.id) }
        for i in settings.servers.indices {
            if ids.contains(settings.servers[i].viaId) { settings.servers[i].viaId = "" }
            settings.servers[i].members.removeAll { ids.contains($0) }
        }
        if ids.contains(settings.cascadeEntryId) { settings.cascadeEntryId = "" }
        if ids.contains(settings.activeId) { settings.activeId = settings.servers.first?.id ?? "" }
    }

    func update(_ s: Server) {
        if let i = settings.servers.firstIndex(where: { $0.id == s.id }) { settings.servers[i] = s }
    }

    // MARK: lists

    func updateLists(force: Bool = false) async {
        listsUpdating = true
        let n = await Lists.update(settings, force: force)
        listsUpdating = false
        if n > 0 { await vpn.reload(settings) }
        if force { show(n > 0 ? L("Списки обновлены: %d", n) : L("Списки уже свежие или недоступны.")) }
    }

    // MARK: import

    func importText(_ text: String) {
        switch Importer.parse(text) {
        case .servers(let list, let failed):
            add(list)
            if list.isEmpty { show(failed.first ?? L("Ссылки не распознаны.")) }
            else if failed.isEmpty { show(L("Добавлено серверов: %d", list.count)) }
            else { show(L("Добавлено: %d, не распознано: %d", list.count, failed.count)) }
        case .subscription(let url):
            pendingSubscriptionURL = url
        case .nothing(let why):
            show(why)
        }
    }

    func addSubscription(url: String, name: String = "") async {
        var sub = Subscription(name: name, url: url)
        settings.subscriptions.append(sub)
        await refresh(&sub)
    }

    func refreshAll(includeManual: Bool = false) async {
        for var sub in settings.subscriptions where sub.autoUpdate || includeManual { await refresh(&sub) }
    }

    func refresh(_ sub: inout Subscription) async {
        do {
            let r = try await Subscriptions.fetch(sub)
            sub = r.sub
            // Keep the chosen server and cascades if the same server comes back (same address and port).
            let old = settings.servers.filter { $0.subscriptionId == sub.id }
            let fresh = r.servers.map { n -> Server in
                var n = n
                if let o = old.first(where: { $0.server == n.server && $0.port == n.port && $0.kind == n.kind && $0.name == n.name }) {
                    n.id = o.id; n.viaId = o.viaId; n.pingMs = o.pingMs
                }
                return n
            }
            let keep = settings.servers.filter { $0.subscriptionId != sub.id }
            settings.servers = keep + fresh
            if settings.server(settings.activeId) == nil { settings.activeId = settings.servers.first?.id ?? "" }
            show(L("Подписка «%@»: %d серверов", sub.name, fresh.count))
        } catch {
            sub.lastError = error.localizedDescription
            show(error.localizedDescription)
        }
        let id = sub.id
        if let i = settings.subscriptions.firstIndex(where: { $0.id == id }) { settings.subscriptions[i] = sub }
    }

    // MARK: ping

    func pingAll() async {
        // QUIC/UDP servers (Hysteria, TUIC, WireGuard) don't answer a TCP handshake: marked, not pinged.
        for i in settings.servers.indices where Pinger.udpOnly.contains(settings.servers[i].kind) { settings.servers[i].pingMs = -3 }
        let list = settings.servers.filter { $0.kind != "group" && !Pinger.udpOnly.contains($0.kind) }
        await withTaskGroup(of: (String, Int).self) { g in
            for s in list { g.addTask { (s.id, await Pinger.tcp(host: s.server, port: s.port)) } }
            for await (id, ms) in g {
                if let i = settings.servers.firstIndex(where: { $0.id == id }) { settings.servers[i].pingMs = ms }
            }
        }
    }
}
