# Diagram source

The eight HTML files in `docs/diagrams/` are generated, not hand-edited. Edit them here and
regenerate, or the next regeneration silently reverts your change.

```bash
python3 docs/diagrams/src/build.py      # writes ../01-overall.html .. ../08-memory-loop.html
python3 docs/diagrams/src/check.py      # geometry + text fit, all eight
```

| File | What it holds |
|---|---|
| `dd.py` | Drawing primitives: nodes, ovals, diamonds, rounded elbow connectors, masked labels, the legend strip, and the page template. Colours and type follow the diagram-design default editorial skin. |
| `build.py` | The eight diagrams themselves. One block per diagram: coordinates, labels, legend, caption, and the accessible `<title>`/`<desc>` pair. |
| `check.py` | Two verification passes. See below. |

## What `check.py` catches

**Geometry.** Label masks must clear their connector by 6 to 14px and must not sit under a
node drawn after them, and every rect coordinate lands on the 4px grid. This overlaps
diagram-design's own `self_check.py`, which is worth running too:

```bash
python3 ~/.claude/plugins/cache/diagram-design/diagram-design/*/skills/diagram-design/scripts/self_check.py docs/diagrams/07-orchestrate.html
```

**Text fit.** Whether each in-box label actually fits its box. Nothing else measures this.
`self_check.py` and the geometry pass both work on coordinates, so a sublabel one character
too long passes both while rendering flush against its border. That shipped in
`07-orchestrate`'s validation chain and survived several commits before anyone looked closely
at a screenshot.

Advance widths are estimated at 0.60em for Geist Mono and 0.56em for Geist sans, so the pass
flags anything with under 6px of side padding rather than only true overflow.

## Two things the checkers cannot see

**Geist Mono ligates `--` into an em dash.** Any SVG label containing a double hyphen renders
wrong. `--strict` and `--no-verify` both had to be reworded. Grep new label text for `--`
before you commit it.

**Mermaid and SVG are kept in sync by hand.** `docs/workflow-diagrams.md` carries the same
eight diagrams as mermaid, and `README.md` mirrors section 1 of that file byte for byte.
Nothing checks either pair. When you change a label here, change it there.
