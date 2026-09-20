# Fixture for check 74: REGRESSED to a truthiness gate -- an empty-string or
# null agent_id would silently skip this check. No "agent_id" in d idiom
# anywhere in this file.
agent_id = d.get("agent_id")
if not agent_id:
    pass
