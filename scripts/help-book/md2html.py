#!/usr/bin/env python3
"""Minimal Markdown to HTML converter for the Help Book (no third-party packages).

Handles what the consumer docs use: headings, paragraphs, bullet and numbered
lists, pipe tables, fenced code, inline code, bold, italic, links and images.
"""
import html
import re


def slug(text):
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def inline(text, link_map):
    codes = []

    def stash(m):
        codes.append("<code>" + html.escape(m.group(1), quote=False) + "</code>")
        return "\x00%d\x00" % (len(codes) - 1)

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)
    def image(m):
        url = link_map(m.group(2))
        return '<img src="%s" alt="%s">' % (url, html.escape(m.group(1))) if url else ""

    def link(m):
        # A link map that returns None drops the link and keeps its text.
        url = link_map(m.group(2))
        return '<a href="%s">%s</a>' % (url, m.group(1)) if url else m.group(1)

    text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", image, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)


def convert(md, link_map=lambda u: u, shift=0):
    """Return HTML. `shift` raises heading levels (## becomes h(2+shift))."""
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
        elif line.startswith("```"):
            buf, i = [], i + 1
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i]); i += 1
            i += 1
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(buf), quote=False))
        elif re.match(r"#{1,6} ", line):
            level = len(line) - len(line.lstrip("#"))
            text = line[level:].strip()
            lv = min(level + shift, 6)
            out.append('<h%d id="%s"><a name="%s"></a>%s</h%d>' % (lv, slug(text), slug(text), inline(text, link_map), lv))
            i += 1
        elif line.lstrip().startswith("|"):
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append(split_row(lines[i]))
                i += 1
            head, body = rows[0], [r for r in rows[2:]]
            t = "<table><thead><tr>%s</tr></thead><tbody>" % "".join("<th>%s</th>" % inline(c, link_map) for c in head)
            for r in body:
                t += "<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c, link_map) for c in r)
            out.append(t + "</tbody></table>")
        elif re.match(r"\s*([-*]|\d+\.) ", line):
            ordered = bool(re.match(r"\s*\d+\. ", line))
            items = []
            while i < len(lines) and (re.match(r"\s*([-*]|\d+\.) ", lines[i]) or (lines[i].startswith("   ") and items and lines[i].strip())):
                if re.match(r"\s*([-*]|\d+\.) ", lines[i]):
                    items.append(re.sub(r"^\s*([-*]|\d+\.) ", "", lines[i]))
                else:
                    items[-1] += " " + lines[i].strip()
                i += 1
            tag = "ol" if ordered else "ul"
            out.append("<%s>%s</%s>" % (tag, "".join("<li>%s</li>" % inline(x, link_map) for x in items), tag))
        else:
            buf = []
            while i < len(lines) and lines[i].strip() and not re.match(r"(#{1,6} |```|\s*\||\s*([-*]|\d+\.) )", lines[i]):
                buf.append(lines[i].strip()); i += 1
            out.append("<p>%s</p>" % inline(" ".join(buf), link_map))
    return "\n".join(out)


def split_row(line):
    # Split on pipes that are not inside backtick code spans.
    cells, cur, in_code = [], "", False
    for ch in line.strip().strip("|"):
        if ch == "`":
            in_code = not in_code
        if ch == "|" and not in_code:
            cells.append(cur.strip()); cur = ""
        else:
            cur += ch
    cells.append(cur.strip())
    return cells
