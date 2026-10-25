#!/usr/bin/env python3
"""App Store 크리에이티브 자산(제품 페이지 헤더 · 검색 결과) 생성: HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_creative_assets.py [언어 ...]     (없으면 전부)

자리
  docs/screenshots/creative/<스토어 로케일>/header.png   3840x1646  제품 페이지 맨 위
  docs/screenshots/creative/<스토어 로케일>/search.png   3840x2560  검색 결과 (없으면 스크린샷이 대신 보인다)

⚠️ 안전 영역 밖은 기기에 따라 잘린다. 글은 **반드시** 안전 영역 안에 둔다(배경 · 기기 그림은 넘쳐도 된다).
   수치는 Apple 공식 PSD 템플릿에서 잰 값이다(https://developer.apple.com/app-store/asset-best-practices/).
   아이폰에서 헤더는 가운데만 남고, 검색 결과는 약 385pt 폭으로 줄어 보인다. 그래서 글이 크다.

⚠️ 가격 · 할인 · 주소(URL) · 수상 · 다른 플랫폼 이름은 넣지 않는다(Apple 가이드).
"""
import subprocess, sys, pathlib, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw" / "iphone"
OUT = ROOT / "docs" / "screenshots" / "creative"
ICON = ROOT / "docs" / "assets" / "icon.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 앱 언어 코드 → 폴더 (deploy.env 의 LOCALES 와 같다)
STORE = {}

# (가로, 세로, 안전 영역 left, top, right, bottom)
SPEC = {
    "header": (3840, 1646, (1097, 493, 2743, 1154)),
    "search": (3840, 2560, (836, 765, 3004, 1795)),
}

# 눈썹글 · 헤드라인 · 보조 문장은 검색 결과에 쓴다. 스크린샷 1장과 **같은 이야기**다.
# 눈썹글은 그 나라 검색어다.
SEARCH = {
    "ko": ("코치 실습 기록", "녹음하면<br>코칭일지 완성", "누적 시간과 작성 점검을 한눈에"),
    "en": ("Coaching hours log", "Record it.<br>Your log is done.", "Total hours and log checks at a glance"),
}

# 헤더는 처음 온 사람에게 **한 가지 약속**만 한다: 코칭에 집중하면 기록은 앱이 한다.
# ⚠️ 기계번역하지 않는다. 각 언어에서 짧게 읽히는 말로 따로 쓴다.
HEADER = {
    "ko": ("코치 자격 실습 기록", "코칭에만 집중하세요<br>기록은 앱이 해요"),
    "en": ("Coaching log for credentials", "Focus on coaching.<br>The log writes itself."),
}

# ⚠️ 바탕 · 글자색은 기존 스크린샷(make_marketing_screenshots.py)과 같다. 다르면 페이지에서
#    헤더만 남의 앱처럼 보인다.
BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:linear-gradient(170deg, #1d3a6b 0%%, #142a52 100%%); position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", "Hiragino Sans", "PingFang SC", "Thonburi", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(160px); pointer-events:none; }
.text { position:absolute; display:flex; flex-direction:column; justify-content:center; }
.eyebrow { font-weight:700; color:#ff6b63; letter-spacing:-0.01em; line-height:1.15; }
.headline { font-weight:800; color:#ffffff; letter-spacing:-0.03em; line-height:1.12; text-wrap:balance; }
.sub { font-weight:500; color:#d6deef; letter-spacing:-0.01em; line-height:1.35; text-wrap:balance; }
:lang(th) .headline, :lang(th) .eyebrow, :lang(th) .sub,
:lang(ja) .headline, :lang(zh) .headline { letter-spacing:0; }
:lang(th) .headline { line-height:1.3; }
/* 한국어는 낱말 중간에서 끊지 않는다("키 / 보드"). */
:lang(ko) .headline, :lang(ko) .sub, :lang(ko) .eyebrow { word-break:keep-all; }
.phone { position:absolute; background:#2b4677; padding:40px; border-radius:190px;
  box-shadow: 0 60px 160px rgba(0,0,0,.45); }
.phone img { width:100%%; display:block; border-radius:152px; }
.key { position:absolute; opacity:.22; border-radius:22%%; }
"""

# 글이 상자를 넘지 않을 때까지 줄인다. 잘리는 글은 없다 - 끝까지 안 맞으면 표시하고 멈춘다.
FIT_JS = """
<script>
// 문구에 적은 줄(<br>)보다 더 쪼개지면 "Rispondi / con un / tocco" 처럼 읽기가 끊긴다.
// 적은 줄 수를 지킬 때까지 줄인다.
function lines(el) {
  return Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
}
function fit(box, el, max, min) {
  const want = el.querySelectorAll('br').length + 1;
  let size = max;
  el.style.fontSize = size + 'px';
  while (size > min && (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 ||
         lines(el) > want)) {
    size -= 4; el.style.fontSize = size + 'px';
  }
  if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 || lines(el) > want)
    document.body.dataset.overflow = '1';
}
document.fonts.ready.then(() => {
  const box = document.querySelector('.text');
  const h = document.querySelector('.headline');
  fit(box, h, +h.dataset.max, +h.dataset.min);
  document.body.dataset.done = '1';
});
</script>
"""


def phone(img, left, top, width, rotate=0):
    return (f'<div class="phone" style="left:{left}px;top:{top}px;width:{width}px;'
            f'transform:rotate({rotate}deg)"><img src="{img}"></div>')


def search_html(lang):
    W, H, (l, t, r, b) = SPEC["search"]
    eyebrow, headline, sub = SEARCH[lang]
    sw, sh = r - l, b - t
    col = int(sw * 0.56)
    # 기기는 안전 영역 오른쪽 몫에 서서, 위아래로 넘쳐 화면 밖까지 이어진다(기기 그림은 잘려도 된다).
    ph_w = 1040
    ph_left = l + col + int(sw * 0.04)
    img = (RAW / lang / "1-list.png").as_uri()
    return f"""
<div class="glow" style="left:{ph_left - 300}px;top:500px;width:1700px;height:1700px;background:rgba(60,110,200,.35)"></div>
<div class="glow" style="left:{l - 700}px;top:{t - 500}px;width:1400px;height:1000px;background:rgba(60,110,200,.18)"></div>
{phone(img, ph_left, t - 360, ph_w, 0)}
<div class="text" style="left:{l}px;top:{t}px;width:{col}px;height:{sh}px">
  <div class="eyebrow" style="font-size:96px">{eyebrow}</div>
  <div class="headline" data-max="250" data-min="140" style="margin-top:36px">{headline}</div>
  <div class="sub" style="font-size:84px;margin-top:52px">{sub}</div>
</div>"""


def header_html(lang):
    W, H, (l, t, r, b) = SPEC["header"]
    eyebrow, headline = HEADER[lang]
    sw, sh = r - l, b - t
    key = ICON.as_uri()
    left_img = (RAW / lang / "2-recording.png").as_uri()
    right_img = (RAW / lang / "1-list.png").as_uri()
    # 앱 아이콘을 안전 영역 바깥에 흩는다. 아이폰에서는 잘려도 되는 장식이다.
    keys = [(-40, 80, 300, -14), (330, 1130, 240, 12), (3330, 120, 260, 16), (3620, 1040, 300, -10),
            (2930, 1260, 200, -6), (650, 40, 190, 8)]
    keys_html = "".join(f'<img class="key" src="{key}" style="left:{x}px;top:{y}px;width:{w}px;'
                        f'transform:rotate({rot}deg)">' for x, y, w, rot in keys)
    return f"""
<div class="glow" style="left:{l - 200}px;top:{t - 400}px;width:{sw + 400}px;height:{sh + 800}px;background:rgba(60,110,200,.30)"></div>
{keys_html}
{phone(left_img, 300, 360, 640, -9)}
{phone(right_img, 2900, 360, 640, 9)}
<div class="text" style="left:{l}px;top:{t}px;width:{sw}px;height:{sh}px;align-items:center;text-align:center">
  <div class="eyebrow" style="font-size:76px">{eyebrow}</div>
  <div class="headline" data-max="210" data-min="110" style="margin-top:22px">{headline}</div>
</div>"""


def html_lang(lang):
    return {"zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant"}.get(lang, lang)


def render(lang, kind):
    W, H, _ = SPEC[kind]
    body = search_html(lang) if kind == "search" else header_html(lang)
    page = (f'<!doctype html><html lang="{html_lang(lang)}"><head><meta charset="utf-8"><style>'
            f'{BASE_CSS % {"W": W, "H": H}}</style></head><body>{body}{FIT_JS}</body></html>')
    html_path = pathlib.Path(tempfile.gettempdir()) / f"coachinglog-creative-{lang}-{kind}.html"
    html_path.write_text(page, encoding="utf-8")
    # 글이 끝까지 안 맞으면 그림을 만들지 않는다(잘린 글이 스토어에 올라가는 것보다 낫다).
    # Chrome prints the page at once but can hang while shutting down, so take what it printed.
    try:
        dom = subprocess.run([CHROME, "--headless=new", "--dump-dom", f"--window-size={W},{H}",
                              "--force-device-scale-factor=1", "--disable-gpu", "--virtual-time-budget=3000",
                              html_path.as_uri()], capture_output=True, text=True, timeout=60).stdout
    except subprocess.TimeoutExpired as e:
        dom = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
    if 'data-done="1"' not in dom:
        raise SystemExit(f"글 맞추기가 끝나지 않았다: {lang} {kind}")
    if 'data-overflow="1"' in dom:
        raise SystemExit(f"글이 안전 영역을 넘는다: {lang} {kind} - 문구를 줄일 것")
    out_dir = OUT / STORE.get(lang, lang)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_png = out_dir / f"{kind}.png"
    # ⚠️ Chrome 은 가끔 아무것도 안 그리고 끝나거나 멈춘다. 파일이 생길 때까지 여섯 번까지 한다.
    out_png.unlink(missing_ok=True)
    for _ in range(6):
        try:
            subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                            f"--window-size={W},{H}", "--force-device-scale-factor=1",
                            "--hide-scrollbars", "--disable-gpu", "--virtual-time-budget=3000",
                            "--allow-file-access-from-files", html_path.as_uri()],
                           capture_output=True, timeout=60)
        except subprocess.TimeoutExpired:
            pass
        if out_png.exists() and out_png.stat().st_size > 0:
            break
    else:
        raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
    print(f"rendered {out_png}")


if __name__ == "__main__":
    langs = sys.argv[1:] or list(SEARCH)
    for lang in langs:
        if lang not in SEARCH:
            raise SystemExit(f"모르는 언어: {lang} (아는 것: {', '.join(SEARCH)})")
        for kind in ("header", "search"):
            render(lang, kind)
