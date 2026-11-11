import Foundation

/// Facts about this install for "Диагностика" in Settings: which build it is and what the signature allows.
/// A re-signed build may lose the App Group or the Network Extension entitlement — this shows it at a glance.
enum Diagnostics {
    static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        #if SLM_LITE
        return "\(v) (\(b)) lite"
        #else
        return "\(v) (\(b))"
        #endif
    }

    static var cores: String {
        #if SLM_LITE
        return "sing-box"
        #else
        return "sing-box · Xray · mihomo · TrustTunnel · Tor"
        #endif
    }

    static var text: String {
        let ext = Bundle.main.bundleURL.appendingPathComponent("PlugIns/PacketTunnel.appex")
        var lines = [
            "Сборка: \(version)",
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "?")",
            "App Group \(AppGroup.id): \(AppGroup.isShared ? "общий" : "нет (настройки идут через профиль VPN)")",
            "Расширение VPN: \(FileManager.default.fileExists(atPath: ext.path) ? "есть" : "НЕТ В СБОРКЕ")",
            "",
            "Подпись приложения:",
        ]
        lines += profile(Bundle.main.bundleURL)
        lines += ["", "Подпись расширения VPN:"]
        lines += profile(ext)
        return lines.joined(separator: "\n")
    }

    /// What embedded.mobileprovision grants (the code signature can't ask for more than this).
    private static func profile(_ bundle: URL) -> [String] {
        guard let raw = try? Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")),
              let from = raw.range(of: Data("<?xml".utf8)),
              let to = raw.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(from: raw[from.lowerBound..<to.upperBound], format: nil) as? [String: Any]
        else { return ["  профиль не найден"] }
        let e = plist["Entitlements"] as? [String: Any] ?? [:]
        let ne = e["com.apple.developer.networking.networkextension"] as? [String] ?? []
        let groups = e["com.apple.security.application-groups"] as? [String] ?? []
        var out = [
            "  профиль: \(plist["Name"] as? String ?? "?")",
            "  app id: \(e["application-identifier"] as? String ?? "?")",
            "  Network Extension: \(ne.isEmpty ? "НЕТ" : ne.joined(separator: ", "))",
            "  App Groups: \(groups.isEmpty ? "нет" : groups.joined(separator: ", "))",
        ]
        if let d = plist["ExpirationDate"] as? Date {
            out.append("  действует до: \(d.formatted(date: .numeric, time: .omitted))")
        }
        return out
    }
}
