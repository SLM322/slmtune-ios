import SwiftUI

@main
struct SLMtuneApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var phase

    init() { Slm.applyAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(state.vpn)
                .preferredColorScheme(.dark)
                .tint(Slm.accent)
                // slmtune://, and vless:// / vmess:// / … when iOS hands such a link to the app.
                .onOpenURL { url in
                    // slmtune://toggle | connect | disconnect — from the widget; everything else is an import.
                    switch url.scheme == "slmtune" ? url.host?.lowercased() : nil {
                    case "toggle": Task { state.vpn.isOn ? await state.vpn.disconnect() : await state.vpn.connect(state.settings) }
                    case "connect": Task { await state.vpn.connect(state.settings) }
                    case "disconnect": Task { await state.vpn.disconnect() }
                    default: state.importText(url.absoluteString)
                    }
                }
        }
        .onChange(of: phase) { p in
            guard p == .active else { return }
            Task {
                await state.updateLists()
                // Subscriptions are refreshed at most every 12 hours when the app comes to the front.
                if state.settings.subscriptions.contains(where: { $0.autoUpdate && ($0.lastUpdate ?? .distantPast) < Date().addingTimeInterval(-43_200) }) {
                    await state.refreshAll()
                }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            HomeView().tabItem { Label("Главная", systemImage: "power.circle") }
            NavigationStack { ServersView() }.tabItem { Label("Серверы", systemImage: "server.rack") }
            NavigationStack { RoutingView() }.tabItem { Label("Маршруты", systemImage: "arrow.triangle.branch") }
            NavigationStack { SettingsView() }.tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .overlay(alignment: .bottom) {
            if let t = state.toast {
                Text(t)
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Slm.card2, in: Capsule())
                    .overlay(Capsule().stroke(Slm.line))
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { state.toast = nil }
            }
        }
        .animation(.spring(response: 0.3), value: state.toast)
        .alert("Добавить подписку?", isPresented: Binding(
            get: { state.pendingSubscriptionURL != nil },
            set: { if !$0 { state.pendingSubscriptionURL = nil } })
        ) {
            Button("Добавить") {
                if let u = state.pendingSubscriptionURL { Task { await state.addSubscription(url: u) } }
                state.pendingSubscriptionURL = nil
            }
            Button("Отмена", role: .cancel) { state.pendingSubscriptionURL = nil }
        } message: {
            Text(state.pendingSubscriptionURL ?? "")
        }
    }
}
