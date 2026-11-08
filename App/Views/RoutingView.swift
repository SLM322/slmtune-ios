import SwiftUI

struct RoutingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        SlmList {
            Section {
                Picker("Пресет", selection: $state.settings.preset) {
                    Text("Все сайты через VPN").tag(Preset.all)
                    Text("Всё, кроме российских сайтов").tag(Preset.exceptRu)
                    Text("Только заблокированное").tag(Preset.blocked)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                listsStatus
            } header: {
                Text("Что идёт через VPN")
            } footer: {
                Text(LocalizedStringKey(presetNote))
            }
            .slmRow()

            Section {
                Toggle("ИИ через VPN", isOn: $state.settings.aiViaVpn)
                NavigationLink("Сервисы ИИ") { ServicesView(group: .ai) }.disabled(!state.settings.aiViaVpn)
                Toggle("Мессенджеры и звонки через VPN", isOn: $state.settings.callsViaVpn)
                NavigationLink("Мессенджеры") { ServicesView(group: .call) }.disabled(!state.settings.callsViaVpn)
            } header: {
                Text("Всегда через VPN")
            } footer: {
                Text("ChatGPT, Claude, Gemini и другие ИИ-сервисы идут через VPN при любом пресете — и их DNS тоже, чтобы не получить региональную блокировку.")
            }
            .slmRow()

            Section {
                ForEach(Lists.blocks) { b in
                    Toggle(isOn: Binding(
                        get: { state.settings.blockLists.contains(b.id) },
                        set: { on in
                            state.settings.blockLists.removeAll { $0 == b.id }
                            if on { state.settings.blockLists.append(b.id) }
                        })) {
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey(b.title))
                            Text(LocalizedStringKey(b.note)).font(.caption).foregroundStyle(Slm.text2)
                        }
                    }
                }
            } header: {
                Text("Блокировка")
            } footer: {
                Text("Списки MetaCubeX (rule-set sing-box). Работает только при включённом VPN.")
            }
            .slmRow()

            Section {
                NavigationLink { CustomRulesView() } label: {
                    LabeledContent("Свои правила", value: "\(state.settings.customRules.filter(\.enabled).count)")
                }
                Picker("Каскад для всех серверов", selection: $state.settings.cascadeEntryId) {
                    Text("Выключен").tag("")
                    ForEach(state.settings.servers.filter { $0.kind != "group" }) { s in Text(s.title).tag(s.id) }
                }
                Toggle("Локальная сеть напрямую", isOn: $state.settings.lanBypass)
                Toggle("IPv6", isOn: $state.settings.ipv6)
            } header: {
                Text("Дополнительно")
            } footer: {
                Text("Каскад: каждый сервер подключается через выбранный входной (у сервера может быть и свой — в его карточке).")
            }
            .slmRow()

            Section("DNS") {
                LabeledContent("Через VPN") {
                    TextField("https://1.1.1.1/dns-query", text: $state.settings.remoteDns).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                LabeledContent("Напрямую") {
                    TextField("https://77.88.8.8/dns-query", text: $state.settings.directDns).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
            }
            .slmRow()
        }
        .navigationTitle("Маршруты")
    }

    private var presetNote: String {
        switch state.settings.preset {
        case .all: return "Весь трафик идёт через сервер, кроме локальной сети."
        case .exceptRu: return "Российские сайты и IP — напрямую (быстрее, и банки не ругаются), остальное через VPN."
        case .blocked: return "Через VPN только сайты из списка заблокированных в России, остальное — напрямую."
        }
    }

    @ViewBuilder private var listsStatus: some View {
        let ids = Lists.presetLists(state.settings.preset)
        if !ids.isEmpty {
            HStack {
                let ready = ids.allSatisfy { Lists.has(Lists.ruleFile($0)) }
                Image(systemName: ready ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(ready ? Slm.ok : Slm.warn)
                Text(LocalizedStringKey(ready ? "Списки загружены" : "Списки ещё не загружены")).font(.footnote)
                Spacer()
                Button {
                    Task { await state.updateLists(force: true) }
                } label: {
                    if state.listsUpdating { ProgressView() } else { Text("Обновить") }
                }
                .buttonStyle(.borderless)
                .disabled(state.listsUpdating)
            }
        }
    }
}

struct ServicesView: View {
    let group: ServiceDef.Group
    @EnvironmentObject var state: AppState

    var body: some View {
        SlmList {
            Section {
                ForEach(Catalog.inGroup(group)) { d in
                    Toggle(isOn: Binding(
                        get: { !state.settings.disabledServices.contains(d.id) },
                        set: { on in
                            state.settings.disabledServices.removeAll { $0 == d.id }
                            if !on { state.settings.disabledServices.append(d.id) }
                        })) {
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey(d.name))
                            if !d.note.isEmpty { Text(LocalizedStringKey(d.note)).font(.caption).foregroundStyle(Slm.text2) }
                        }
                    }
                }
            } footer: {
                Text(LocalizedStringKey(group == .ai
                     ? "Выключенный сервис пойдёт по общему пресету."
                     : "Telegram подключается к своим серверам по IP — эти адреса тоже идут через VPN."))
            }
            .slmRow()
        }
        .navigationTitle(LocalizedStringKey(group == .ai ? "Сервисы ИИ" : "Мессенджеры"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomRulesView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: CustomRule?

    var body: some View {
        SlmList {
            Section {
                ForEach($state.settings.customRules) { $r in
                    HStack {
                        Toggle("", isOn: $r.enabled).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(r.name.isEmpty ? (r.domains.first ?? r.ips.first ?? L("Правило")) : r.name)
                            Text(LocalizedStringKey(actionTitle(r.action))).font(.caption).foregroundStyle(Slm.text2)
                        }
                        Spacer()
                        Button { editing = r } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    }
                }
                .onDelete { state.settings.customRules.remove(atOffsets: $0) }
                Button { editing = CustomRule() } label: { Label("Добавить правило", systemImage: "plus") }
            } footer: {
                Text("Свои правила важнее пресета и «ИИ через VPN». Сайт example.com включает и все его поддомены.")
            }
            .slmRow()
        }
        .navigationTitle("Свои правила")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { r in NavigationStack { RuleEditor(rule: r) } }
    }

    private func actionTitle(_ a: String) -> String {
        switch a {
        case "direct": return "Напрямую"
        case "block": return "Блокировать"
        default: return "Через VPN"
        }
    }
}

private struct RuleEditor: View {
    @State var rule: CustomRule
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var domains = ""
    @State private var ips = ""

    var body: some View {
        SlmList {
            Section {
                TextField("Название", text: $rule.name)
                Picker("Действие", selection: $rule.action) {
                    Text("Через VPN").tag("vpn")
                    Text("Напрямую").tag("direct")
                    Text("Блокировать").tag("block")
                }
            }
            .slmRow()
            Section("Сайты (по одному на строку)") {
                TextEditor(text: $domains).frame(minHeight: 90)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .slmRow()
            Section("IP и сети (1.2.3.4, 10.0.0.0/8)") {
                TextEditor(text: $ips).frame(minHeight: 70)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .slmRow()
        }
        .onAppear {
            domains = rule.domains.joined(separator: "\n")
            ips = rule.ips.joined(separator: "\n")
        }
        .navigationTitle("Правило")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    let split = { (t: String) in
                        t.components(separatedBy: CharacterSet(charactersIn: "\n, ;")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
                    rule.domains = split(domains).map { d in
                        // "https://www.site.com/page" → "site.com"
                        var h = d.lowercased()
                        if let u = URL(string: h), let host = u.host { h = host }
                        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
                    }
                    rule.ips = split(ips)
                    if let i = state.settings.customRules.firstIndex(where: { $0.id == rule.id }) { state.settings.customRules[i] = rule }
                    else { state.settings.customRules.append(rule) }
                    dismiss()
                }
            }
        }
    }
}
