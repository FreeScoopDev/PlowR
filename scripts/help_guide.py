#!/usr/bin/env python3
"""PlowR's help has one source: PlowR/Help/HelpGuide.json. The app bundles
it (Settings > Help, the Help items on screens, and from 1.8 the tips), and
this script writes the website's page from it, docs/help.html. Edit the JSON,
never the page, then run this.

  python3 scripts/help_guide.py           # writes docs/help.html
  python3 scripts/help_guide.py --check   # exits 1 if the page is out of date

The page records the SHA-256 of the JSON, of this script and of itself (with
that field blank), and a unit test (HelpGuideTests) recomputes all three, so
the required test check fails a PR that edits one without remaking the page.

Markup in the JSON, the same in the app: **UI label**, [text](https://...),
and [PRO] for the Pro badge; links are https: or mailto:. HelpGuideTests
fails any other markup, which the app and this script would show differently.
Standard library only."""

import hashlib, html, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PlowR/Help/HelpGuide.json"
PAGE = ROOT / "docs/help.html"
PAGE_HASH = "plowr-help-page"
SOURCE_HASH = "plowr-help-source"
SCRIPT_HASH = "plowr-help-script"

CSS = """\
        :root { color-scheme: light dark; --text: #1c1c1e; --muted: #6e6e73; --link: #0071e3; --card: #f2f2f7; --bg: #ffffff; --shot: #e5e5ea; --shot2: #dedee3; --line: #c7c7cc; --warn: #b25000; }
        @media (prefers-color-scheme: dark) {
            :root { --text: #f2f2f7; --muted: #a1a1a6; --link: #4da3ff; --card: #1c1c1e; --bg: #000000; --shot: #2c2c2e; --shot2: #262628; --line: #48484a; --warn: #ff9f0a; }
        }
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 760px; margin: 40px auto; padding: 0 20px; color: var(--text); background: var(--bg); line-height: 1.6; }
        a { color: var(--link); }
        h1 { font-size: 2.4em; margin-bottom: 0; }
        p.lede { font-size: 1.2em; color: var(--muted); margin-top: 4px; }
        nav.toc { display: flex; flex-wrap: wrap; gap: 8px; }
        nav.toc a { background: var(--card); color: var(--text); padding: 6px 14px; border-radius: 999px; font-size: 0.9em; text-decoration: none; }
        section { margin-top: 2.5em; }
        section > h2 { margin-bottom: 4px; }
        section > p.intro { color: var(--muted); margin-top: 0; }
        .card { background: var(--card); border-radius: 12px; padding: 18px 20px; margin-top: 16px; }
        .card h3 { margin: 0 0 4px; font-size: 1.15em; }
        .card p.lead { margin: 0 0 4px; color: var(--muted); }
        .shots { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin: 14px 0 16px; }
        img.shot { display: block; width: 100%; height: auto; padding: 0; border: 1px solid var(--line); border-radius: 18px; object-fit: cover; }
        ol.steps { padding-left: 0; list-style: none; counter-reset: step; margin: 0; }
        ol.steps li { counter-increment: step; position: relative; padding: 0 0 10px 38px; }
        ol.steps li::before { content: counter(step); position: absolute; left: 0; top: 1px; width: 26px; height: 26px; border-radius: 50%; background: var(--link); color: #fff; font-size: 0.8em; font-weight: 600; display: flex; align-items: center; justify-content: center; }
        .ui { font-weight: 600; }
        .pro { display: inline-block; font-size: 0.7em; font-weight: 700; padding: 1px 7px; border-radius: 999px; border: 1px solid var(--muted); color: var(--muted); vertical-align: middle; margin-left: 4px; }
        .note { margin-top: 8px; padding: 10px 14px; background: var(--bg); border-radius: 10px; font-size: 0.92em; color: var(--muted); }
        .tips { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin-top: 12px; }
        .tip { background: var(--card); border-radius: 12px; padding: 14px 16px; }
        .tip strong { display: block; }
        .tip span { color: var(--muted); font-size: 0.92em; }
        details { background: var(--card); border-radius: 12px; padding: 12px 16px; margin-top: 10px; }
        details summary { cursor: pointer; font-weight: 600; }
        details p { margin: 8px 0 0; }
        .release ul { padding-left: 20px; margin: 8px 0 0; }
        footer { margin-top: 3em; padding-top: 1em; border-top: 1px solid var(--card); color: var(--muted); font-size: 0.9em; }
        footer a { margin-right: 1em; }"""

PRO = '<span class="pro">PRO</span>'


def inline(text):
    """The JSON's markup as HTML: escape first, then the three marks."""
    out = html.escape(text, quote=False)
    out = re.sub(r"\*\*(.+?)\*\*", r'<span class="ui">\1</span>', out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', out)
    out = out.replace("[PRO]", PRO)
    return out


def attr(text):
    return html.escape(text, quote=True)


def title(topic):
    badge = f" {PRO}" if topic.get("pro") else ""
    return inline(topic["title"]) + badge


def card(topic, lines):
    lines.append(f'    <div class="card" id="{topic["id"]}">')
    lines.append(f"        <h3>{title(topic)}</h3>")
    if "lead" in topic:
        lines.append(f'        <p class="lead">{inline(topic["lead"])}</p>')
    if topic.get("shots"):
        lines.append('        <div class="shots">')
        for shot in topic["shots"]:
            lines.append(f'            <img class="shot" src="help/{attr(shot["file"])}" alt="{attr(shot["alt"])}" loading="lazy">')
        lines.append("        </div>")
    if topic.get("steps"):
        lines.append('        <ol class="steps">')
        for step in topic["steps"]:
            lines.append(f"            <li>{inline(step)}</li>")
        lines.append("        </ol>")
    if "note" in topic:
        lines.append(f'        <div class="note">{inline(topic["note"])}</div>')
    lines.append("    </div>")


def section(sec, lines):
    lines.append("")
    lines.append(f'<section id="{sec["id"]}">')
    lines.append(f"    <h2>{inline(sec['title'])}</h2>")
    if "intro" in sec:
        lines.append(f'    <p class="intro">{inline(sec["intro"])}</p>')
    style = sec["style"]
    if style == "cards":
        for topic in sec["topics"]:
            lines.append("")
            card(topic, lines)
    elif style == "tips":
        lines.append('    <div class="tips">')
        for t in sec["topics"]:
            emoji = t["emoji"] + " " if "emoji" in t else ""
            lines.append(f'        <div class="tip" id="{t["id"]}"><strong>{emoji}{title(t)}</strong><span>{inline(t["summary"])}</span></div>')
        lines.append("    </div>")
    elif style == "faq":
        for t in sec["topics"]:
            lines.append(f'    <details id="{t["id"]}">')
            lines.append(f"        <summary>{title(t)}</summary>")
            lines.append(f"        <p>{inline(t['summary'])}</p>")
            lines.append("    </details>")
    elif style == "release":
        for t in sec["topics"]:
            lines.append(f'    <div class="card release" id="{t["id"]}">')
            lines.append(f"        <h3>{title(t)}</h3>")
            lines.append("        <ul>")
            for b in t.get("bullets", []):
                lines.append(f"            <li>{inline(b)}</li>")
            lines.append("        </ul>")
            lines.append("    </div>")
    else:
        sys.exit(f"Unknown section style {style!r} in {sec['id']}")
    if "outro" in sec:
        lines.append(f"    <p>{inline(sec['outro'])}</p>")
    lines.append("</section>")


def render(source_bytes):
    guide = json.loads(source_bytes)
    lines = [
        "<!DOCTYPE html>",
        '<html lang="en">',
        "<!-- Made by scripts/help_guide.py from PlowR/Help/HelpGuide.json. Don't edit",
        "     this page: edit the JSON, then run python3 scripts/help_guide.py. -->",
        "<head>",
        '    <meta charset="UTF-8">',
        '    <meta name="viewport" content="width=device-width, initial-scale=1.0">',
        f'    <meta name="description" content="{attr(guide["description"])}">',
        f'    <meta name="{SOURCE_HASH}" content="{hashlib.sha256(source_bytes).hexdigest()}">',
        f'    <meta name="{SCRIPT_HASH}" content="{hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}">',
        f'    <meta name="{PAGE_HASH}" content="">',
        "    <title>PlowR Help — Tips &amp; Tricks</title>",
        "    <style>",
        CSS,
        "    </style>",
        "</head>",
        "<body>",
        "",
        f"<h1>{inline(guide['title'])}</h1>",
        f'<p class="lede">{inline(guide["lede"])}</p>',
        "",
        '<nav class="toc">',
    ]
    for sec in guide["sections"]:
        lines.append(f'    <a href="#{sec["id"]}">{inline(sec["nav"])}</a>')
    lines.append("</nav>")
    for sec in guide["sections"]:
        section(sec, lines)
    lines += [
        "",
        "<footer>",
        '    <a href="index.html">Home</a>',
        '    <a href="support.html">Support</a>',
        '    <a href="privacy-policy.html">Privacy Policy</a>',
        '    <a href="terms-of-service.html">Terms of Service</a>',
        "</footer>",
        "",
        "</body>",
        "</html>",
        "",
    ]
    page = "\n".join(lines)
    # The page's own hash, taken with its field blank; the test does the same.
    blank = f'<meta name="{PAGE_HASH}" content="">'
    digest = hashlib.sha256(page.encode("utf-8")).hexdigest()
    return page.replace(blank, f'<meta name="{PAGE_HASH}" content="{digest}">', 1)


def main():
    page = render(SOURCE.read_bytes())
    if "--check" in sys.argv[1:]:
        if not PAGE.exists() or PAGE.read_text(encoding="utf-8") != page:
            print("docs/help.html isn't what PlowR/Help/HelpGuide.json makes. "
                  "Edit the JSON, not the page, then run: python3 scripts/help_guide.py")
            return 1
        print("docs/help.html matches PlowR/Help/HelpGuide.json.")
        return 0
    PAGE.write_text(page, encoding="utf-8")
    print(f"Wrote {PAGE.relative_to(ROOT)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
