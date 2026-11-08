import Foundation
#if canImport(Security)
import Security
#endif

/// The App Group shared by the app and the Packet Tunnel extension. Must match both .entitlements files
/// and Config/Signing.xcconfig (APP_GROUP).
enum AppGroup {
    static let id: String = Bundle.main.object(forInfoDictionaryKey: "SLMAppGroup") as? String ?? "group.com.slmtune.ios"

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
    static var clashSecret: String {
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
