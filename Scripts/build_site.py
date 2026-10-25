#!/usr/bin/env python3
"""Builds one page per language from the bilingual sources in docs/src.

    python3 Scripts/build_site.py

Elements marked data-lang="ko" or "en" are kept only on their language's page.
Korean pages go to docs/ (the default language), English pages to docs/en/.
"""
import re
from html.parser import HTMLParser
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"
SITE = "https://m1zz.github.io/KACCoachingLog/"
LANGS = {"ko": ("", "한국어"), "en": ("en/", "English")}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class LanguageFilter(HTMLParser):
    """Copies the source verbatim, dropping elements written for another language."""

    def __init__(self, lang):
        super().__init__(convert_charrefs=False)
        self.lang, self.out, self.skip = lang, [], 0

    def emit(self, text):
        if not self.skip:
            self.out.append(text)

    def handle_starttag(self, tag, attrs):
        other = dict(attrs).get("data-lang") not in (None, self.lang)
        if self.skip or other:
            if tag not in VOID:
                self.skip += 1
            return
        self.out.append(self.get_starttag_text().replace(f' data-lang="{self.lang}"', ""))

    def handle_startendtag(self, tag, attrs):
        if not self.skip and dict(attrs).get("data-lang") in (None, self.lang):
            self.out.append(self.get_starttag_text().replace(f' data-lang="{self.lang}"', ""))

    def handle_endtag(self, tag):
        if self.skip:
            self.skip -= 1
        else:
            self.out.append(f"</{tag}>")

    def handle_data(self, data): self.emit(data)
    def handle_entityref(self, name): self.emit(f"&{name};")
    def handle_charref(self, name): self.emit(f"&#{name};")
    def handle_comment(self, data): self.emit(f"<!--{data}-->")
    def handle_decl(self, decl): self.emit(f"<!{decl}>")


def build(source: Path, lang: str) -> str:
    prefix, _ = LANGS[lang]
    html = source.read_text()
    title = re.search(rf'data-title-{lang}="([^"]*)"', html).group(1)

    parser = LanguageFilter(lang)
    parser.feed(html)
    html = "".join(parser.out)
    html = re.sub(r'<html lang="\w+"[^>]*>', f'<html lang="{lang}">', html)
    html = re.sub(r"<title>.*?</title>", f"<title>{title}</title>", html)

    page = "" if source.name == "index.html" else source.name
    alternates = "".join(
        f'  <link rel="alternate" hreflang="{code}" href="{SITE}{p}{page}">\n' for code, (p, _) in LANGS.items()
    ) + f'  <link rel="alternate" hreflang="x-default" href="{SITE}{page}">\n'
    html = html.replace("</head>", alternates + "</head>")

    up = "../" * prefix.count("/")
    current = ' aria-current="page"'
    switch = "".join(
        f'<a href="{up}{p}{page or "./"}"{current if code == lang else ""}>{name}</a>'
        for code, (p, name) in LANGS.items()
    )
    html = re.sub(r'(<div class="lang"[^>]*>).*?(</div>)', rf"\g<1>{switch}\g<2>", html, flags=re.S)
    if up:
        html = re.sub(r'(href|src)="(assets/|style\.css)', rf'\1="{up}\2', html)
    return html


for source in sorted((DOCS / "src").glob("*.html")):
    for lang, (prefix, _) in LANGS.items():
        target = DOCS / prefix / source.name
        target.parent.mkdir(exist_ok=True)
        target.write_text(build(source, lang))
        print("wrote", target.relative_to(DOCS))
