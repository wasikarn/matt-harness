# Fixture for check 74: the idiom appears ONLY inside a docstring, never in code.
"""Gate note: the check is `"agent_id" in d` and `"agent_id" not in d` here."""
if d.get("agent_id") and _nested_spawn(cmd):
    pass
if d.get("agent_id") and _nested_spawn(body):
    pass
