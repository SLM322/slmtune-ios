#!/usr/bin/env bash
# Builds Libbox.xcframework with gomobile and puts it in Frameworks/. Runs on a Mac with Xcode and Go ≥ 1.26.
#
# One framework, one Go runtime (two gomobile frameworks can't be linked into one process):
#   - github.com/sagernet/sing-box/experimental/libbox  — sing-box 1.14.4 (same as the Android build)
#   - github.com/slmtune/slmtune-ios/core (core/)        — Xray, mihomo (AmneziaWG, mieru, SSR), Tor transports
# Versions are pinned in core/go.mod. Tags are sing-box's own build_libbox tags for Apple.
#
#   bash scripts/build-libbox.sh
#   PLATFORMS=ios bash scripts/build-libbox.sh       # device only, faster
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORMS="${PLATFORMS:-ios,iossimulator}"
GOMOBILE_VERSION="v0.1.13"

command -v go >/dev/null || { echo "Go не найден: brew install go"; exit 1; }
command -v xcodebuild >/dev/null || { echo "Нужен Xcode"; exit 1; }

go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION"
go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION"
export PATH="$(go env GOPATH)/bin:$PATH"

SING_BOX_VERSION="$(cd "$ROOT/core" && go list -m -f '{{.Version}}' github.com/sagernet/sing-box)"
TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_naive_outbound,with_clash_api,badlinkname,tfogo_checklinkname0"
# no_tailscale: mihomo's own Tailscale fork (metacubex/tailscale) registers the same expvar names as sing-box's
# (sagernet/tailscale) — together they panic in init and the extension dies at launch.
TAGS="$TAGS,with_dhcp,grpcnotrace,with_low_memory,no_tailscale"
LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=${SING_BOX_VERSION#v} -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

# LITE=1: sing-box alone (no Xray / mihomo / Tor transports) — a much smaller extension; build the app with
# SWIFT_ACTIVE_COMPILATION_CONDITIONS=SLM_LITE.
PACKAGES="github.com/sagernet/sing-box/experimental/libbox github.com/slmtune/slmtune-ios/core"
if [ "${LITE:-0}" = "1" ]; then PACKAGES="github.com/sagernet/sing-box/experimental/libbox"; fi

mkdir -p "$ROOT/Frameworks"
rm -rf "$ROOT/Frameworks/Libbox.xcframework"
cd "$ROOT/core"
gomobile bind -v \
  -target "$PLATFORMS" \
  -libname=box \
  -iosversion=15.0 \
  -trimpath -buildvcs=false \
  -tags "$TAGS" \
  -ldflags "$LDFLAGS" \
  -o "$ROOT/Frameworks/Libbox.xcframework" \
  $PACKAGES

echo "Готово: $ROOT/Frameworks/Libbox.xcframework (sing-box $SING_BOX_VERSION; пакеты: $PACKAGES)"
echo "Сверьте протоколы: $ROOT/Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework/Headers/"
