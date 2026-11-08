import SwiftUI

struct ServerDetailView: View {
    let id: String
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var share: String?
    @State private var editGroup: Server?
    @State private var confirmDelete = false

    private var server: Server? { state.settings.server(id) }

    var body: some View {
        if let s = server {
            SlmList {
                Section {
                    TextField("Название", text: binding(\.name))
                    LabeledContent("Протокол", value: ShareLinks.describe(s))
                    if s.kind != "group" {
                        LabeledContent("Адрес", value: "\(s.server):\(s.port)")
                        if !s.param("sni").isEmpty { LabeledContent("SNI", value: s.param("sni")) }
                    }
                    if s.pingMs >= 0 { LabeledContent("Пинг", value: L("%d мс", s.pingMs)) }
                }
                .slmRow()

                Section {
                    Picker("Через сервер", selection: binding(\.viaId)) {
                        Text("Напрямую").tag("")
                        ForEach(state.settings.servers.filter { $0.id != s.id && $0.kind != "group" }) { o in
                            Text(o.title).tag(o.id)
                        }
                    }
                } header: {
                    Text("Каскад")
                } footer: {
                    Text("Соединение с этим сервером пойдёт через выбранный: конечный сервер увидит только адрес промежуточного.")
                }
                .slmRow()

                Section {
                    Button { state.select(s); dismiss() } label: { Label("Сделать активным", systemImage: "checkmark.circle") }
                        .disabled(state.activeServer?.id == s.id)
                    if s.kind == "group" {
                        Button { editGroup = s } label: { Label("Изменить группу", systemImage: "square.stack.3d.up") }
                    } else if let link = ShareLinks.export(s) {
                        Button { share = link } label: { Label("Поделиться (QR-код)", systemImage: "qrcode") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
                }
                .slmRow()
            }
            .navigationTitle(s.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(get: { share.map { IdentifiedString(value: $0) } }, set: { share = $0?.value })) { ShareServerView(link: $0.value) }
            .sheet(item: $editGroup) { g in NavigationStack { GroupEditorView(group: g, isNew: false) } }
            .confirmationDialog("Удалить сервер?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { state.remove([s.id]); dismiss() }
            }
        } else {
            Text("Сервер удалён").foregroundStyle(Slm.text2)
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<Server, T>) -> Binding<T> {
        Binding(
            get: { (server ?? Server())[keyPath: kp] },
            set: { v in
                guard var s = server else { return }
                s[keyPath: kp] = v
                state.update(s)
            })
    }
}

struct IdentifiedString: Identifiable { let value: String; var id: String { value } }

/// A group of servers behind one entry: sing-box urltest picks the fastest (or keeps one until it fails).
struct GroupEditorView: View {
    @State var group: Server
    let isNew: Bool
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SlmList {
            Section {
                TextField("Название", text: $group.name)
                Picker("Режим", selection: Binding(get: { group.param("mode", "fastest") }, set: { group.params["mode"] = $0 })) {
                    Text("Самый быстрый").tag("fastest")
                    Text("Резерв").tag("fallback")
                }
            } footer: {
                Text("«Самый быстрый» каждые 2 минуты проверяет серверы и переключается на лучший. «Резерв» держится за текущий, пока тот не перестанет отвечать.")
            }
            .slmRow()
            Section("Серверы в группе") {
                ForEach(state.settings.servers.filter { $0.kind != "group" }) { s in
                    let on = group.members.contains(s.id)
                    Button {
                        if on { group.members.removeAll { $0 == s.id } } else { group.members.append(s.id) }
                    } label: {
                        HStack {
                            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Slm.accent2 : Slm.text3)
                            VStack(alignment: .leading) {
                                Text(s.title).foregroundStyle(Slm.text)
                                Text(ShareLinks.describe(s)).font(.caption).foregroundStyle(Slm.text2)
                            }
                        }
                    }
                }
            }
            .slmRow()
        }
        .navigationTitle(LocalizedStringKey(isNew ? "Новая группа" : "Группа"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    if isNew { state.add([group]) } else { state.update(group) }
                    dismiss()
                }
                .disabled(group.members.count < 2)
            }
        }
    }
}
