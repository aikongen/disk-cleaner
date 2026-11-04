#!/usr/bin/env python3
"""Generate the Help Book pages from the consumer docs. Called by scripts/make-help-book.sh.

Usage: build.py <repo-root> <English.lproj dir> <version>
Every topic page is one docs page with `audience: consumer`. Links that leave that set
(maintainer pages, Sources, Tests, the root README) are dropped and their text is kept.
"""
import html, os, re, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from md2html import convert

root, lproj, version = sys.argv[1], sys.argv[2], sys.argv[3]
GH = "https://github.com/aikongen/disk-cleaner"

def read(rel):
    return open(os.path.join(root, rel), encoding="utf-8").read()

def consumer(rel):
    m = re.match(r"---\n(.*?)\n---\n", read(rel), re.S)
    if not m or "audience: consumer" not in m.group(1).splitlines():
        sys.exit("%s is not audience: consumer" % rel)
    return read(rel)[m.end():]

# anchor, source docs page, card title, card summary
TOPICS = [
    ("what-it-does", "docs/explanation/what-it-does.md", "What Disk Cleaner does", "What it shows you and what it never does."),
    ("first-scan", "docs/tutorials/first-scan.md", "Your first scan", "Open the app, try the preview, scan a folder."),
    ("browse-and-trash", "docs/how-to/browse-and-trash.md", "Browse and move to the Trash", "Find items, check them, review the exact paths, then move."),
    ("agents", "docs/reference/automation-contract.md", "Agents and the command line", "Let an AI agent ask for free space and get an honest answer."),
    ("settings", "docs/how-to/settings.md", "Settings and Cleanups", "Scan history, and the list of past agent requests."),
    ("limits", "docs/explanation/limits.md", "Limits and your data", "What is stored, what is not promised, what to do if a file is damaged."),
    ("shortcuts", "docs/reference/keyboard-shortcuts.md", "Keyboard shortcuts", "The keys the app defines."),
    ("whats-new", None, "What's new", "Changes in this version."),
]
PAGE_OF = {src: a for a, src, _, _ in TOPICS if src}
PAGE_OF["docs/README.md"] = "index"
images = set()

def make_link_map(src):
    base_dir = os.path.dirname(src)
    def link_map(url):
        if url.startswith(("http://", "https://")):
            return url
        path, _, frag = url.partition("#")
        target = os.path.normpath(os.path.join(base_dir, path)) if path else src
        if target in PAGE_OF:
            return PAGE_OF[target] + ".html" + ("#" + frag if frag else "")
        if target.startswith("assets/") and target.endswith(".png"):
            images.add(os.path.basename(target))
            return "images/" + os.path.basename(target)
        return None  # leaves the consumer set
    return link_map

# Keep the shortcuts page in step with the app's commands.
src_code = "".join(open(os.path.join(dp, f), encoding="utf-8").read()
                   for dp, _, fs in os.walk(os.path.join(root, "Sources", "DiskCleanerApp")) for f in fs if f.endswith(".swift"))
for needle in ('keyboardShortcut(",", modifiers: .command)', ".keyboardShortcut(.cancelAction)", 'keyboardShortcut("?", modifiers: .command)'):
    if needle not in src_code:
        sys.exit("Shortcut in docs/reference/keyboard-shortcuts.md is no longer in the app source: " + needle)

def paragraphs(text):
    return [p for p in re.split(r"\n\s*\n", text) if p.strip()]

def agents_filter(md):
    """The automation contract without maintainer-only rows and paragraphs."""
    lines = [l for l in md.split("\n") if not l.startswith(("| `worker <job-id>`", "| `fixture-capability`"))]
    paras = [p for p in paragraphs("\n".join(lines)) if not p.startswith(("DEBUG CLI fixtures", "Maintainer source:"))]
    return "\n\n".join(paras)

def changelog_section():
    cl = read("CHANGELOG.md")
    m = re.search(r"^## %s\b.*?(?=^## |\Z)" % re.escape(version), cl, re.S | re.M)
    if not m:
        sys.exit("CHANGELOG.md has no '## %s' section; the Help Book never shows Unreleased." % version)
    return "# What's new\n\n" + m.group(0).strip()

def strip_h1(body_html):
    return re.sub(r'<h1 id="[^"]*"><a name="[^"]*"></a>.*?</h1>\n?', "", body_html, count=1, flags=re.S)

def page(anchor, title, body, index=False):
    meta = '<meta name="AppleTitle" content="Disk Cleaner Help">\n<meta name="AppleIcon" content="DiskCleaner.help/Contents/Resources/English.lproj/images/icon.png">\n' if index else ""
    head = ('<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8">\n<title>%s</title>\n%s'
            '<meta name="robots" content="anchors">\n<meta name="description" content="%s">\n<link rel="stylesheet" href="style.css">\n</head>\n<body>\n'
            % (html.escape(title), meta, html.escape(title)))
    nav = '<header><img class="icon" src="images/icon.png" alt="" width="48" height="48"><div><a href="index.html" class="crumb">Disk Cleaner Help</a>' + \
          ('' if index else '<span class="crumb-sep"> / </span><span class="crumb">%s</span>' % html.escape(title)) + '</div></header>\n'
    foot = '<footer>Disk Cleaner %s &middot; <a href="index.html">All topics</a> &middot; <a href="%s">GitHub</a></footer>\n</body></html>\n' % (version, GH)
    return head + nav + '<main>\n<a name="%s"></a>\n%s\n</main>\n' % (anchor, body) + foot

os.makedirs(os.path.join(lproj, "images"), exist_ok=True)
rendered = []
for anchor, srcpath, title, summary in TOPICS:
    if srcpath is None:
        md, lm = changelog_section(), (lambda u: u if u.startswith("http") else None)
    else:
        md, lm = consumer(srcpath), make_link_map(srcpath)
        if anchor == "agents":
            md = agents_filter(md)
    body = strip_h1(convert(md, lm))
    open(os.path.join(lproj, anchor + ".html"), "w", encoding="utf-8").write(
        page(anchor, title, "<h1>%s</h1>\n%s" % (html.escape(title), body)))
    rendered.append((anchor, title, summary))

for name in ["icon.png"] + sorted(images):
    shutil.copy(os.path.join(root, "assets", name), os.path.join(lproj, "images", name))
shutil.copy(os.path.join(os.path.dirname(os.path.abspath(__file__)), "style.css"), os.path.join(lproj, "style.css"))

cards = "".join('<li><a href="%s.html"><strong>%s</strong><span>%s</span></a></li>\n' % (a, html.escape(t), html.escape(s)) for a, t, s in rendered)
tagline = re.search(r"^(See what fills[^\n]*)", consumer("docs/explanation/what-it-does.md"), re.M).group(1)
index_body = '<h1>Disk Cleaner Help</h1>\n<p class="lead">%s</p>\n<ul class="topics">\n%s</ul>\n' % (html.escape(tagline), cards)
open(os.path.join(lproj, "index.html"), "w", encoding="utf-8").write(page("index", "Disk Cleaner Help", index_body, index=True))
print("pages: index " + " ".join(a for a, _, _ in rendered))
