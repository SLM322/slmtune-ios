// See TTSocksClient.h. Mirrors VpnClient.mm of TrustTunnelClient (Apache-2.0), with AutoSetup + SOCKS listener
// instead of UseProcessPackets + TUN. Socket protection and certificate checks are the same as there.
#import "TTSocksClient.h"
#import "vpn/trusttunnel/auto_network_monitor.h"
#import "vpn/trusttunnel/client.h"
#import "net/network_manager.h"
#import "common/socket_address.h"

#import "toml++/toml.h"

#import <Security/Security.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netinet/in.h>

static ag::Logger g_tt_logger("TT_SOCKS");

NS_ASSUME_NONNULL_BEGIN

static ag::SocketAddress tt_interface_address(const char *if_name, int family) {
    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) == 0) {
        for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == NULL || 0 != strcmp(ifa->ifa_name, if_name)) {
                continue;
            }
            if (ifa->ifa_addr->sa_family == family) {
                ag::SocketAddress sa{ifa->ifa_addr};
                if (family == AF_INET6 && sa.addr()[0] == 0xfe && sa.addr()[1] == 0x80) {
                    continue;
                }
                freeifaddrs(ifaddr);
                return sa;
            }
        }
        freeifaddrs(ifaddr);
    }
    return {};
}

/// Binds the client's sockets to the physical interface, so they never enter SLMtune's own tunnel.
static bool tt_protect(ag::SocketProtectEvent *event) {
    char if_name[IF_NAMESIZE] = "not set";
    uint32_t idx = ag::vpn_network_manager_get_outbound_interface();
    if (idx == 0) {
        return true; // the extension's own sockets bypass its tunnel anyway
    }
    if (!if_indextoname(idx, if_name)) {
        return false;
    }
    int family = event->peer->sa_family;
    int level = family == AF_INET ? IPPROTO_IP : IPPROTO_IPV6;
    int opt = family == AF_INET ? IP_BOUND_IF : IPV6_BOUND_IF;
    if (setsockopt(event->fd, level, opt, &idx, sizeof(idx)) != 0) {
        return false;
    }
    if (auto sa = tt_interface_address(if_name, family); sa.valid()) {
        return bind(event->fd, sa.c_sockaddr(), sa.c_socklen()) == 0;
    }
    return false;
}

static _Nullable SecCertificateRef tt_certificate(X509 *cert) {
    unsigned char *buffer = NULL;
    int len = i2d_X509(cert, &buffer);
    if (len < 0) {
        return NULL;
    }
    NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)buffer
                                                length:len
                                           deallocator:^void(void *bytes, NSUInteger length) {
                                               OPENSSL_free(bytes);
                                           }];
    return SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
}

static bool tt_verify(const ag::VpnVerifyCertificateEvent *event) {
    SecCertificateRef cert = tt_certificate(event->cert);
    if (!cert) {
        return false;
    }
    NSMutableArray *chain = [NSMutableArray arrayWithObject:(__bridge_transfer id)cert];
    int n = sk_X509_num(event->chain);
    for (int i = 0; i < n; ++i) {
        SecCertificateRef c = tt_certificate(sk_X509_value(event->chain, i));
        if (!c) {
            return false;
        }
        [chain addObject:(__bridge_transfer id)c];
    }
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecTrustRef trust = NULL;
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)chain, policy, &trust);
    if (policy) {
        CFRelease(policy);
    }
    if (status != errSecSuccess || trust == NULL) {
        if (trust) {
            CFRelease(trust);
        }
        return false;
    }
    SecTrustSetAnchorCertificatesOnly(trust, false);
    bool ok = SecTrustEvaluateWithError(trust, NULL);
    CFRelease(trust);
    return ok;
}

@interface TTSocksClient () {
    std::unique_ptr<ag::TrustTunnelClient> _client;
    std::unique_ptr<ag::AutoNetworkMonitor> _monitor;
}
@end

@implementation TTSocksClient

- (nullable instancetype)initWithConfig:(NSString *)config stateHandler:(TTSocksStateHandler)stateHandler {
    self = [super init];
    if (!self) {
        return nil;
    }
    toml::parse_result parsed = toml::parse(config.UTF8String);
    if (!parsed) {
        errlog(g_tt_logger, "Failed to parse configuration: {}", parsed.error().description());
        return nil;
    }
    auto cfg = ag::TrustTunnelConfig::build_config(parsed);
    if (!cfg) {
        return nil;
    }
    if (!std::holds_alternative<ag::TrustTunnelConfig::SocksListener>(cfg->listener)) {
        errlog(g_tt_logger, "The configuration has no [listener.socks]");
        return nil;
    }
    ag::vpn_post_quantum_group_set_enabled(cfg->post_quantum_group_enabled);
    ag::VpnCallbacks callbacks = {
        .protect_handler = [](ag::SocketProtectEvent *event) {
            event->result = tt_protect(event) ? 0 : -1;
        },
        .verify_handler = [](ag::VpnVerifyCertificateEvent *event) {
            event->result = tt_verify(event) ? 0 : -1;
        },
        .state_changed_handler = [stateHandler](ag::VpnStateChangedEvent *event) {
            stateHandler((int)event->state);
        },
    };
    _client = std::make_unique<ag::TrustTunnelClient>(std::move(*cfg), std::move(callbacks));
    _monitor = std::make_unique<ag::AutoNetworkMonitor>(_client.get(), std::string{});
    if (!_monitor->start()) {
        errlog(g_tt_logger, "Failed to start network monitor");
        return nil;
    }
    return self;
}

- (void)dealloc {
    if (_monitor) {
        _monitor->stop();
    }
}

- (BOOL)start {
    auto error = _client->connect(ag::TrustTunnelClient::AutoSetup{}, ag::TrustTunnelClient::ConnectOptions{});
    if (error) {
        errlog(g_tt_logger, "Failed to connect: {}", error->pretty_str());
        return NO;
    }
    return YES;
}

- (void)stop {
    _client->disconnect();
}

- (void)notifySleep {
    _client->notify_sleep();
}

- (void)notifyWake {
    _client->notify_wake();
}

@end

NS_ASSUME_NONNULL_END
