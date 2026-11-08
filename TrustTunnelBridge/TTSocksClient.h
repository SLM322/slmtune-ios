// TrustTunnel in SOCKS mode for SLMtune: the AdGuard client listens on 127.0.0.1 (listener.socks in the TOML)
// and sing-box routes to it, like trusttunnel_client.exe in the Windows version.
// scripts/build-trusttunnel.sh copies this file into TrustTunnelClient/platform/apple/VpnClient and adds it to
// VpnClientFramework, next to the stock VpnClient (which only knows the TUN mode).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TTSocksStateHandler)(int state);

@interface TTSocksClient : NSObject

/// `config` is a trusttunnel_client TOML with [listener.socks]. nil if it doesn't parse.
- (nullable instancetype)initWithConfig:(NSString *)config stateHandler:(TTSocksStateHandler)stateHandler;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)start;
- (void)stop;
- (void)notifySleep;
- (void)notifyWake;

@end

NS_ASSUME_NONNULL_END
