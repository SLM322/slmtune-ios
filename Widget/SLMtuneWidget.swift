import AppIntents
import NetworkExtension
import SwiftUI
import WidgetKit

// Home-screen / lock-screen widget and (iOS 18) a Control Center button.
// The state comes from the VPN profile itself; the button starts or stops the tunnel through an App Intent
// (the widget extension carries the Network Extension entitlement for that). If iOS refuses
// (no profile yet), the widget opens the app instead.

enum VPNToggle {
    static func manager() async -> NETunnelProviderManager? {
        let all = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        return all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier?.hasSuffix(".PacketTunnel") == true }
    }

    static func isOn() async -> Bool {
        guard let m = await manager() else { return false }
        return [.connected, .connecting, .reasserting].contains(m.connection.status)
    }

    static func set(_ on: Bool) async throws {
        guard let m = await manager() else { throw IntentError.noProfile }
        if on {
            if !m.isEnabled { m.isEnabled = true; try await m.saveToPreferences() }
            try m.connection.startVPNTunnel()
        } else {
            // As the app's own button: a manual "off" pauses Connect On Demand.
            if m.isOnDemandEnabled { m.isOnDemandEnabled = false; try? await m.saveToPreferences() }
            m.connection.stopVPNTunnel()
        }
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case noProfile
        var localizedStringResource: LocalizedStringResource { "Откройте SLMtune и подключитесь один раз." }
    }
}

struct ToggleVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "SLMtune: включить или выключить VPN"
    func perform() async throws -> some IntentResult {
        try await VPNToggle.set(!(await VPNToggle.isOn()))
        try? await Task.sleep(nanoseconds: 700_000_000)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: widget

struct VPNEntry: TimelineEntry {
    let date: Date
    let on: Bool
    let server: String
}

struct VPNProvider: TimelineProvider {
    func placeholder(in context: Context) -> VPNEntry { VPNEntry(date: Date(), on: false, server: "SLMtune") }

    func getSnapshot(in context: Context, completion: @escaping (VPNEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VPNEntry>) -> Void) {
        Task { completion(Timeline(entries: [await entry()], policy: .after(Date().addingTimeInterval(15 * 60)))) }
    }

    private func entry() async -> VPNEntry {
        VPNEntry(date: Date(), on: await VPNToggle.isOn(), server: SettingsFile.load().activeServer?.title ?? L("Сервер не выбран"))
    }
}

struct VPNWidgetView: View {
    let entry: VPNEntry
    @Environment(\.widgetFamily) private var family

    private let ink = Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
    private let accent = Color(red: 209 / 255, green: 0, blue: 209 / 255)
    private let accent2 = Color(red: 1, green: 61 / 255, blue: 1)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.on ? "lock.shield.fill" : "lock.shield")
            }
            .widgetURL(URL(string: "slmtune://toggle"))
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.on ? "VPN включён" : "VPN выключен").font(.headline)
                Text(entry.server).font(.caption).lineLimit(1)
            }
            .widgetURL(URL(string: "slmtune://toggle"))
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SLM").font(.headline.weight(.heavy)).foregroundColor(accent2)
                        + Text("tune").font(.headline.weight(.heavy)).foregroundColor(.white)
                    Spacer()
                    Circle().fill(entry.on ? Color.green : Color.gray).frame(width: 8, height: 8)
                }
                Text(entry.server).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                Spacer(minLength: 0)
                toggle
            }
            .padding(2)
        }
    }

    @ViewBuilder private var toggle: some View {
        let label = HStack {
            Image(systemName: "power")
            Text(entry.on ? "Отключить" : "Подключить").font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(entry.on ? AnyShapeStyle(LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing))
                             : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
        .foregroundStyle(.white)
        if #available(iOS 17.0, *) {
            Button(intent: ToggleVPNIntent()) { label }.buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "slmtune://toggle")!) { label }
        }
    }
}

struct SLMtuneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SLMtuneWidget", provider: VPNProvider()) { entry in
            if #available(iOS 17.0, *) {
                VPNWidgetView(entry: entry).containerBackground(Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255), for: .widget)
            } else {
                VPNWidgetView(entry: entry).background(Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255))
            }
        }
        .configurationDisplayName("SLMtune")
        .description("Состояние VPN и кнопка подключения.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Control Center (iOS 18)

@available(iOS 18.0, *)
struct SetVPNIntent: SetValueIntent {
    static var title: LocalizedStringResource = "SLMtune VPN"
    @Parameter(title: "Включён") var value: Bool
    func perform() async throws -> some IntentResult {
        try await VPNToggle.set(value)
        return .result()
    }
}

@available(iOS 18.0, *)
struct VPNControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { await VPNToggle.isOn() }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SLMtuneControl", provider: Provider()) { on in
            ControlWidgetToggle("SLMtune", isOn: on, action: SetVPNIntent()) { isOn in
                Label(isOn ? "VPN включён" : "VPN выключен", systemImage: isOn ? "lock.shield.fill" : "lock.shield")
            }
        }
        .displayName("SLMtune VPN")
    }
}

@main
struct SLMtuneWidgets: WidgetBundle {
    var body: some Widget {
        SLMtuneWidget()
        if #available(iOS 18.0, *) { VPNControl() }
    }
}
