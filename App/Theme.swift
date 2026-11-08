import SwiftUI
import UIKit

/// The palette of the Windows app (App.xaml) and the Android one: ink background, magenta accent.
enum Slm {
    static let ink = Color(hex: 0x0B0B0D)
    static let card = Color(hex: 0x151518)
    static let card2 = Color(hex: 0x1C1C21)
    static let line = Color(hex: 0x2A2A30)
    static let tint = Color(hex: 0x2E0B2E)
    static let accent = Color(hex: 0xD100D1)
    static let accent2 = Color(hex: 0xFF3DFF)
    static let text = Color(hex: 0xF2F2F5)
    static let text2 = Color(hex: 0xA6A6B0)
    static let text3 = Color(hex: 0x6E6E78)
    static let ok = Color(hex: 0x34D399)
    static let okBg = Color(hex: 0x1E3A34)
    static let warn = Color(hex: 0xF5B83D)
    static let err = Color(hex: 0xFF5C7A)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// UIKit chrome (navigation and tab bars, lists) in the same colours.
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(ink)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(card)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UISwitch.appearance().onTintColor = UIColor(accent)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A grouped list in SLMtune colours.
struct SlmList<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        List { content() }
            .scrollContentBackground(.hidden)
            .background(Slm.ink)
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(LocalizedStringKey(text)).font(.footnote).foregroundStyle(Slm.text3)
    }
}

extension View {
    /// Rows in the card colour of the Windows app.
    func slmRow() -> some View { listRowBackground(Slm.card) }
}

/// The big round connect button: grey when off, the magenta gradient when on, pulsing while connecting.
struct PowerButton: View {
    let on: Bool
    let busy: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(on ? AnyShapeStyle(Slm.gradient) : AnyShapeStyle(Slm.card2))
                    .frame(width: 168, height: 168)
                    .shadow(color: on ? Slm.accent.opacity(0.55) : .clear, radius: 28)
                Circle()
                    .stroke(on ? Slm.accent2 : Slm.line, lineWidth: 2)
                    .frame(width: 190, height: 190)
                    .scaleEffect(busy && pulse ? 1.12 : 1)
                    .opacity(busy && pulse ? 0.2 : 1)
                Image(systemName: "power")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(on ? .white : Slm.text2)
            }
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
        .accessibilityLabel(Text(LocalizedStringKey(on ? "Отключить" : "Подключить")))
    }
}
