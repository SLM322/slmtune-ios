import Foundation

/// The sing-box config for one connection — the iOS counterpart of SingBoxConfig.Build (Windows) and
/// ConfigBuilder.kt (Android). Order of the route rules matters: blocking first, then the user's own rules,
/// AI and calls, then the preset.
///
/// Left out on iOS (no such thing in a Network Extension): process_name / package_name rules, the local
/// mixed/SOCKS inbound for other devices, the Windows-only LAN DNS tricks.
enum ConfigBuilder {
    static let lanRanges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"]

    /// "https://1.1.1.1/dns-query" → a sing-box 1.12+ DNS server object.
    static func dnsServer(tag: String, url: String, detour: String?) -> JSON {
        var o: JSON = ["tag": tag]
        let u = URLComponents(string: url)
        switch u?.scheme?.lowercased() {
        case "https":
            o["type"] = "https"; o["server"] = u?.host ?? "1.1.1.1"
            if let p = u?.path, !p.isEmpty, p != "/dns-query" { o["path"] = p }
        case "tls":
            o["type"] = "tls"; o["server"] = u?.host ?? "1.1.1.1"
        case "quic":
            o["type"] = "quic"; o["server"] = u?.host ?? "1.1.1.1"
        default:
            o["type"] = "udp"
            let raw = url.components(separatedBy: "://").last ?? ""
            o["server"] = raw.isEmpty ? "1.1.1.1" : raw
        }
        if let d = detour { o["detour"] = d }
        return o
    }

    private static func uniq(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.filter { seen.insert($0).inserted }
    }

    private static func cidr(_ ip: String) -> String {
        if ip.contains("/") { return ip }
        return ip.contains(":") ? "\(ip)/128" : "\(ip)/32"
    }

    /// `backends`: server id → SOCKS port of its extra core, started by the extension before sing-box.
    static func build(_ s: AppSettings, server: Server, backends: [String: Int] = [:]) throws -> String {
        let chain = try Outbounds.chain(s, server, backends: backends)
        let udp = ShareLinks.hasUdp(server) && Outbounds.hops(s, server).allSatisfy(ShareLinks.hasUdp)
        let selective = s.preset == .blocked

        // ---- rule sets (local files the app keeps up to date) ----
        var ruleSets: [JSON] = []
        func local(_ tag: String, _ url: URL, binary: Bool) {
            ruleSets.append(["type": "local", "tag": tag, "format": binary ? "binary" : "source", "path": url.path])
        }
        let blockTags: [String] = Lists.blocks.filter { s.blockLists.contains($0.id) && Lists.has(Lists.blockFile($0)) }.map {
            let tag = "block-\($0.id)"
            local(tag, Lists.blockFile($0), binary: true)
            return tag
        }
        let presetTags = Lists.presetLists(s.preset).filter { Lists.has(Lists.ruleFile($0)) }
        for t in presetTags { local(t, Lists.ruleFile(t), binary: false) }

        // ---- services ----
        let on = { (d: ServiceDef) in !s.disabledServices.contains(d.id) }
        let aiDomains = uniq(Catalog.inGroup(.ai).filter(on).flatMap(\.domains) + Catalog.aiAlways)
        let callDefs = Catalog.inGroup(.call).filter(on)
        let callDomains = uniq(callDefs.flatMap(\.domains))
        let telegramOn = callDefs.contains { $0.id == "telegram" }

        var rules: [JSON] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["ip_is_private": true, "action": "route", "outbound": "direct"],
        ]
        if !blockTags.isEmpty { rules.append(["rule_set": blockTags, "action": "reject"]) }
        // The user's own rules win over everything below.
        for r in s.customRules where r.enabled {
            func target(_ o: JSON) -> JSON {
                var o = o
                if r.action == "block" { o["action"] = "reject" }
                else { o["action"] = "route"; o["outbound"] = r.action == "direct" ? "direct" : "proxy" }
                return o
            }
            let domains = r.domains.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }.filter { !$0.isEmpty }
            if !domains.isEmpty { rules.append(target(["domain_suffix": uniq(domains)])) }
            let ips = r.ips.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(cidr)
            if !ips.isEmpty { rules.append(target(["ip_cidr": uniq(ips)])) }
        }
        // A server without UDP: QUIC is refused at once so browsers fall back to TCP instead of leaking.
        if !udp { rules.append(["network": ["udp"], "port": [443], "action": "reject"]) }
        if s.aiViaVpn, !aiDomains.isEmpty {
            var r: JSON = ["domain_suffix": aiDomains, "action": "route", "outbound": "proxy"]
            if !udp { r["network"] = ["tcp"] }
            rules.append(r)
        }
        // Messengers and calls: their sites (and Telegram's data centres) through the VPN.
        if s.callsViaVpn {
            if !callDomains.isEmpty { rules.append(["domain_suffix": callDomains, "action": "route", "outbound": "proxy"]) }
            if telegramOn {
                let nets = s.ipv6 ? Catalog.telegramCidrs : Catalog.telegramCidrs.filter { !$0.contains(":") }
                rules.append(["ip_cidr": nets, "action": "route", "outbound": "proxy"])
            }
        }
        if !udp { rules.append(["network": ["udp"], "action": "route", "outbound": "direct"]) }
        if !presetTags.isEmpty {
            rules.append(["rule_set": presetTags, "action": "route", "outbound": selective ? "proxy" : "direct"])
        }

        // ---- DNS: direct names via a DoH reachable without the VPN, the rest through the tunnel ----
        var dnsRules: [JSON] = []
        if !blockTags.isEmpty { dnsRules.append(["rule_set": blockTags, "action": "predefined", "rcode": "NXDOMAIN"]) }
        if s.aiViaVpn { dnsRules.append(["domain_suffix": aiDomains, "action": "route", "server": "remote-dns"]) }
        let domainSets = presetTags.filter { $0 != Lists.ruIps }
        if !domainSets.isEmpty {
            dnsRules.append(["rule_set": domainSets, "action": "route", "server": selective ? "remote-dns" : "direct-dns"])
        }
        var dns: JSON = [
            "servers": [dnsServer(tag: "remote-dns", url: s.remoteDns, detour: "proxy"),
                        dnsServer(tag: "direct-dns", url: s.directDns, detour: nil)],
            "rules": dnsRules,
            "final": selective ? "direct-dns" : "remote-dns",
        ]
        if !s.ipv6 { dns["strategy"] = "ipv4_only" }

        // ---- TUN: libbox turns it into NEPacketTunnelNetworkSettings (see ExtensionPlatformInterface.openTun) ----
        var tun: JSON = [
            "type": "tun", "tag": "tun-in",
            "address": s.ipv6 ? ["172.19.0.1/30", "fdfe:dcba:9876::1/126"] : ["172.19.0.1/30"],
            "mtu": s.mtu, "auto_route": true, "strict_route": true,
            // gVisor for UDP, the system stack for TCP: lighter on the extension's ~50 MB memory limit.
            "stack": "mixed",
        ]
        // Local network (router, printers, AirPlay) stays outside the tunnel.
        if s.lanBypass, !s.killSwitch { tun["route_exclude_address"] = lanRanges }

        var outbounds = chain.outbounds
        outbounds.append(["type": "direct", "tag": "direct"])
        var route: JSON = [
            "rules": rules,
            "final": selective ? "direct" : "proxy",
            "auto_detect_interface": true,
            "default_domain_resolver": "direct-dns",
        ]
        if !ruleSets.isEmpty { route["rule_set"] = ruleSets }

        var config: JSON = [
            "log": ["level": s.logLevel, "timestamp": true, "output": SharedLog.singBoxLogFile.path] as JSON,
            "dns": dns,
            "inbounds": [tun],
            "outbounds": outbounds,
            "route": route,
            "experimental": [
                "cache_file": ["enabled": true] as JSON,
                // Connections panel in the app; loopback only, with a secret.
                "clash_api": ["external_controller": "127.0.0.1:\(AppGroup.clashPort)", "secret": AppGroup.clashSecret] as JSON,
            ] as JSON,
        ]
        if !chain.endpoints.isEmpty { config["endpoints"] = chain.endpoints }
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
