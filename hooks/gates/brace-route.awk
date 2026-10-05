# Fast-path routing for irrecoverable.sh (GH #309): prints, per input line, how many brace groups can
# expand, i.e. a closed {...} (not "${...}") with a "," or ".." at its own top level. A nested group
# counts toward its parent only through its own commas: r{{x},m} is one expanding group (the outer),
# which a single-level pattern cannot see. Quotes are not read, so a quoted comma over-routes (safe).
# The input is the hook's JSON payload, where a quote inside the command is escaped: a "{" followed by an
# unescaped quote is a JSON object of the payload itself, not a brace group, and is skipped like "${".
# tests/hooks/test-gates.sh enumerates every shape of { } , x up to a length and checks that no shape
# _bracex expands is missed here.
{
  n = length($0); d = 0; prev = ""
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (c == "{") { d++; par[d] = (prev == "$") || (substr($0, i + 1, 1) == "\""); com[d] = 0 }
    else if (c == "}") { if (d > 0) { if (com[d] && !par[d]) hit++; d-- } }
    else if (c == "," || (c == "." && substr($0, i + 1, 1) == ".")) { if (d > 0) com[d] = 1 }
    prev = c
  }
  print hit + 0; hit = 0
}
