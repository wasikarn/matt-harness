"""Verify the generated diagrams. Run with no arguments to check all of them.

Two passes, because they catch different classes of defect and only the first one
has an upstream equivalent:

  geometry  Label masks must not sit on a connector (diagram-design connector rule 2)
            or under a node drawn later (rule 6), and every rect coordinate lands on
            the 4px grid.

  text fit  Does each in-box label actually fit its box? diagram-design's own
            self_check.py and the geometry pass above both measure geometry and
            neither measures text. A sublabel one character too long sits flush
            against its border and reads as clipped. That shipped once, in
            07-orchestrate's validation chain, and stayed for several commits.

Usage:
    python3 docs/diagrams/src/check.py             # all diagrams
    python3 docs/diagrams/src/check.py 'path/*.html'
"""
import glob
import pathlib
import re
import sys

DIAGRAMS = str(pathlib.Path(__file__).resolve().parent.parent / "*.html")

# ---------------------------------------------------------------- geometry

def segs_from_path(d):
    """Axis-aligned segments of a connector path.

    Quarter-arc control points are skipped; they only round the corner, and the
    straight runs are what a label mask can collide with.
    """
    out = []
    x = y = None
    for tok in re.finditer(r'([MHVQ])\s*([-\d.,\s]+)', d):
        c = tok.group(1)
        n = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?', tok.group(2))]
        if c == 'M':
            x, y = n[0], n[1]
        elif c == 'H':
            out.append((x, y, n[0], y)); x = n[0]
        elif c == 'V':
            out.append((x, y, x, n[0])); y = n[0]
        elif c == 'Q':
            x, y = n[2], n[3]
    return out


def rect_seg_dist(rx, ry, rw, rh, s):
    """Gap between a mask rect and one connector segment, or None if they never meet."""
    x1, y1, x2, y2 = s
    if abs(y1 - y2) < 0.01:                       # horizontal segment
        lo, hi = sorted((x1, x2))
        if hi < rx or lo > rx + rw:
            return None
        return 0 if ry <= y1 <= ry + rh else (ry - y1 if y1 < ry else y1 - (ry + rh))
    lo, hi = sorted((y1, y2))                     # vertical segment
    if hi < ry or lo > ry + rh:
        return None
    return 0 if rx <= x1 <= rx + rw else (rx - x1 if x1 < rx else x1 - (rx + rw))


def check_geometry(svg):
    masks = [tuple(float(v) for v in m) for m in re.findall(
        r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="(12)" rx="2" fill="#f5f5f5"/>', svg)]
    nodes = [tuple(float(v) for v in m.groups()) for m in re.finditer(
        r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" rx="\d+" fill="(?!#f5f5f5")', svg)]
    for m in re.finditer(r'<polygon points="([\d,. ]+)" fill="(?!#f5f5f5")', svg):
        n = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?', m.group(1))]
        xs, ys = n[0::2], n[1::2]
        nodes.append((min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)))
    conns = [tuple(float(v) for v in m.groups()) for m in re.finditer(
        r'<line x1="(\d+)" y1="(\d+)" x2="(\d+)" y2="(\d+)"', svg)]
    for m in re.finditer(r'<path d="([^"]+)"', svg):
        conns += segs_from_path(m.group(1))

    probs = []
    for (mx, my, mw, mh) in masks:
        for (nx, ny, nw, nh) in nodes:
            if mx < nx + nw and mx + mw > nx and my < ny + nh and my + mh > ny:
                probs.append(f"mask({mx},{my}) overlaps node({nx},{ny},{nw}x{nh})")
        ds = [d for d in (rect_seg_dist(mx, my, mw, mh, c) for c in conns) if d is not None]
        if not ds:
            probs.append(f"mask({mx},{my}) annotates no connector")
        elif min(ds) < 6:
            probs.append(f"mask({mx},{my}) is {min(ds):.0f}px from a stroke (min 6)")
        elif min(ds) > 14:
            probs.append(f"mask({mx},{my}) is {min(ds):.0f}px from its stroke (max 14)")

    off = [m for m in re.findall(r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)"', svg)
           if any(int(v) % 4 for v in m)]
    if off:
        probs.append(f"{len(off)} rect(s) off the 4px grid: {off[:3]}")
    return probs, len(masks), len(nodes), len(conns)


# ---------------------------------------------------------------- text fit

# Advance widths are estimates: Geist Mono is 0.6em, Geist sans averages ~0.56em at
# these sizes. Because they are estimates, flag anything under MIN_PAD rather than
# only true overflow.
MONO_ADV, SANS_ADV, MIN_PAD = 0.60, 0.56, 6.0
UNESC = [("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]

BOX = re.compile(
    r'<rect x="(-?[\d.]+)" y="(-?[\d.]+)" width="(\d+)" height="(\d+)" rx="\d+" fill="#[0-9a-fA-F]{6}"/>')
TXT = re.compile(
    r'<text x="(-?[\d.]+)" y="(-?[\d.]+)"[^>]*?font-size="([\d.]+)"[^>]*?'
    r'font-family="([^"]+)"[^>]*?text-anchor="middle"[^>]*>([^<]*)</text>')


def check_textfit(svg):
    boxes = [(float(a), float(b), int(c), int(d)) for a, b, c, d in BOX.findall(svg)]
    probs = []
    for x, y, size, fam, raw in TXT.findall(svg):
        x, y, size = float(x), float(y), float(size)
        text = raw
        for a, b in UNESC:
            text = text.replace(a, b)
        if not text.strip():
            continue
        w = len(text) * size * (MONO_ADV if "Mono" in fam else SANS_ADV)
        for bx, by, bw, bh in boxes:
            if bx <= x <= bx + bw and by <= y <= by + bh:
                pad = (bw - w) / 2
                if pad < MIN_PAD:
                    probs.append(
                        f"{pad:.1f}px side padding: {text!r} needs ~{w:.0f}px in a {bw}px box")
                break
    return probs


# ---------------------------------------------------------------- driver

def main():
    pattern = sys.argv[1] if len(sys.argv) > 1 else DIAGRAMS
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"no diagrams matched {pattern!r}", file=sys.stderr)
        return 1
    failed = 0
    for f in files:
        page = pathlib.Path(f).read_text()
        svg = page[page.index('</defs>'):page.index('</svg>')]   # skip the marker defs
        probs, nm, nn, nc = check_geometry(svg)
        probs += check_textfit(svg)
        name = pathlib.Path(f).name
        if probs:
            failed += 1
            print(f"FAIL {name}")
            for p in probs:
                print("       -", p)
        else:
            print(f"OK   {name}  masks={nm} nodes={nn} conns={nc}")
    print(f"\n{len(files) - failed}/{len(files)} clean")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
