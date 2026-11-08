import SwiftUI

/// Соединения: the live list from sing-box's Clash API inside the extension (127.0.0.1, with a secret),
/// the same data as the Windows Connections window. Swipe to close one.
struct ConnectionsView: View {
    @EnvironmentObject var vpn: VPNController
    @State private var list: [Conn] = []
    @State private var totals = (up: Int64(0), down: Int64(0))
    @State private var error: String?
    @State private var filter = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct Conn: Identifiable, Hashable {
        let id: String
        let host: String
        let network: String
        let chain: String
        let rule: String
        let up: Int64
        let down: Int64
        let start: Date?
    }

    private var shown: [Conn] {
        filter.isEmpty ? list : list.filter { $0.host.localizedCaseInsensitiveContains(filter) || $0.chain.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        SlmList {
            if vpn.status != .connected {
                Text("VPN выключен — соединений нет.").foregroundStyle(Slm.text2).slmRow()
            } else if let error {
                Text(error).foregroundStyle(Slm.err).slmRow()
            } else {
                Section {
                    LabeledContent(L("Всего"), value: "↓ \(human(UInt64(max(0, totals.down))))  ↑ \(human(UInt64(max(0, totals.up))))")
                    LabeledContent(L("Открыто"), value: "\(list.count)")
                }
                .slmRow()
                Section {
                    ForEach(shown) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.host).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(c.network.uppercased()).font(.caption2).foregroundStyle(Slm.text3)
                            }
                            HStack(spacing: 8) {
                                Text(c.chain).font(.caption).foregroundStyle(c.chain == "direct" ? Slm.text2 : Slm.accent2)
                                if !c.rule.isEmpty { Text(c.rule).font(.caption2).foregroundStyle(Slm.text3).lineLimit(1) }
                                Spacer()
                                Text("↓\(human(UInt64(max(0, c.down)))) ↑\(human(UInt64(max(0, c.up))))").font(.caption2.monospacedDigit()).foregroundStyle(Slm.text2)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await close(c.id) } } label: { Label("Закрыть", systemImage: "xmark") }
                        }
                    }
                }
                .slmRow()
            }
        }
        .searchable(text: $filter, prompt: Text("Сайт или сервер"))
        .navigationTitle("Соединения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(role: .destructive) { Task { await close(nil) } } label: { Image(systemName: "xmark.circle") }
                .disabled(list.isEmpty)
        }
        .onReceive(timer) { _ in Task { await reload() } }
        .task { await reload() }
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(AppGroup.clashPort)\(path)")!, timeoutInterval: 3)
        r.httpMethod = method
        r.setValue("Bearer \(AppGroup.clashSecret)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func reload() async {
        guard vpn.status == .connected else { list = []; return }
        do {
            let (data, _) = try await URLSession.shared.data(for: request("/connections"))
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let conns = (root["connections"] as? [[String: Any]] ?? []).map { c -> Conn in
                let m = c["metadata"] as? [String: Any] ?? [:]
                let host = (m["host"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (m["destinationIP"] as? String ?? "?")
                let port = m["destinationPort"] as? String ?? ""
                let chains = (c["chains"] as? [String] ?? []).reversed().joined(separator: " → ")
                return Conn(id: c["id"] as? String ?? UUID().uuidString, host: port.isEmpty ? host : "\(host):\(port)",
                            network: m["network"] as? String ?? "", chain: chains.isEmpty ? "?" : chains,
                            rule: c["rule"] as? String ?? "", up: (c["upload"] as? NSNumber)?.int64Value ?? 0,
                            down: (c["download"] as? NSNumber)?.int64Value ?? 0, start: (c["start"] as? String).flatMap(iso.date))
            }
            list = conns.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
            totals = ((root["uploadTotal"] as? NSNumber)?.int64Value ?? 0, (root["downloadTotal"] as? NSNumber)?.int64Value ?? 0)
            error = nil
        } catch {
            self.error = L("Не удалось получить соединения: %@", error.localizedDescription)
        }
    }

    private func close(_ id: String?) async {
        _ = try? await URLSession.shared.data(for: request(id.map { "/connections/\($0)" } ?? "/connections", method: "DELETE"))
        await reload()
    }
}
