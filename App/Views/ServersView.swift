import PhotosUI
import SwiftUI

struct ServersView: View {
    var picker = false
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var showPaste = false
    @State private var showSubscriptions = false
    @State private var newGroup: Server?
    @State private var showTor = false
    @State private var photo: PhotosPickerItem?
    @State private var showPhoto = false
    @State private var pinging = false

    var body: some View {
        content
            .navigationTitle("Серверы")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { Task { pinging = true; await state.pingAll(); pinging = false } } label: {
                        if pinging { ProgressView() } else { Label("Пинг", systemImage: "speedometer") }
                    }
                    .disabled(state.settings.servers.isEmpty || pinging)
                }
                ToolbarItem(placement: .navigationBarTrailing) { addMenu }
                if picker {
                    ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { text in
                    showScanner = false
                    state.importText(text)
                }
            }
            .sheet(isPresented: $showPaste) { PasteLinksView() }
            .sheet(isPresented: $showTor) { TorAddView() }
            .sheet(isPresented: $showSubscriptions) { NavigationStack { SubscriptionsView() } }
            .sheet(item: $newGroup) { g in NavigationStack { GroupEditorView(group: g, isNew: true) } }
            .photosPicker(isPresented: $showPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let text = QRCode.decode(imageData: data) {
                        state.importText(text)
                    } else {
                        state.show(L("На картинке нет QR-кода."))
                    }
                    photo = nil
                }
            }
    }

    @ViewBuilder private var content: some View {
        if state.settings.servers.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "server.rack").font(.system(size: 44)).foregroundStyle(Slm.accent2)
                Text("Серверов пока нет").font(.headline)
                Text("Скопируйте ссылку vless://, ss://, hysteria2:// … или ссылку на подписку и нажмите «Из буфера», либо отсканируйте QR-код.")
                    .font(.subheadline).foregroundStyle(Slm.text2).multilineTextAlignment(.center)
                HStack {
                    Button { pasteFromClipboard() } label: { Label("Из буфера", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.borderedProminent)
                    Button { showScanner = true } label: { Label("QR-код", systemImage: "qrcode.viewfinder") }
                        .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Slm.ink)
        } else {
            SlmList {
                ForEach(sections, id: \.id) { sec in
                    Section {
                        ForEach(sec.servers) { s in row(s) }
                            .onDelete { idx in state.remove(Set(idx.map { sec.servers[$0].id })) }
                    } header: {
                        if !sec.title.isEmpty { Text(sec.title) }
                    } footer: {
                        if !sec.footer.isEmpty { Text(sec.footer) }
                    }
                }
            }
        }
    }

    private struct Sec { let id: String; let title: String; let footer: String; let servers: [Server] }

    private var sections: [Sec] {
        let all = state.settings.servers
        var out = [Sec(id: "own", title: "", footer: "", servers: all.filter { $0.subscriptionId.isEmpty })]
        for sub in state.settings.subscriptions {
            out.append(Sec(id: sub.id, title: sub.name, footer: Subscriptions.describe(sub), servers: all.filter { $0.subscriptionId == sub.id }))
        }
        return out.filter { !$0.servers.isEmpty }
    }

    private func row(_ s: Server) -> some View {
        let active = s.id == state.activeServer?.id
        return HStack(spacing: 12) {
            Image(systemName: active ? "checkmark.circle.fill" : (s.kind == "group" ? "square.stack.3d.up" : "circle"))
                .foregroundStyle(active ? Slm.accent2 : Slm.text3)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).foregroundStyle(Slm.text).lineLimit(1)
                Text(ShareLinks.describe(s) + (s.viaId.isEmpty ? "" : " · " + L("каскад")))
                    .font(.caption).foregroundStyle(Slm.text2).lineLimit(1)
            }
            Spacer()
            ping(s.pingMs)
            NavigationLink { ServerDetailView(id: s.id) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.select(s)
            if picker { dismiss() }
        }
        .slmRow()
    }

    @ViewBuilder private func ping(_ ms: Int) -> some View {
        switch ms {
        case -1: EmptyView()
        case -2: Text("нет ответа").font(.caption).foregroundStyle(Slm.err)
        case -3: Text("UDP").font(.caption).foregroundStyle(Slm.text3)
        default: Text(L("%d мс", ms)).font(.caption.monospacedDigit()).foregroundStyle(ms < 150 ? Slm.ok : (ms < 400 ? Slm.warn : Slm.err))
        }
    }

    private var addMenu: some View {
        Menu {
            Button { pasteFromClipboard() } label: { Label("Из буфера обмена", systemImage: "doc.on.clipboard") }
            Button { showScanner = true } label: { Label("Сканировать QR-код", systemImage: "qrcode.viewfinder") }
            Button { showPhoto = true } label: { Label("QR-код из фото", systemImage: "photo") }
            Button { showPaste = true } label: { Label("Вставить ссылки", systemImage: "text.badge.plus") }
            Button { showTor = true } label: { Label("Tor", systemImage: "network.badge.shield.half.filled") }
            Divider()
            Button { showSubscriptions = true } label: { Label("Подписки", systemImage: "arrow.triangle.2.circlepath") }
            Button {
                newGroup = Server(name: L("Группа"), kind: "group", server: "group", port: 1)
            } label: { Label("Группа серверов", systemImage: "square.stack.3d.up") }
            .disabled(state.settings.servers.filter { $0.kind != "group" }.count < 2)
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3)
        }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            state.show(L("Буфер обмена пуст."))
            return
        }
        state.importText(text)
    }
}

struct PasteLinksView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Slm.card, in: RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Hint("По одной ссылке на строку, ссылка на подписку, slmtune:// или конфиг WireGuard ([Interface] … [Peer]).")
            }
            .padding()
            .background(Slm.ink)
            .navigationTitle("Вставить ссылки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { state.importText(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
