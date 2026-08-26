"""Inject the eight shipped diagram SVGs into the artifact page. One source, two homes."""
import re, pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent          # docs/diagrams/, next to src/
files = sorted(SRC.glob('0*.html'))
assert len(files) == 8, files

HERE = pathlib.Path(__file__).resolve().parent
tpl = (HERE / 'artifact.tpl.html').read_text()
for i, f in enumerate(files, 1):
    html = f.read_text()
    svg = html[html.index('<svg'):html.index('</svg>') + 6]
    assert 'viewBox' in svg and '<title' in svg, f.name
    # Eight SVGs share one document here, so the marker ids have to be namespaced —
    # otherwise every url(#arrow) in the page resolves to diagram 1's marker.
    for mid in ('arrow-accent', 'arrow-link', 'arrow'):
        svg = svg.replace('id="%s"' % mid, 'id="d%d-%s"' % (i, mid))
        svg = svg.replace('url(#%s)' % mid, 'url(#d%d-%s)' % (i, mid))
    tpl = tpl.replace('{{D%d}}' % i, svg)
assert '{{D' not in tpl

# the mermaid <pre> wrappers are gone; the SVG sits straight on the plate
tpl = re.sub(r'<pre class="mermaid">(<svg.*?</svg>)</pre>', r'\1', tpl, flags=re.S)
assert 'class="mermaid"' not in tpl

out = HERE / 'harness-workflow-maps.html'
out.write_text(tpl)
print('built', len(tpl), 'bytes,', tpl.count('<svg'), 'inline SVGs')
