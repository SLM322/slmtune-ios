#!/usr/bin/env bash
# Builds VpnClientFramework.xcframework (AdGuard's TrustTunnel client, C++) with SLMtune's SOCKS bridge
# (TrustTunnelBridge/TTSocksClient) and puts it in Frameworks/. Runs on a Mac.
#
# Needs (from TrustTunnelClient's DEVELOPMENT.md): Xcode, CMake ≥ 3.24, Conan ≥ 2.0.5, Rust ≥ 1.85,
# Python ≥ 3.13, CocoaPods:  brew install cmake conan python cocoapods && curl https://sh.rustup.rs -sSf | sh
#
#   bash scripts/build-trusttunnel.sh            # latest release
#   TT_REF=v1.3.0 bash scripts/build-trusttunnel.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$ROOT/.build/TrustTunnelClient}"
REF="${TT_REF:-$(curl -s https://api.github.com/repos/TrustTunnel/TrustTunnelClient/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')}"
[ -n "$REF" ] || { echo "Не удалось узнать версию TrustTunnelClient; задайте TT_REF"; exit 1; }

for tool in cmake conan cargo pod xcodebuild; do
  command -v "$tool" >/dev/null || { echo "Нет $tool — см. комментарий в начале скрипта"; exit 1; }
done

rm -rf "$WORK"
git clone --depth 1 --branch "$REF" https://github.com/TrustTunnel/TrustTunnelClient.git "$WORK"

APPLE="$WORK/platform/apple"
VC="$APPLE/VpnClient"
cp "$ROOT/TrustTunnelBridge/TTSocksClient.h" "$ROOT/TrustTunnelBridge/TTSocksClient.mm" "$VC/"

# Add the bridge to the framework: sources, public headers and the umbrella header.
python3 - "$VC" <<'PY'
import pathlib, sys
vc = pathlib.Path(sys.argv[1])
cm = vc / "CMakeLists.txt"
s = cm.read_text()
s = s.replace("    VpnClient.mm\n", "    VpnClient.mm\n    TTSocksClient.h\n    TTSocksClient.mm\n", 1)
s = s.replace('PUBLIC_HEADER "VpnClient.h;', 'PUBLIC_HEADER "VpnClient.h;TTSocksClient.h;', 1)
assert "TTSocksClient.mm" in s and "TTSocksClient.h;" in s, "CMakeLists.txt changed upstream: add TTSocksClient by hand"
cm.write_text(s)
h = vc / "VpnClient.h"
t = h.read_text()
if "TTSocksClient.h" not in t:
    t = t.replace('#import "DeepLink.h"', '#import "DeepLink.h"\n#import "TTSocksClient.h"', 1)
    h.write_text(t)
PY

cd "$APPLE"
pod install
xcodebuild -project TrustTunnelClient.xcodeproj -scheme VpnClientFramework -configuration Release \
  MARKETING_VERSION="${REF#v}" CURRENT_PROJECT_VERSION=1

mkdir -p "$ROOT/Frameworks"
rm -rf "$ROOT/Frameworks/VpnClientFramework.xcframework"
mv build/framework/VpnClientFramework.xcframework "$ROOT/Frameworks/"
echo "Готово: $ROOT/Frameworks/VpnClientFramework.xcframework (TrustTunnelClient $REF)"
