"""diagram-design primitive emitters. Default skin, style-guide.md tokens."""
PAPER="#f5f5f5"; INK="#2d3142"; MUTED="#4f5d75"; SOFT="#7a8399"; ACCENT="#eb6c36"
SANS="'Geist', sans-serif"; MONO="'Geist Mono', monospace"
R=8

KIND={
 "step":   ("#ffffff","#2d3142",None),
 "focal":  ("rgba(235,108,54,0.08)","#eb6c36",None),
 "store":  ("rgba(45,49,66,0.05)","#4f5d75",None),
 "ext":    ("rgba(45,49,66,0.03)","rgba(45,49,66,0.30)",None),
 "input":  ("rgba(79,93,117,0.10)","#7a8399",None),
 "opt":    ("rgba(45,49,66,0.02)","rgba(45,49,66,0.20)","4,3"),
}

def esc(s): return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

def node(x,y,w,h,name,sub=None,kind="step",rx=6,tag=None):
    fill,stroke,dash=KIND[kind]
    d=f' stroke-dasharray="{dash}"' if dash else ""
    cx=x+w//2
    ny = y+h//2+2 if not sub else y+h//2-4
    out=[f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{PAPER}"/>',
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="1"{d}/>']
    if tag:
        out.append(f'<rect x="{x+8}" y="{y+8}" width="24" height="12" rx="2" fill="transparent" stroke="{stroke}" stroke-opacity="0.4" stroke-width="0.8"/>')
        out.append(f'<text x="{x+20}" y="{y+17}" fill="{stroke}" fill-opacity="0.8" font-size="7" font-family="{MONO}" text-anchor="middle" letter-spacing="0.08em">{esc(tag)}</text>')
    out.append(f'<text x="{cx}" y="{ny}" fill="{INK}" font-size="12" font-weight="600" font-family="{SANS}" text-anchor="middle">{esc(name)}</text>')
    if sub:
        out.append(f'<text x="{cx}" y="{ny+16}" fill="{MUTED}" font-size="9" font-family="{MONO}" text-anchor="middle">{esc(sub)}</text>')
    return "\n      ".join(out)

def oval(x,y,w,h,name,sub=None,kind="ext"):
    return node(x,y,w,h,name,sub,kind,rx=h//2)

def diamond(cx,cy,hw,hh,lines,kind="step"):
    fill,stroke,_=KIND[kind]
    pts=f"{cx},{cy-hh} {cx+hw},{cy} {cx},{cy+hh} {cx-hw},{cy}"
    out=[f'<polygon points="{pts}" fill="{PAPER}"/>',
         f'<polygon points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="1"/>']
    n=len(lines); y0=cy-((n-1)*7)+3
    for i,l in enumerate(lines):
        out.append(f'<text x="{cx}" y="{y0+i*14}" fill="{INK}" font-size="11" font-weight="600" font-family="{SANS}" text-anchor="middle">{esc(l)}</text>')
    return "\n      ".join(out)

def _stroke(a,dash):
    c=ACCENT if a else MUTED
    m="arrow-accent" if a else "arrow"
    w="1.4" if a else ("1" if dash else "1.2")
    d=' stroke-dasharray="4,3"' if dash else ""
    return f'stroke="{c}" stroke-width="{w}"{d} marker-end="url(#{m})"'

def line(x1,y1,x2,y2,accent=False,dash=False):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" {_stroke(accent,dash)}/>'

def _p(d,accent,dash):
    return f'<path d="{d}" fill="none" {_stroke(accent,dash)}/>'

def hv(x1,y1,x2,y2,accent=False,dash=False):
    """horizontal from (x1,y1) to x2, then vertical to y2. One rounded bend."""
    sx=1 if x2>x1 else -1; sy=1 if y2>y1 else -1
    return _p(f"M {x1},{y1} H {x2-R*sx} Q {x2},{y1} {x2},{y1+R*sy} V {y2}",accent,dash)

def vh(x1,y1,x2,y2,accent=False,dash=False):
    """vertical from (x1,y1) to y2, then horizontal to x2."""
    sx=1 if x2>x1 else -1; sy=1 if y2>y1 else -1
    return _p(f"M {x1},{y1} V {y2-R*sy} Q {x1},{y2} {x1+R*sx},{y2} H {x2}",accent,dash)

def vhv(x1,y1,x2,y2,my,accent=False,dash=False):
    s1=1 if my>y1 else -1; sx=1 if x2>x1 else -1; s2=1 if y2>my else -1
    return _p(f"M {x1},{y1} V {my-R*s1} Q {x1},{my} {x1+R*sx},{my} H {x2-R*sx} Q {x2},{my} {x2},{my+R*s2} V {y2}",accent,dash)

def hvh(x1,y1,x2,y2,mx,accent=False,dash=False):
    s1=1 if mx>x1 else -1; sy=1 if y2>y1 else -1; s2=1 if x2>mx else -1
    return _p(f"M {x1},{y1} H {mx-R*s1} Q {mx},{y1} {mx},{y1+R*sy} V {y2-R*sy} Q {mx},{y2} {mx+R*s2},{y2} H {x2}",accent,dash)

def _mask(x0,y_base,w,text,accent):
    x0=round(x0/4)*4; y_base=round((y_base-9)/4)*4+9   # §7: every rect coord on the 4px grid
    c=ACCENT if accent else MUTED
    return (f'<rect x="{x0}" y="{y_base-9}" width="{w}" height="12" rx="2" fill="{PAPER}"/>\n      '
            f'<text x="{x0+w//2}" y="{y_base}" fill="{c}" font-size="8" font-family="{MONO}" '
            f'text-anchor="middle" letter-spacing="0.12em">{esc(text)}</text>')

def _w(text,w):
    w=w or max(24,len(text)*6+8)
    return (w+3)//4*4

def hlabel(cx,line_y,text,accent=False,w=None,below=False):
    """Label for a HORIZONTAL connector. Mask sits 9px clear of the stroke."""
    w=_w(text,w)
    y=line_y+17 if below else line_y-11      # mask edge lands on the 4px grid, 8px clear
    return _mask(cx-w//2,y,w,text,accent)

def vlabel(line_x,cy,text,accent=False,w=None,left=False):
    """Label for a VERTICAL connector. Mask sits 8px clear of the stroke."""
    w=_w(text,w)
    x0=line_x-8-w if left else line_x+8
    return _mask(x0,cy+5,w,text,accent)      # mask top = cy-4, on the grid

def steptag(x,y,label):
    """Sequence number as an eyebrow above the node, clear of a long node name."""
    return (f'<text x="{x}" y="{y-12}" fill="{MUTED}" font-size="8" font-family="{MONO}" '
            f'letter-spacing="0.18em">{esc(label)}</text>')

def legend(y,title,items,x0=40,x1=920):
    out=[f'<line x1="{x0}" y1="{y}" x2="{x1}" y2="{y}" stroke="rgba(45,49,66,0.10)" stroke-width="0.8"/>',
         f'<text x="{x0}" y="{y+16}" fill="{MUTED}" font-size="8" font-family="{MONO}" letter-spacing="0.18em">{esc(title)}</text>']
    ly=y+36
    for x,kind,label in items:
        x=round(x/4)*4
        if kind=="arrow" or kind=="arrow-accent" or kind=="arrow-dash":
            a=kind=="arrow-accent"; d=kind=="arrow-dash"
            out.append(f'<line x1="{x}" y1="{ly+6}" x2="{x+28}" y2="{ly+6}" {_stroke(a,d)}/>')
            tx=x+36
        else:
            fill,stroke,dash=KIND[kind]
            dd=f' stroke-dasharray="{dash}"' if dash else ""
            out.append(f'<rect x="{x}" y="{ly}" width="24" height="12" rx="2" fill="{fill}" stroke="{stroke}" stroke-width="1"{dd}/>')
            tx=x+32
        out.append(f'<text x="{tx}" y="{ly+10}" fill="{MUTED}" font-size="8.5" font-family="{SANS}">{esc(label)}</text>')
    return "\n      ".join(out)

TPL='''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
  <link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    :root {{
      --color-paper:   #f5f5f5;
      --color-ink:     #2d3142;
      --color-muted:   #4f5d75;
      --color-accent:  #eb6c36;
      --font-sans:     'Geist', system-ui, sans-serif;
      --font-serif:    'Instrument Serif', serif;
      --font-mono:     'Geist Mono', ui-monospace, monospace;
    }}
    body {{
      font-family: var(--font-sans);
      background: var(--color-paper);
      color: var(--color-ink);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 3rem 2rem;
    }}
    .frame {{ max-width: 1200px; width: 100%; }}
    .eyebrow {{
      font-family: var(--font-mono);
      font-size: 0.66rem;
      font-weight: 500;
      letter-spacing: 0.18em;
      text-transform: uppercase;
      color: var(--color-muted);
      margin-bottom: 0.5rem;
    }}
    h1 {{
      font-family: var(--font-serif);
      font-size: clamp(1.5rem, 2.4vw + 0.75rem, 2rem);
      font-weight: 400;
      letter-spacing: -0.02em;
      line-height: 1.15;
      color: var(--color-ink);
      margin-bottom: 1.5rem;
    }}
    svg {{ width: 100%; min-width: 900px; display: block; }}
    .note {{
      font-size: 0.875rem;
      line-height: 1.55;
      color: var(--color-muted);
      max-width: 62ch;
      margin-top: 1.25rem;
      padding-top: 1rem;
      border-top: 1px solid rgba(45,49,66,0.12);
    }}
  </style>
</head>
<body>
  <div class="frame">
    <p class="eyebrow">{eyebrow}</p>
    <h1>{title}</h1>

    <svg viewBox="0 0 960 600" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="{slug}-title {slug}-desc">
      <title id="{slug}-title">{title}</title>
      <desc id="{slug}-desc">{desc}</desc>
      <defs>
        <marker id="arrow" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><polygon points="0 0, 8 3, 0 6" fill="#4f5d75"/></marker>
        <marker id="arrow-accent" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><polygon points="0 0, 8 3, 0 6" fill="#eb6c36"/></marker>
        <marker id="arrow-link" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><polygon points="0 0, 8 3, 0 6" fill="#2e5aa8"/></marker>
      </defs>

      <rect width="100%" height="100%" fill="#f5f5f5"/>

      {body}
    </svg>

    <p class="note">{note}</p>
  </div>
</body>
</html>
'''

def page(path,slug,eyebrow,title,desc,parts,note=""):
    body="\n\n      ".join(parts)
    open(path,"w").write(TPL.format(slug=slug,eyebrow=eyebrow,title=esc(title),desc=esc(desc),
                                    body=body,note=esc(note)))
    return path
