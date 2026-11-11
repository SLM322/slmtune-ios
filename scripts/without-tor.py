#!/usr/bin/env python3
"""Drops the Tor.framework package from project.yml (Tor servers then report "no core" in the app).
For the lite build, and for an Xcode whose Swift is older than the package's tools version (6.3)."""
import re

p = open('project.yml', encoding='utf-8').read()
out = p.replace("      - package: TorFramework\n        product: CTor\n", "")
out = re.sub(r"(?:  #[^\n]*\n)?  TorFramework:\n(?:    [^\n]*\n)+", "", out)
assert "TorFramework" not in out and out != p, "project.yml: the Tor package entries were not found"
open('project.yml', 'w', encoding='utf-8').write(out)
print("project.yml: Tor.framework removed")
