# Fast-path routing for irrecoverable.sh (GH #309): prints, per input line, how many "{" open a brace
# group that bash would expand. It follows bash's own scan (brace_gobbler, mirrored in _bracex.py): from
# a "{", a "}" closes the group only after a comma at the group's level or a ".." not followed by "}" has
# been seen; before that it is a literal character, so "{A=1}},git}" is a group and "{x}" is not. A nested
# group is read by its own "{" (the scan counts levels). Quotes are tracked from the "{" on, so a blank
# inside them ({A="x y",git}) does not end the scan; a quote that opened before the "{" is unknown, which
# only over-routes (safe). The scan ends at the command's closing quote, so it never leaves the command.
# The input is the hook's JSON payload, where a quote inside the command is escaped: a "{" followed by an
# unescaped quote is a JSON object of the payload itself, and "${" is a parameter; neither opens a group.
# tests/hooks/test-gates.sh enumerates every shape of { } , x . up to a length and checks that no shape
# _bracex expands is missed here. irrecoverable.sh sends payloads over 2000 characters to python instead
# (one scan per "{" is quadratic).
{
  n = length($0)
  for (i = 1; i <= n; i++) {
    if (substr($0, i, 1) != "{") continue
    if (i > 1 && substr($0, i - 1, 1) == "$") continue
    if (substr($0, i + 1, 1) == "\"") continue
    level = 0; commas = 0; dq = 0; sq = 0; bq = 0
    for (j = i + 1; j <= n; j++) {
      c = substr($0, j, 1)
      if (c == "\\") {
        e = substr($0, j + 1, 1)
        if (e == "\"") { if (!sq) dq = !dq }
        else if ((e == "n" || e == "t") && !(dq || sq || bq)) break
        j++
        continue
      }
      if (c == "\"") break
      if (c == "'" && !dq) { sq = !sq; continue }
      if (c == "`" && !dq && !sq) { bq = !bq; continue }
      if ((c == " " || c == "\t") && !(dq || sq || bq)) break
      if (c == "}" && level == 0 && commas) { hit++; break }
      if (c == "{") level++
      else if (c == "}") { if (level) level-- }
      else if (c == ",") { if (level == 0) commas++ }
      else if (c == "." && substr($0, j + 1, 1) == "." && substr($0, j + 2, 1) != "}") commas++
    }
  }
  print hit + 0; hit = 0
}
