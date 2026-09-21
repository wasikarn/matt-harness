# Fixture for check 74: one of the two _nested_spawn call sites regressed to truthiness.
if ("agent_id" in d) and _nested_spawn(cmd):
    pass
if d.get("agent_id") and _nested_spawn(body):
    pass
