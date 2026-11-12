import Foundation
#if canImport(Security)
import Security
#endif

/// The App Group shared by the app and the Packet Tunnel extension. Must match both .entitlements files
/// and Config/Signing.xcconfig (APP_GROUP).
enum AppGroup {
    /// Our own group, or — in a build re-signed with someone else's profile — the first group that profile grants
    /// and this process can really open. The app and the extension read the same profile (the app's), in the same
    /// order, so they land on the same group.
    static let id: String = {
        let declared = Bundle.main.object(forInfoDictionaryKey: "SLMAppGroup") as? String ?? "group.com.slmtune.ios"
        #if os(iOS)
        let fm = FileManager.default
        if fm.containerURL(forSecurityApplicationGroupIdentifier: declared) != nil { return declared }
        for g in profileGroups() where fm.containerURL(forSecurityApplicationGroupIdentifier: g) != nil { return g }
        #endif
        return declared
    }()

    /// App Groups listed in the app's embedded.mobileprovision (an extension looks in the app that contains it).
    private static func profileGroups() -> [String] {
        var bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "appex" { bundle = bundle.deletingLastPathComponent().deletingLastPathComponent() }
        guard let raw = try? Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")),
              let from = raw.range(of: Data("<?xml".utf8)),
              let to = raw.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(from: raw[from.lowerBound..<to.upperBound], format: nil) as? [String: Any],
              let e = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return (e["com.apple.security.application-groups"] as? [String] ?? []).sorted()
    }

    static var container: URL {
        #if os(iOS) || os(macOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        #endif
        // No App Group (unsigned simulator build, or re-signed with a profile without our group — e.g. a bought
        // "signing" certificate with a wildcard App ID): fall back to the process's own folder.
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Whether the app and the extension really share a folder. When not, settings travel inside the VPN profile
    /// (providerConfiguration) and with the reload message — see VPNController and PacketTunnelProvider.
    static var isShared: Bool {
        #if os(iOS) || os(macOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
        #else
        return false
        #endif
    }

    static var settingsFile: URL { container.appendingPathComponent("settings.json") }
    static var rulesDir: URL { dir("rules") }
    /// libbox working folders (cache.db, logs).
    static var workingDir: URL { dir("work") }
    static var tempDir: URL { dir("tmp") }
    /// The extension writes the last start error here so the app can show it.
    static var lastErrorFile: URL { container.appendingPathComponent("last-error.txt") }
    static var lastConfigFile: URL { container.appendingPathComponent("last-config.json") }

    /// sing-box's Clash API inside the extension (Connections panel): loopback only, with a per-install secret.
    static let clashPort = 19090
    /// Without a shared folder the extension can't read the app's secret file: the app puts its secret into the
    /// VPN profile and the extension sets it here before building the config.
    static var secretOverride: String?
    static var clashSecret: String {
        if let o = secretOverride, o.count >= 16 { return o }
        let url = container.appendingPathComponent("api-secret")
        if let s = try? String(contentsOf: url, encoding: .utf8), s.count >= 16 { return s }
        let bytes = (0..<18).map { _ in UInt8.random(in: 0...255) } // SystemRandomNumberGenerator: CSPRNG
        let s = Data(bytes).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        try? s.write(to: url, atomically: true, encoding: .utf8)
        return s
    }

    private static func dir(_ name: String) -> URL {
        let u = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

/// Settings in one JSON file in the App Group: the app writes, the extension reads on every start / reload.
enum SettingsFile {
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: AppGroup.settingsFile),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    static func encoded(_ s: AppSettings) -> Data { (try? JSONEncoder().encode(s)) ?? Data() }

    static func decode(_ data: Data?) -> AppSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    static func save(_ s: AppSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        // .completeFileProtectionUntilFirstUserAuthentication: readable by the extension after the first unlock
        // (on-demand may start the tunnel while the phone is locked).
        try? data.write(to: AppGroup.settingsFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
