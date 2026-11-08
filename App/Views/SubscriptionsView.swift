import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false

    var body: some View {
        SlmList {
            Section {
                TextField("https://…", text: $url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    let u = url.trimmingCharacters(in: .whitespaces)
                    url = ""
                    Task { busy = true; await state.addSubscription(url: u); busy = false }
                } label: { Label("Добавить подписку", systemImage: "plus") }
                .disabled(!(url.hasPrefix("https://") || url.hasPrefix("http://")) || busy)
            } footer: {
                Text("Ссылка от провайдера (Marzban, 3x-ui, Remnawave и др.). Показывается остаток трафика и срок, если панель их сообщает.")
            }
            .slmRow()

            if !state.settings.subscriptions.isEmpty {
                Section("Подписки") {
                    ForEach($state.settings.subscriptions) { $sub in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sub.name.isEmpty ? sub.url : sub.name).font(.headline)
                                Spacer()
                                Text(L("%d серв.", sub.count)).font(.caption).foregroundStyle(Slm.text2)
                            }
                            let info = Subscriptions.describe(sub)
                            if !info.isEmpty { Text(info).font(.caption).foregroundStyle(Slm.accent2) }
                            if let e = sub.lastError { Text(e).font(.caption).foregroundStyle(Slm.err) }
                            if let d = sub.lastUpdate {
                                Text(L("Обновлено: %@", d.formatted(date: .abbreviated, time: .shortened))).font(.caption2).foregroundStyle(Slm.text3)
                            }
                            Toggle("Обновлять автоматически", isOn: $sub.autoUpdate).font(.footnote)
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(sub) } label: { Label("Удалить", systemImage: "trash") }
                            Button { Task { var s = sub; busy = true; await state.refresh(&s); busy = false } } label: {
                                Label("Обновить", systemImage: "arrow.clockwise")
                            }.tint(Slm.accent)
                        }
                    }
                }
                .slmRow()
            }
        }
        .navigationTitle("Подписки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { Task { busy = true; await state.refreshAll(includeManual: true); busy = false } } label: {
                    if busy { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(state.settings.subscriptions.isEmpty || busy)
            }
        }
    }

    private func delete(_ sub: Subscription) {
        let ids = Set(state.settings.servers.filter { $0.subscriptionId == sub.id }.map(\.id))
        state.remove(ids)
        state.settings.subscriptions.removeAll { $0.id == sub.id }
    }
}
