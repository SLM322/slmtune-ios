#!/usr/bin/env bash
# One command on a Mac: tools → cores → Xcode project.
#   bash scripts/bootstrap.sh && open SLMtune.xcodeproj
#   WITH_TRUSTTUNNEL=1 bash scripts/bootstrap.sh     # also build AdGuard's TrustTunnel client (needs conan, rust, cmake)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v brew >/dev/null || { echo "Установите Homebrew: https://brew.sh"; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen
command -v go >/dev/null || brew install go

[ -d Frameworks/Libbox.xcframework ] || bash scripts/build-libbox.sh
if [ "${WITH_TRUSTTUNNEL:-0}" = 1 ] && [ ! -d Frameworks/VpnClientFramework.xcframework ]; then
  bash scripts/build-trusttunnel.sh
fi

if [ -d Frameworks/VpnClientFramework.xcframework ]; then
  cp Config/trusttunnel.yml Config/optional.yml
  echo "TrustTunnel: включён"
else
  printf '# Written by scripts/bootstrap.sh. Empty: TrustTunnel framework not built (scripts/build-trusttunnel.sh).\n{}\n' > Config/optional.yml
  echo "TrustTunnel: не собран (WITH_TRUSTTUNNEL=1 bash scripts/bootstrap.sh)"
fi

grep -q "XXXXXXXXXX" Config/Signing.xcconfig && \
  echo "⚠ Впишите DEVELOPMENT_TEAM, BUNDLE_PREFIX и APP_GROUP в Config/Signing.xcconfig (или Config/Local.xcconfig)."

xcodegen generate
echo "Готово: open SLMtune.xcodeproj"
