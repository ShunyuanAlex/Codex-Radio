import importlib.util
import json
from pathlib import Path
import tempfile

spec=importlib.util.spec_from_file_location("collector",Path(__file__).with_name("collector.py"))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
base={"hook_event_name":"PostToolUse","session_id":"s","turn_id":"t","tool_use_id":"u","tool_name":"Bash","tool_response":{"exit_code":0},"tool_input":{"command":"PRIVATE"},"transcript_path":"PRIVATE","last_assistant_message":"PRIVATE"}
result=module.normalize(base,now=0)
assert result["status"]=="success" and "PRIVATE" not in json.dumps(result)
assert result["id"]==module.normalize(base,now=2)["id"]
assert result["id"]!=module.normalize(dict(base,hook_event_name="PreToolUse"))["id"]
assert module.normalize(dict(base,tool_response={"exit_code":7}))["status"]=="blocked"
assert module.normalize(dict(base,tool_response={"content":"Process exited with code 0"}))["status"]=="unknown"
assert module.normalize(dict(base,tool_name="mcp__x",tool_response={"isError":False}))["status"]=="unknown"
assert module.normalize(dict(base,tool_name="mcp__x",tool_response={"isError":True}))["status"]=="blocked"
assert module.normalize(dict(base,hook_event_name="Stop"))["status"]=="complete"
assert module.normalize(dict(base,hook_event_name="PermissionRequest"))["id"]!=module.normalize(dict(base,hook_event_name="PermissionRequest"))["id"]
assert module.normalize(dict(base,hook_event_name="SessionStart"))["status"] is None
assert module.normalize({"hook_event_name":"PreToolUse"}) is None
with tempfile.TemporaryDirectory(prefix="wing-radio-test-") as temporary:
    module.save(result,temporary)
    files=list(Path(temporary).glob("event-*.json"))
    assert len(files)==1 and json.loads(files[0].read_text())==result
print("12 collector checks passed using synthetic inputs and a temporary directory; no live hooks installed.")
