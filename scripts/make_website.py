#!/usr/bin/env python3
"""Builds website/credits.html from Lumi/Resources/Credits.json and checks that every entry made it into the page."""
import html, json, os

ROOT = os.path.join(os.path.dirname(__file__), "..")
entries = json.load(open(os.path.join(ROOT, "Lumi", "Resources", "Credits.json")))

def card(e):
    link = f' · <a href="{html.escape(e["licenseURL"])}">license</a>' if e.get("licenseURL") else ""
    src = f' · <a href="{html.escape(e["sourceURL"])}">source</a>' if e.get("sourceURL") else ""
    return f'<li><strong>{html.escape(e["title"])}</strong><br>{html.escape(e["attribution"])}<br><small>{html.escape(e["license"])}{link}{src}</small></li>'

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lumi credits</title>
<style>body{{font:16px/1.5 system-ui,sans-serif;max-width:720px;margin:2rem auto;padding:0 1rem;color:#222}}li{{margin:1rem 0}}small{{color:#666}}</style></head>
<body><h1>Credits</h1>
<p>Lumi is made with open models, open fonts and original artwork. Thank you to everyone below.</p>
<ul>
{chr(10).join(card(e) for e in entries)}
</ul></body></html>
"""
out = os.path.join(ROOT, "website", "credits.html")
open(out, "w").write(page)
written = open(out).read()
missing = [e["title"] for e in entries if html.escape(e["title"]) not in written]
assert not missing, missing
print(len(entries), "credits written")
