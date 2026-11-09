"""Renders the iPhone mockups of docs/showcase.html to PNG for the README (docs/img/*.png).

    python tools/render_screens.py            # needs Google Chrome; fonts load from Google Fonts

Every <div class="phone"> block of the showcase becomes one image; a strip of all of them is screens.png.
"""
import html
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "showcase.html")
OUT = os.path.join(ROOT, "docs", "img")
CHROME = next((p for p in [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome",
] if os.path.exists(p)), None)

NAMES = ["home", "servers", "routing", "settings", "connections", "log", "myservers", "lockscreen"]
TITLES = ["Главная", "Серверы", "Маршруты", "Настройки", "Соединения", "Журнал", "Мои серверы", "Виджет и Пункт управления"]

src = open(SRC, encoding="utf-8").read()
head = src[: src.index('<div class="wrap">')]  # title, fonts, <style>, svg symbols


def phones(text):
    """Every balanced <div class="phone">…</div> block, in page order."""
    out, i = [], 0
    while (start := text.find('<div class="phone">', i)) >= 0:
        depth, j = 0, start
        for m in re.finditer(r"<div\b|</div>", text[start:]):
            depth += 1 if m.group(0) == "<div" else -1
            if depth == 0:
                j = start + m.end()
                break
        out.append(text[start:j])
        i = j
    return out


blocks = phones(src)
assert len(blocks) == len(NAMES), f"{len(blocks)} phones in showcase.html, expected {len(NAMES)}"
os.makedirs(OUT, exist_ok=True)
extra = """<style>
body{margin:0;padding:0!important;background:#0B0B0D}
.shot{display:flex;gap:44px;padding:44px 48px 40px;align-items:flex-start;background:
 radial-gradient(60% 80% at 50% 0%,rgba(209,0,209,.22),transparent 70%),#0B0B0D}
.cap{font:600 15px/1 'Golos Text',system-ui;color:#A6A6B0;text-align:center;margin-top:18px}
.item{display:flex;flex-direction:column;align-items:center}
</style>"""


def render(name, body, width, height):
    page = os.path.join(tempfile.gettempdir(), f"slm-render-{name}.html")
    open(page, "w", encoding="utf-8").write(head + extra + body)
    png = os.path.join(OUT, f"{name}.png")
    profile = os.path.join(tempfile.gettempdir(), "slm-render-chrome")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={profile}",
                    "--force-device-scale-factor=2", "--virtual-time-budget=6000",
                    f"--window-size={width},{height}", f"--screenshot={png}", "file:///" + page.replace("\\", "/")],
                   check=True, capture_output=True)
    print("wrote", os.path.relpath(png, ROOT))


if not CHROME:
    sys.exit("Google Chrome not found")

item = lambda b, t: f'<div class="item">{b}<div class="cap">{html.escape(t)}</div></div>'
for name, title, b in zip(NAMES, TITLES, blocks):
    render(name, f'<div class="shot">{item(b, title)}</div>', 386, 730)
render("screens-1", '<div class="shot">' + "".join(item(b, t) for b, t in zip(blocks[:4], TITLES[:4])) + "</div>", 1424, 730)
render("screens-2", '<div class="shot">' + "".join(item(b, t) for b, t in zip(blocks[4:], TITLES[4:])) + "</div>", 1424, 730)
