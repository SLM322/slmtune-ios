#!/usr/bin/env bash
# Toolchain for working on SLMtune iOS from Windows: run inside WSL (Ubuntu 24.04).
#   wsl -d Ubuntu-24.04 -u root -- bash /mnt/g/slmtune-ios/scripts/wsl-setup.sh
# Installs Swift (swiftly) and Go, enough to compile and test Shared/ on Linux (scripts/linux-check.sh).
# Building the whole iOS app on Linux needs xtool plus Xcode.xip — see README.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl git unzip ca-certificates gnupg2 binutils libc6-dev libcurl4-openssl-dev \
  libedit2 libgcc-13-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev \
  pkg-config tzdata zlib1g-dev >/dev/null

if ! command -v swift >/dev/null 2>&1 && [ ! -x "$HOME/.local/share/swiftly/bin/swift" ]; then
  cd /tmp
  curl -sSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
  tar zxf "swiftly-$(uname -m).tar.gz"
  ./swiftly init --quiet-shell-followup --assume-yes
fi
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
hash -r
swift --version

if ! command -v go >/dev/null 2>&1; then
  GOV=$(curl -sS "https://go.dev/VERSION?m=text" | head -1)
  curl -sSL "https://go.dev/dl/${GOV}.linux-amd64.tar.gz" | tar -C /usr/local -xz
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
fi
go version
