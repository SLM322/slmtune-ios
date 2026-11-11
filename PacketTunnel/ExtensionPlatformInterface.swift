import Foundation
import Libbox
import Network
import NetworkExtension
import UserNotifications

/// What sing-box asks of the platform (libbox PlatformInterface, sing-box 1.14). Modelled on sing-box for
/// Apple's ExtensionPlatformInterface (GPL-3.0). The Go interface is in
/// sing-box/experimental/libbox/platform.go; gomobile turns it into `LibboxPlatformInterfaceProtocol`.
/// If a newer libbox adds or renames a method, Xcode lists it — compare with Libbox.objc.h.
final class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private weak var tunnel: PacketTunnelProvider?
    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "slmtune.path")
    private var currentPath: Network.NWPath?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        monitor?.cancel()
        monitor = nil
    }

    private func fail(_ m: String) -> NSError {
        NSError(domain: "SLMtune", code: 2, userInfo: [NSLocalizedDescriptionKey: m])
    }

    // MARK: TUN

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let ret0_, let tunnel else { throw fail("openTun: no options") }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            let dnsIt = try options.getDNSServerAddress()
            var dnsServers: [String] = []
            while dnsIt.hasNext() { dnsServers.append(dnsIt.next()) }
            let dns = NEDNSSettings(servers: dnsServers)
            dns.matchDomains = [""] // every name goes to sing-box's DNS (hijack-dns)
            dns.matchDomainsNoSearch = true
            settings.dnsSettings = dns

            var v4: [String] = [], v4Masks: [String] = []
            if let it = options.getInet4Address() {
                while it.hasNext() { if let p = it.next() { v4.append(p.address()); v4Masks.append(p.mask()) } }
            }
            if !v4.isEmpty {
                let ipv4 = NEIPv4Settings(addresses: v4, subnetMasks: v4Masks)
                var routes: [NEIPv4Route] = []
                if let it = options.getInet4RouteAddress(), it.hasNext() {
                    while it.hasNext() { if let p = it.next() { routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) } }
                } else {
                    routes.append(NEIPv4Route.default())
                }
                ipv4.includedRoutes = routes
                var excluded: [NEIPv4Route] = []
                if let it = options.getInet4RouteExcludeAddress() {
                    while it.hasNext() { if let p = it.next() { excluded.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) } }
                }
                ipv4.excludedRoutes = excluded
                settings.ipv4Settings = ipv4
            }

            var v6: [String] = [], v6Prefixes: [NSNumber] = []
            if let it = options.getInet6Address() {
                while it.hasNext() { if let p = it.next() { v6.append(p.address()); v6Prefixes.append(NSNumber(value: p.prefix())) } }
            }
            if !v6.isEmpty {
                let ipv6 = NEIPv6Settings(addresses: v6, networkPrefixLengths: v6Prefixes)
                var routes: [NEIPv6Route] = []
                if let it = options.getInet6RouteAddress(), it.hasNext() {
                    while it.hasNext() {
                        if let p = it.next() { routes.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix()))) }
                    }
                } else {
                    routes.append(NEIPv6Route.default())
                }
                ipv6.includedRoutes = routes
                var excluded: [NEIPv6Route] = []
                if let it = options.getInet6RouteExcludeAddress() {
                    while it.hasNext() {
                        if let p = it.next() { excluded.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix()))) }
                    }
                }
                ipv6.excludedRoutes = excluded
                settings.ipv6Settings = ipv6
            }
        }

        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxy.httpServer = server
            proxy.httpsServer = server
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            settings.proxySettings = proxy
        }

        // libbox calls this synchronously from Go: wait for the system to apply the settings.
        let done = DispatchSemaphore(value: 0)
        var applyError: Error?
        tunnel.setTunnelNetworkSettings(settings) { error in
            applyError = error
            done.signal()
        }
        done.wait()
        if let applyError { throw applyError }

        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let fd = LibboxGetTunnelFileDescriptor()
        guard fd != -1 else { throw fail("openTun: no utun file descriptor") }
        ret0_.pointee = fd
    }

    // MARK: Network

    /// false, as in sing-box for Apple: sing-box itself binds every outgoing socket to the physical interface
    /// (IP_BOUND_IF) reported by the monitor below. With true and an empty control nothing was bound, and
    /// connections to the server could be routed back into the tunnel.
    func usePlatformAutoDetectControl() -> Bool { false }

    func autoDetectControl(_ fd: Int32) throws {}

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let m = NWPathMonitor()
        monitor = m
        let first = DispatchSemaphore(value: 0)
        var signalled = false
        m.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
            self?.report(path, to: listener)
            if !signalled { signalled = true; first.signal() }
        }
        m.start(queue: monitorQueue)
        _ = first.wait(timeout: .now() + 3)
    }

    private func report(_ path: Network.NWPath, to listener: LibboxInterfaceUpdateListenerProtocol) {
        guard path.status != .unsatisfied, let iface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(iface.name, interfaceIndex: Int32(iface.index),
                                        isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        monitor?.cancel()
        monitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let path = currentPath else { return InterfaceIterator([]) }
        let list: [LibboxNetworkInterface] = path.availableInterfaces.map { i in
            let n = LibboxNetworkInterface()
            n.name = i.name
            n.index = Int32(i.index)
            switch i.type {
            case .wifi: n.type = LibboxInterfaceTypeWIFI
            case .cellular: n.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: n.type = LibboxInterfaceTypeEthernet
            default: n.type = LibboxInterfaceTypeOther
            }
            n.metered = path.isExpensive
            // The core walks these iterators: never leave them nil.
            n.addresses = StringIterator([])
            n.dnsServer = StringIterator([])
            n.gateway = StringIterator([])
            return n
        }
        return InterfaceIterator(list)
    }

    func underNetworkExtension() -> Bool { true }

    func includeAllNetworks() -> Bool {
        (tunnel?.protocolConfiguration as? NETunnelProviderProtocol)?.includeAllNetworks ?? false
    }

    /// iOS has no API to flush the system resolver; re-applying the network settings would drop connections.
    func clearDNSCache() {}

    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }

    func readWIFIState() -> LibboxWIFIState? {
        // Needs the "Access Wi-Fi Information" entitlement; a configured VPN app may read the SSID.
        let done = DispatchSemaphore(value: 0)
        var state: LibboxWIFIState?
        NEHotspotNetwork.fetchCurrent { net in
            if let net { state = LibboxNewWIFIState(net.ssid, net.bssid) }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
        return state
    }

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                             destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw fail("iOS does not tell which app owns a connection")
    }

    func registerMyInterface(_ name: String?) {}

    // MARK: Notifications (rule-set updates, errors)

    func send(_ notification: LibboxNotification?) throws {
        guard let notification else { return }
        let c = UNMutableNotificationContent()
        c.title = notification.title
        c.subtitle = notification.subtitle
        c.body = notification.body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notification.identifier, content: c, trigger: nil))
    }

    func cancelNotification(_ identifier: String?, typeID: Int32) throws {
        if let identifier { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier]) }
    }

    // MARK: Not available on iOS

    func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}
    func closeNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}
    func usePlatformShell() -> Bool { false }
    func checkPlatformShell() throws { throw fail("not supported") }
    func openShellSession(_ user: LibboxPlatformUser?, command: String?, environ: LibboxStringIteratorProtocol?,
                          term: String?, rows: Int32, cols: Int32) throws -> LibboxShellSessionProtocol {
        throw fail("not supported")
    }
    func lookupUser(_ username: String?) throws -> LibboxPlatformUser { throw fail("not supported") }
    // (string, error) Go methods come in as an error pointer, not `throws`.
    func lookupSFTPServer(_ error: NSErrorPointer) -> String { error?.pointee = fail("not supported"); return "" }
    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String { error?.pointee = fail("not supported"); return "" }
    func tailscaleHostname() -> String { "SLMtune-iPhone" }
    func usePlatformBridge() -> Bool { false }
    func createBridge(_ options: LibboxBridgeOptions?) throws -> LibboxBridgeSessionProtocol { throw fail("not supported") }
}

final class StringIterator: NSObject, LibboxStringIteratorProtocol {
    private var items: [String]
    init(_ items: [String]) { self.items = items }
    func len() -> Int32 { Int32(items.count) }
    func hasNext() -> Bool { !items.isEmpty }
    func next() -> String { items.isEmpty ? "" : items.removeFirst() }
}

private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var items: [LibboxNetworkInterface]
    init(_ items: [LibboxNetworkInterface]) { self.items = items }
    func hasNext() -> Bool { !items.isEmpty }
    func next() -> LibboxNetworkInterface? { items.isEmpty ? nil : items.removeFirst() }
}
