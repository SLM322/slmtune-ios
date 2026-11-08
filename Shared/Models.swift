import Foundation

/// One server: a share link split into fields — the same shape as ServerProfile (Windows) and Server (Android).
struct Server: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    var name: String = ""
    /// vless, vmess, trojan, ss, hysteria2, hysteria, tuic, anytls, naive, socks, wireguard, group
    var kind: String = ""
    var server: String = ""
    var port: Int = 0
    var userId: String = ""
    var password: String = ""
    var params: [String: String] = [:]
    var subscriptionId: String = ""
    /// Cascade: reach this server through another one (its id).
    var viaId: String = ""
    /// Group: member ids, in order.
    var members: [String] = []
    var link: String = ""
    /// Last TCP ping, ms; -1 = not measured, -2 = no answer.
    var pingMs: Int = -1

    func param(_ key: String, _ def: String = "") -> String {
        if let v = params[key] { return v }
        return params.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value ?? def
    }

    var title: String { name.isEmpty ? "\(kind) \(server)" : name }

    init(id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
         name: String = "", kind: String = "", server: String = "", port: Int = 0,
         userId: String = "", password: String = "", params: [String: String] = [:],
         subscriptionId: String = "", viaId: String = "", members: [String] = [], link: String = "") {
        self.id = id; self.name = name; self.kind = kind; self.server = server; self.port = port
        self.userId = userId; self.password = password; self.params = params
        self.subscriptionId = subscriptionId; self.viaId = viaId; self.members = members; self.link = link
    }

    // Tolerant decoding: settings written by an older build may miss fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 0
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId) ?? ""
        viaId = try c.decodeIfPresent(String.self, forKey: .viaId) ?? ""
        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        pingMs = try c.decodeIfPresent(Int.self, forKey: .pingMs) ?? -1
    }
}

/// Provider subscription: the server list plus traffic and end date (subscription-userinfo).
struct Subscription: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var url: String = ""
    var autoUpdate: Bool = true
    var lastUpdate: Date? = nil
    var count: Int = 0
    var lastError: String? = nil
    var upload: Int64 = 0
    var download: Int64 = 0
    var total: Int64 = 0
    /// Unix seconds; 0 = not sent.
    var expire: Int64 = 0
}

/// The user's own rule: these sites / IPs go through the VPN, direct, or are blocked.
struct CustomRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    /// "vpn" | "direct" | "block"
    var action: String = "vpn"
    var domains: [String] = []
    var ips: [String] = []
    var enabled: Bool = true
}

/// Protocol tuning (Windows: Settings → Протоколы), only the parts sing-box on iOS can use.
struct ProtocolSettings: Codable, Hashable {
    var tlsFragment = false
    var tlsRecordFragment = false
    /// "" = from the link; chrome, firefox, safari, edge, ios, android, random, randomized.
    var fingerprintOverride = ""
    /// "" = off; smux | yamux | h2mux.
    var multiplex = ""
    var multiplexMaxConnections = 4
    var multiplexPadding = false
    var hysteriaUpMbps = 0
    var hysteriaDownMbps = 0
    var tuicCongestion = ""
    var tuicZeroRtt = false
    var shadowsocksUdpOverTcp = false
}

/// "Мой сервер": a VPS the app sets up over SSH (same fields as Windows/Android). The password is never stored.
struct MyServer: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var user: String = "root"
    /// The pinned host key ("ssh-ed25519 AAAA…"); empty until the user confirmed its fingerprint.
    var hostKey: String = ""
    /// The app's key is in the server's authorized_keys: no password needed any more.
    var keyInstalled: Bool = false
    var title: String { name.isEmpty ? host : name }
}

enum Preset: String, Codable, CaseIterable, Identifiable {
    /// Everything through the VPN.
    case all
    /// Russian sites and IPs direct, the rest through the VPN.
    case exceptRu = "except_ru"
    /// Only blocked sites through the VPN.
    case blocked
    var id: String { rawValue }
}

struct AppSettings: Codable {
    var servers: [Server] = []
    var activeId: String = ""
    var subscriptions: [Subscription] = []
    var preset: Preset = .exceptRu
    var aiViaVpn = true
    var callsViaVpn = false
    var disabledServices: [String] = []
    var customRules: [CustomRule] = []
    /// Ids from Lists.blocks: ads, trackers, adult.
    var blockLists: [String] = []
    var lanBypass = true
    var ipv6 = false
    /// Cascade entry for every server ("" = off).
    var cascadeEntryId = ""
    var remoteDns = "https://1.1.1.1/dns-query"
    var directDns = "https://77.88.8.8/dns-query"
    var protocols = ProtocolSettings()

    // ---- iOS: Connect On Demand (instead of the Android Wi-Fi watcher) ----
    var onDemandOn = false
    /// Wi-Fi names where the VPN is switched off ("Дома без VPN").
    var wifiHome: [String] = []
    /// Other Wi-Fi networks: connect automatically.
    var wifiOtherConnect = true
    /// Mobile network: connect automatically.
    var cellularConnect = true

    // ---- iOS: the "kill switch" ----
    /// includeAllNetworks: nothing leaves the phone outside the tunnel, even while it reconnects.
    var killSwitch = false
    /// With the kill switch: the local network (AirPlay, printers) stays reachable.
    var excludeLocalNetworks = true

    var mtu = 9000
    var logLevel = "warn"
    var myServers: [MyServer] = []

    init() {}

    init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        servers = v(.servers, d.servers); activeId = v(.activeId, d.activeId)
        subscriptions = v(.subscriptions, d.subscriptions); preset = v(.preset, d.preset)
        aiViaVpn = v(.aiViaVpn, d.aiViaVpn); callsViaVpn = v(.callsViaVpn, d.callsViaVpn)
        disabledServices = v(.disabledServices, d.disabledServices); customRules = v(.customRules, d.customRules)
        blockLists = v(.blockLists, d.blockLists); lanBypass = v(.lanBypass, d.lanBypass); ipv6 = v(.ipv6, d.ipv6)
        cascadeEntryId = v(.cascadeEntryId, d.cascadeEntryId)
        remoteDns = v(.remoteDns, d.remoteDns); directDns = v(.directDns, d.directDns)
        protocols = v(.protocols, d.protocols)
        onDemandOn = v(.onDemandOn, d.onDemandOn); wifiHome = v(.wifiHome, d.wifiHome)
        wifiOtherConnect = v(.wifiOtherConnect, d.wifiOtherConnect); cellularConnect = v(.cellularConnect, d.cellularConnect)
        killSwitch = v(.killSwitch, d.killSwitch); excludeLocalNetworks = v(.excludeLocalNetworks, d.excludeLocalNetworks)
        mtu = v(.mtu, d.mtu); logLevel = v(.logLevel, d.logLevel)
        myServers = v(.myServers, d.myServers)
    }

    var activeServer: Server? { servers.first { $0.id == activeId } ?? servers.first }
    func server(_ id: String) -> Server? { servers.first { $0.id == id } }
}
