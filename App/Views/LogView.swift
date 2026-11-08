import SwiftUI

/// Журнал: sing-box, the extra cores and Tor, from the App Group log files the extension writes.
struct LogView: View {
    @State private var lines: [LogLine] = []
    @State private var filter = ""
    @State private var onlyProblems = false
    @State private var follow = true
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var shown: [LogLine] {
        lines.filter { l in
            (!onlyProblems || l.level != "info") && (filter.isEmpty || l.text.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(shown) { l in
                Text(l.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(l.level == "error" ? Slm.err : (l.level == "warn" ? Slm.warn : Slm.text2))
                    .textSelection(.enabled)
                    .listRowBackground(Slm.ink)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .id(l.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Slm.ink)
            .searchable(text: $filter, prompt: Text("Поиск в журнале"))
            .onReceive(timer) { _ in
                reload()
                if follow, let last = shown.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear { reload() }
        }
        .navigationTitle("Журнал")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Toggle("Только ошибки и предупреждения", isOn: $onlyProblems)
                    Toggle("Следить за концом", isOn: $follow)
                    ShareLink(item: shown.map(\.text).joined(separator: "\n")) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { SharedLog.clear(); lines = [] } label: { Label("Очистить", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func reload() {
        let fresh = SharedLog.tail()
        // Keep ids stable when nothing changed, so the list doesn't jump.
        if fresh.map(\.text) != lines.map(\.text) { lines = fresh }
    }
}
