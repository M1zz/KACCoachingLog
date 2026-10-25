#!/usr/bin/env python3
"""Composes App Store screenshots from the raw captures, in every language.

    Scripts/capture_screenshots.sh <app>       # raw captures first
    python3 Scripts/make_marketing_screenshots.py

Reads  docs/screenshots/raw/<device>/<lang>/<n>-<screen>.png
Writes docs/screenshots/marketing/<lang>/<n>-<device>-<screen>.png at App Store sizes.
"""
import base64
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs/screenshots/raw"
OUT = ROOT / "docs/screenshots/marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Canvas, headline size, and phone frame per device (frame width is a share of the canvas).
DEVICES = {
    "iphone": dict(size=(1242, 2688), headline=104, sub=56, top=96, frame=0.86, frame_top=440, radius=66, bezel=14),
    "ipad": dict(size=(2064, 2752), headline=112, sub=62, top=120, frame=0.84, frame_top=500, radius=44, bezel=16),
}

COPY = {
    "ko": {
        "1-list": ("녹음하면 코칭일지가 완성돼요", "누적 시간과 작성 점검을 한눈에"),
        "2-recording": ("시작과 종료, 버튼 한 번", "날짜·시각·분은 자동으로 기록돼요"),
        "3-detail": ("작성 오류를 미리 찾아요", "넘친 시간은 한 번에 고쳐요"),
        "4-settings": ("KAC부터 ICF MCC까지", "준비 중인 자격증에 맞춰 점검해요"),
        "5-export": ("제출용 엑셀로 바로", "공식 양식 서식 그대로 내보내요"),
    },
    "en": {
        "1-list": ("Record it. Your log is done.", "Total hours and log checks at a glance"),
        "2-recording": ("One tap to start and end", "Date, time, and minutes logged for you"),
        "3-detail": ("Every session, log-ready", "Times and minutes in ICF log format"),
        "4-settings": ("ICF ACC, PCC, MCC and KAC", "Checks follow your credential"),
        "5-export": ("Ready to submit", "Export your ICF coaching log as CSV"),
    },
}

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; }}
body {{
  background: radial-gradient({w}px {gh}px at 85% 0%, #2a5196 0%, transparent 70%),
              linear-gradient(170deg, #1d3a6b 0%, #142a52 100%);
  font-family: -apple-system, "SF Pro Display", "Apple SD Gothic Neo", sans-serif;
  color: #fff; text-align: center;
}}
h1 {{ margin: {top}px 40px 0; font-size: {headline}px; font-weight: 800; letter-spacing: -0.02em;
      line-height: 1.15; white-space: nowrap; }}
p {{ margin: {gap}px 40px 0; font-size: {sub}px; font-weight: 500; color: #d6deef; white-space: nowrap; }}
p::before {{ content: ""; display: inline-block; width: {dot}px; height: {dot}px; border-radius: 50%;
             background: #ef4b45; margin-right: {dotgap}px; vertical-align: middle; }}
.frame {{ position: absolute; left: 50%; top: {ftop}px; width: {fw}px; transform: translateX(-50%);
          padding: {bezel}px; border-radius: {outer}px; background: #2b4677;
          box-shadow: 0 30px 80px rgba(0,0,0,.35); }}
.frame img {{ display: block; width: 100%; border-radius: {radius}px; }}
</style></head><body>
<h1>{title}</h1><p>{subtitle}</p>
<div class="frame"><img src="data:image/png;base64,{shot}"></div>
<script>
// Shrink a line that would overflow the canvas.
for (const el of document.querySelectorAll("h1, p")) {{
  let size = parseFloat(getComputedStyle(el).fontSize);
  while (el.scrollWidth > el.clientWidth && size > 20) el.style.fontSize = (size -= 2) + "px";
}}
</script></body></html>"""


def render(device: str, lang: str, raw: Path, title: str, subtitle: str, target: Path) -> None:
    spec = DEVICES[device]
    w, h = spec["size"]
    html = PAGE.format(
        w=w, h=h, gh=int(h * 0.45), top=spec["top"], headline=spec["headline"], sub=spec["sub"],
        gap=int(spec["sub"] * 0.55), dot=int(spec["sub"] * 0.42), dotgap=int(spec["sub"] * 0.3),
        ftop=spec["frame_top"], fw=int(w * spec["frame"]), bezel=spec["bezel"], radius=spec["radius"],
        outer=spec["radius"] + spec["bezel"], title=title, subtitle=subtitle,
        shot=base64.b64encode(raw.read_bytes()).decode(),
    )
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as page:
        page.write(html)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Chrome writes the PNG right away but can hang while shutting down, so the file decides.
    target.unlink(missing_ok=True)
    for _ in range(6):
        try:
            subprocess.run([
                CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                "--virtual-time-budget=3000", f"--window-size={w},{h}", f"--screenshot={target}",
                f"file://{page.name}",
            ], capture_output=True, timeout=60)
        except subprocess.TimeoutExpired:
            pass
        if target.exists() and target.stat().st_size > 0:
            break
    else:
        raise SystemExit(f"Chrome could not render {target}")
    Path(page.name).unlink()
    print("wrote", target)


for lang, slides in COPY.items():
    for device in DEVICES:
        for name, (title, subtitle) in slides.items():
            raw = RAW / device / lang / f"{name}.png"
            number, screen = name.split("-", 1)
            render(device, lang, raw, title, subtitle, OUT / lang / f"{number}-{device}-{screen}.png")
