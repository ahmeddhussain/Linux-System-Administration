#!/usr/bin/env python3
"""Build docs/guide/ahmed-infra-guide.pdf from the HTML parts in src/.

Needs WeasyPrint (pip install weasyprint) and the Pango libraries.
    python3 docs/guide/build.py
Parts are concatenated in name order; every <h1> and <h2> gets an id and
an entry in the table of contents, with page numbers filled in by
WeasyPrint (target-counter).
"""
import html
import pathlib
import re

import weasyprint

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / "src"
OUT = HERE / "ahmed-infra-guide.pdf"


def slug(text, seen):
    s = re.sub(r"<[^>]+>", "", text)
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-") or "section"
    base, n = s, 2
    while s in seen:
        s = f"{base}-{n}"
        n += 1
    seen.add(s)
    return s


def main():
    body = "\n".join(p.read_text() for p in sorted(SRC.glob("[0-9]*.html")))
    seen, toc = set(), []

    def add_id(m):
        level, attrs, text = m.group(1), m.group(2), m.group(3)
        if "notoc" in attrs:
            return m.group(0)
        sid = slug(text, seen)
        toc.append((level, sid, re.sub(r"<[^>]+>", "", text)))
        return f'<h{level} id="{sid}"{attrs}>{text}</h{level}>'

    body = re.sub(r"<h([12])([^>]*)>(.*?)</h\1>", add_id, body, flags=re.S)
    items = "\n".join(
        f'<li class="toc{lvl}"><a href="#{sid}">{html.escape(t)}</a></li>'
        for lvl, sid, t in toc
    )
    doc = (SRC / "template.html").read_text()
    doc = doc.replace("{{TOC}}", items).replace("{{BODY}}", body)
    weasyprint.HTML(string=doc, base_url=str(SRC)).write_pdf(
        OUT, stylesheets=[weasyprint.CSS(filename=str(SRC / "style.css"))]
    )
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
