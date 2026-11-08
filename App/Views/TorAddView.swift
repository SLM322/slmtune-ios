import SwiftUI

/// Tor as a server: tor runs inside the VPN extension, with bridges through the built-in transports.
struct TorAddView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var transport = "snowflake"
    @State private var bridges = ""

    private var needsBridges: Bool { transport == "custom" || transport == "webtunnel" }

    var body: some View {
        NavigationStack {
            SlmList {
                Section {
                    Picker("Мосты", selection: $transport) {
                        ForEach(MoreLinks.torTransports, id: \.id) { t in
                            Text(LocalizedStringKey(t.title)).tag(t.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Как подключаться к Tor")
                } footer: {
                    Text("Tor медленнее обычного VPN и первый раз подключается до пары минут. Сайты видят адрес выходного узла Tor; часть сайтов его блокирует.")
                }
                .slmRow()
                if needsBridges {
                    Section {
                        TextEditor(text: $bridges)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 120)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: {
                        Text("Мосты (по одному на строку)")
                    } footer: {
                        Text("Возьмите на bridges.torproject.org или у Telegram-бота @GetBridgesBot. Поддерживаются obfs4, webtunnel, snowflake и meek.")
                    }
                    .slmRow()
                }
            }
            .navigationTitle("Tor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        state.add([MoreLinks.torProfile(transport: transport, bridges: bridges)])
                        dismiss()
                    }
                    .disabled(needsBridges && bridges.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
