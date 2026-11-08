import Foundation

/// Speed on the main screen: byte counters of the utun interfaces (the tunnel), read once a second.
/// iOS keeps a few utun interfaces of its own, but they carry almost nothing next to the VPN.
@MainActor
final class TrafficMonitor: ObservableObject {
    @Published private(set) var down: UInt64 = 0
    @Published private(set) var up: UInt64 = 0
    @Published private(set) var totalDown: UInt64 = 0
    @Published private(set) var totalUp: UInt64 = 0

    private var timer: Timer?
    private var start: (UInt64, UInt64)?
    private var last: (UInt64, UInt64)?

    func run(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        start = nil
        last = nil
        down = 0; up = 0; totalDown = 0; totalUp = 0
        guard on else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = Self.counters()
        if start == nil { start = now }
        if let last { down = now.0 &- last.0; up = now.1 &- last.1 }
        if let start { totalDown = now.0 &- start.0; totalUp = now.1 &- start.1 }
        last = now
    }

    /// (received, sent) over all utun interfaces.
    nonisolated static func counters() -> (UInt64, UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let a = cur.pointee
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: a.ifa_name).hasPrefix("utun"), let data = a.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
            p = a.ifa_next
        }
        return (rx, tx)
    }
}

func human(_ bytes: UInt64) -> String {
    let units = [L("Б"), L("КБ"), L("МБ"), L("ГБ"), L("ТБ")]
    var v = Double(bytes)
    var i = 0
    while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
    return i == 0 ? "\(bytes) \(units[0])" : String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
}
