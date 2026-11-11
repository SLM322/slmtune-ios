import NetworkExtension
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vpn: VPNController
    @StateObject private var traffic = TrafficMonitor()
    @State private var showServers = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    PowerButton(on: vpn.status == .connected, busy: busy) { toggle() }
                        .padding(.top, 8)
                    Text(LocalizedStringKey(statusText))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(vpn.status == .connected ? Slm.ok : Slm.text2)
                    if let since = vpn.connectedSince {
                        Text(since, style: .timer).font(.footnote.monospacedDigit()).foregroundStyle(Slm.text3)
                    }
                    if let e = vpn.lastError {
                        Text(verbatim: e).font(vpn.crashReport == nil ? .footnote : .caption2.monospaced())
                            .foregroundStyle(Slm.err)
                            .multilineTextAlignment(vpn.crashReport == nil ? .center : .leading).padding(.horizontal)
                            .textSelection(.enabled)
                        if let report = vpn.crashReport {
                            ShareLink(item: report) { Label("Поделиться отчётом", systemImage: "square.and.arrow.up") }
                                .font(.footnote)
                        }
                    }
                    serverCard
                    if vpn.status == .connected { speedCard }
                    presetCard
                }
                .padding()
            }
            .background(Slm.ink)
            .navigationTitle("SLMtune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink { ConnectionsView() } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }
                        .disabled(vpn.status != .connected)
                    NavigationLink { LogView() } label: { Image(systemName: "doc.text.magnifyingglass") }
                }
            }
            .sheet(isPresented: $showServers) { NavigationStack { ServersView(picker: true) } }
        }
        .onChange(of: vpn.status) { traffic.run($0 == .connected) }
        .onAppear { traffic.run(vpn.status == .connected) }
    }

    private var busy: Bool { [.connecting, .disconnecting, .reasserting].contains(vpn.status) }

    private var statusText: String {
        switch vpn.status {
        case .connected: return "Подключено"
        case .connecting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        case .reasserting: return "Переподключение…"
        default: return "Не подключено"
        }
    }

    private var header: some View {
        HStack {
            (Text("SLM").foregroundColor(Slm.accent2) + Text("tune").foregroundColor(Slm.text))
                .font(.largeTitle.weight(.heavy))
            Spacer()
            if state.settings.killSwitch {
                Label("Kill switch", systemImage: "lock.shield").font(.caption).foregroundStyle(Slm.ok)
            }
        }
    }

    private func toggle() {
        Task {
            if vpn.isOn { await vpn.disconnect() } else { await vpn.connect(state.settings) }
        }
    }

    private var serverCard: some View {
        Button { showServers = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe").font(.title2).foregroundStyle(Slm.accent2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.activeServer?.title ?? L("Сервер не выбран")).font(.headline).foregroundStyle(Slm.text).lineLimit(1)
                    if let s = state.activeServer {
                        let hops = Outbounds.hops(state.settings, s)
                        Text(hops.isEmpty ? ShareLinks.describe(s) : (hops.map(\.title) + [s.title]).joined(separator: " → "))
                            .font(.caption).foregroundStyle(Slm.text2).lineLimit(1)
                    } else {
                        Text("Добавьте сервер на вкладке «Серверы»").font(.caption).foregroundStyle(Slm.text2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Slm.text3)
            }
            .padding(14)
            .background(Slm.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var speedCard: some View {
        HStack {
            stat("arrow.down", human(traffic.down) + L("/с"), human(traffic.totalDown))
            Divider().frame(height: 36).overlay(Slm.line)
            stat("arrow.up", human(traffic.up) + L("/с"), human(traffic.totalUp))
        }
        .padding(14)
        .background(Slm.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ icon: String, _ speed: String, _ total: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Slm.accent2)
            VStack(alignment: .leading) {
                Text(speed).font(.headline.monospacedDigit())
                Text(total).font(.caption).foregroundStyle(Slm.text3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Через VPN").font(.subheadline.weight(.semibold)).foregroundStyle(Slm.text2)
            Picker("Через VPN", selection: $state.settings.preset) {
                Text("Все сайты").tag(Preset.all)
                Text("Кроме РФ").tag(Preset.exceptRu)
                Text("Заблокированное").tag(Preset.blocked)
            }
            .pickerStyle(.segmented)
            Toggle("ИИ всегда через VPN", isOn: $state.settings.aiViaVpn)
        }
        .padding(14)
        .background(Slm.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
