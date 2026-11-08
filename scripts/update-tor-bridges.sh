#!/usr/bin/env bash
# Refreshes the built-in Tor bridges (the same file Tor Browser ships).
set -euo pipefail
cd "$(dirname "$0")/.."
curl -sfL "https://gitlab.torproject.org/tpo/applications/tor-browser-build/-/raw/main/projects/tor-expert-bundle/pt_config.json" -o Resources/pt_config.json
echo "Resources/pt_config.json updated"
