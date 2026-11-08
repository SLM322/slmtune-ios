import NetworkExtension
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vpn: VPNController
    @State private var newWifi = ""
    @State private var showConfig = false
    @State private var confirmRemove = false

    var body: some View {
        SlmList {
            Section {
                Toggle("Kill switch", isOn: $state.settings.killSwitch)
                if state.settings.killSwitch {
                    Toggle("Локальная сеть доступна", isOn: $state.settings.excludeLocalNetworks)
                }
            } header: {
                Text("Защита от утечек")
            } footer: {
                Text("iOS не выпускает трафик мимо VPN, даже пока он переподключается (includeAllNetworks). Если VPN выключить вручную, интернет работает как обычно.")
            }
            .slmRow()

            Section {
                Toggle("Подключать автоматически", isOn: $state.settings.onDemandOn)
                if state.settings.onDemandOn {
                    Toggle("В чужих сетях Wi-Fi", isOn: $state.settings.wifiOtherConnect)
                    Toggle("В мобильной сети", isOn: $state.settings.cellularConnect)
                    ForEach(state.settings.wifiHome, id: \.self) { ssid in
                        Label(ssid, systemImage: "house")
                    }
                    .onDelete { state.settings.wifiHome.remove(atOffsets: $0) }
                    HStack {
                        TextField("Домашняя сеть Wi-Fi (SSID)", text: $newWifi).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button("Текущая") { Task { await addCurrentWifi() } }.buttonStyle(.borderless)
                        Button { addWifi(newWifi) } label: { Image(systemName: "plus.circle.fill") }
                            .buttonStyle(.borderless).disabled(newWifi.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Правила сетей")
            } footer: {
                Text("Connect On Demand: iOS сама включает VPN в выбранных сетях и выключает дома. Правила работают и когда приложение закрыто. Кнопка «Отключить» на главной приостанавливает автоподключение до следующего «Подключить».")
            }
            .slmRow()

            Section {
                Toggle("Фрагментация TLS ClientHello", isOn: $state.settings.protocols.tlsFragment)
                Toggle("Фрагментация TLS-записей", isOn: $state.settings.protocols.tlsRecordFragment)
                Picker("Отпечаток TLS", selection: $state.settings.protocols.fingerprintOverride) {
                    Text("Из ссылки").tag("")
                    ForEach(["chrome", "firefox", "safari", "ios", "edge", "android", "random", "randomized"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Мультиплексирование", selection: $state.settings.protocols.multiplex) {
                    Text("Выключено").tag("")
                    Text("smux").tag("smux"); Text("yamux").tag("yamux"); Text("h2mux").tag("h2mux")
                }
                Stepper(L("Hysteria: вход %d Мбит/с", state.settings.protocols.hysteriaDownMbps),
                        value: $state.settings.protocols.hysteriaDownMbps, in: 0...1000, step: 10)
                Stepper(L("Hysteria: выход %d Мбит/с", state.settings.protocols.hysteriaUpMbps),
                        value: $state.settings.protocols.hysteriaUpMbps, in: 0...1000, step: 10)
                Picker("TUIC: контроль перегрузки", selection: $state.settings.protocols.tuicCongestion) {
                    Text("Из ссылки").tag("")
                    Text("bbr").tag("bbr"); Text("cubic").tag("cubic"); Text("new_reno").tag("new_reno")
                }
                Toggle("Shadowsocks: UDP поверх TCP", isOn: $state.settings.protocols.shadowsocksUdpOverTcp)
            } header: {
                Text("Протоколы")
            } footer: {
                Text("Фрагментация помогает против DPI, блокирующего по SNI (не для Reality и QUIC). 0 Мбит/с — скорость определяет протокол.")
            }
            .slmRow()

            Section("Диагностика") {
                NavigationLink { LogView() } label: { Label("Журнал", systemImage: "doc.text.magnifyingglass") }
                NavigationLink { ConnectionsView() } label: { Label("Соединения", systemImage: "point.3.connected.trianglepath.dotted") }
                NavigationLink { MyServersView() } label: { Label("Мои серверы", systemImage: "externaldrive.connected.to.line.below") }
            }
            .slmRow()

            Section("Для опытных") {
                Picker("MTU", selection: $state.settings.mtu) {
                    ForEach([1280, 1400, 1500, 9000], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Журнал sing-box", selection: $state.settings.logLevel) {
                    ForEach(["error", "warn", "info", "debug"], id: \.self) { Text($0).tag($0) }
                }
                Button("Показать конфиг sing-box") { showConfig = true }
                Button("Удалить профиль VPN из iOS", role: .destructive) { confirmRemove = true }
            }
            .slmRow()

            Section {
                Button("Язык приложения") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("Ядра", value: "sing-box · Xray · mihomo · TrustTunnel · Tor")
                Link("sing-box (GPL-3.0)", destination: URL(string: "https://github.com/SagerNet/sing-box")!)
            } header: {
                Text("О приложении")
            } footer: {
                Text("Язык (русский / English) выбирается в Настройках iOS → SLMtune → Язык.")
            }
            .slmRow()
        }
        .navigationTitle("Настройки")
        .sheet(isPresented: $showConfig) { ConfigPreview() }
        .confirmationDialog("Удалить профиль VPN?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await vpn.removeProfile() } }
        } message: {
            Text("Серверы и настройки останутся. При следующем подключении iOS снова спросит разрешение.")
        }
    }

    private func addWifi(_ ssid: String) {
        let s = ssid.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !state.settings.wifiHome.contains(s) else { return }
        state.settings.wifiHome.append(s)
        newWifi = ""
    }

    /// Reading the SSID needs the "Access Wi-Fi Information" entitlement; a configured VPN app may read it.
    private func addCurrentWifi() async {
        let net: NEHotspotNetwork? = await withCheckedContinuation { c in NEHotspotNetwork.fetchCurrent { c.resume(returning: $0) } }
        if let ssid = net?.ssid, !ssid.isEmpty { addWifi(ssid) } else { state.show(L("Не удалось узнать имя сети: сначала подключите VPN хотя бы раз.")) }
    }
}

/// The config the extension would build now (passwords hidden).
private struct ConfigPreview: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .background(Slm.ink)
            .navigationTitle("config.json")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }

    private var text: String {
        guard let s = state.activeServer else { return L("Нет сервера.") }
        do {
            // Extra cores get their ports only when the tunnel starts: placeholders here.
            let ports = Dictionary(uniqueKeysWithValues: Engines.backends(state.settings, s).enumerated().map { ($1.id, 20000 + $0) })
            let raw = try ConfigBuilder.build(state.settings, server: s, backends: ports)
            // Hide secrets: "password", "uuid", "private_key", "public_key"(Reality pbk is fine but short), "auth_str".
            return raw.replacingOccurrences(of: #""(password|uuid|private_key|pre_shared_key|auth_str)" : "[^"]*""#,
                                            with: "\"$1\" : \"•••\"", options: .regularExpression)
        } catch {
            return error.localizedDescription
        }
    }
}
