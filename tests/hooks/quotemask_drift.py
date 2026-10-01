#!/usr/bin/env python3
# Drift check: the inline fallback mask copies in subagent-git-guard.py and
# test-integrity.py must produce the same output as the shared _quotemask.py.
# Prints one DRIFT line per disagreement; prints OK when all agree.
import ast, os, sys

root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
gates = os.path.join(root, "hooks", "gates")
sys.path.insert(0, gates)
from _quotemask import mask_quotes

CORPUS = [
    "git reset --hard",
    "echo 'a; b' ; git stash",
    "echo hi # don't\ngit stash",
    "echo x\\\n#y; git stash",
    "echo x \\\n#y; git stash",
    "echo x\n#y; git stash",
    "echo x\\\\\n#y; git stash",
    "echo x\\\\\\\n#y; git stash",
    "\\\ngit stash",
    "echo \\\ngit stash",
    "echo 'a'\\\n#y; git stash",
    "git\\\nstash",
    "x\\\n\\\n#y",
    "echo \\'x\\' ; git stash",
    "echo $'a\\'b' ; git stash",
    "a\\",
    "(true)#c\ngit stash",
]


def inline(path, name):
    tree = ast.parse(open(path).read())
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == name:
            ns = {}
            exec(compile(ast.Module([node], []), path, "exec"), ns)
            return ns[name]
    raise SystemExit("DRIFT: %s not found in %s" % (name, path))


copies = [
    ("subagent-git-guard.py", inline(os.path.join(gates, "subagent-git-guard.py"), "_mask_quotes")),
    ("test-integrity.py", inline(os.path.join(gates, "test-integrity.py"), "_mask_quotes_bash")),
]
bad = 0
for label, fn in copies:
    for s in CORPUS:
        if fn(s) != mask_quotes(s):
            print("DRIFT %s on %r: %r != %r" % (label, s, fn(s), mask_quotes(s)))
            bad += 1
print("OK" if not bad else "FAIL")
sys.exit(1 if bad else 0)
