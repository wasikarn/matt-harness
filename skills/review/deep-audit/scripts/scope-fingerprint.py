#!/usr/bin/env python3
"""Scope fingerprint for deep-audit: existence + content hash per scope path.

  scope-fingerprint.py snapshot <manifest>   # scope paths on stdin, one per line
  scope-fingerprint.py compare  <manifest>   # re-hash the manifest's paths

compare exits 0 when every path matches, 1 on any drift (one line per path:
"changed: P", "appeared: P", "disappeared: P"), 2 on a usage error or an
unreadable manifest. A directory hashes as the sorted walk of its files'
relative paths and bytes. mtime is ignored: only bytes count.
"""
import hashlib
import json
import os
import sys


def fingerprint(path):
    if not os.path.lexists(path):
        return None
    h = hashlib.sha256()
    if os.path.isdir(path):
        for d, dirs, files in os.walk(path):
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(d, name)
                h.update(os.path.relpath(full, path).encode() + b"\0")
                h.update(_file_digest(full).encode() + b"\0")
        return "dir:" + h.hexdigest()
    return _file_digest(path)


def _file_digest(path):
    if os.path.islink(path) and not os.path.exists(path):
        return "link:" + os.readlink(path)
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv):
    if len(argv) != 3 or argv[1] not in ("snapshot", "compare"):
        sys.stderr.write(__doc__)
        return 2
    mode, manifest = argv[1], argv[2]
    if mode == "snapshot":
        paths = [line.rstrip("\n") for line in sys.stdin if line.strip()]
        with open(manifest, "w") as f:
            json.dump({p: fingerprint(p) for p in paths}, f, indent=1, sort_keys=True)
        return 0
    try:
        with open(manifest) as f:
            before = json.load(f)
    except (OSError, ValueError) as e:
        sys.stderr.write("scope-fingerprint: cannot read manifest: %s\n" % e)
        return 2
    drift = 0
    for p in sorted(before):
        old, new = before[p], fingerprint(p)
        if old == new:
            continue
        drift = 1
        kind = "appeared" if old is None else "disappeared" if new is None else "changed"
        print("%s: %s" % (kind, p))
    return drift


if __name__ == "__main__":
    sys.exit(main(sys.argv))
