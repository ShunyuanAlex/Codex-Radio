"""Codex command-hook collector. Trust remains an explicit Codex UI action.
Only future hook input is read. No Codex history, credentials, network, audio or decisions.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import time
import uuid

EVENTS = {"SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SubagentStart", "SubagentStop"}

def short(value, limit=256):
    return value[:limit] if isinstance(value, str) else ""

def normalize(payload, host="local", now=None):
    if not isinstance(payload, dict):
        return None
    event = payload.get("hook_event_name")
    session = short(payload.get("session_id"))
    if event not in EVENTS or not session:
        return None
    turn = short(payload.get("turn_id"))
    tool_id = short(payload.get("tool_use_id"))
    agent = short(payload.get("agent_id")) or None
    name = short(payload.get("tool_name"))
    status = None
    if event == "PreToolUse":
        status = "editing" if name in ("apply_patch", "Edit", "Write") else "testing"
    elif event == "PostToolUse":
        status = "unknown"
        response = payload.get("tool_response")
        if isinstance(response, dict):
            if response.get("isError") is True:
                status = "blocked"
            elif name == "Bash":
                code = response.get("exit_code")
                if isinstance(code, int) and not isinstance(code, bool):
                    status = "success" if code == 0 else "blocked"
        # Do not parse free text or assume every MCP business operation succeeded.
    elif event == "PermissionRequest":
        status = "waiting"
    elif event == "Interrupt":
        status = "cancelled"
    elif event == "Stop":
        status = "complete"  # UI explicitly calls this a stop candidate, never success.
    elif event == "SubagentStart":
        status = "delegating"
    elif event == "SubagentStop":
        status = "unknown"
    identifier = uuid.uuid4().hex
    if event in ("PreToolUse", "PostToolUse") and turn and tool_id:
        identifier = hashlib.sha256(json.dumps([host,session,turn,tool_id,event,agent],ensure_ascii=True).encode()).hexdigest()
    return {"id":identifier,"host":short(host,128),"session":session,"turn":turn,"agent":agent,"toolUse":tool_id,"event":event,"status":status,"receivedAt":time.time() if now is None else now}

def save(event, spool):
    # Dedicated path explicitly specified in the reviewed hook command.
    root = Path(spool)
    if not root.is_absolute():
        raise ValueError("spool must be absolute")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("spool must be a private directory owned by this user")
    # Remove only this collector's ephemeral event files after a minute.
    cutoff = time.time() - 60
    for path in root.glob("event-*.json"):
        entry = path.lstat()
        if stat.S_ISREG(entry.st_mode) and entry.st_uid == os.getuid() and entry.st_mtime < cutoff:
            path.unlink()
    token = uuid.uuid4().hex
    temporary = root / (".pending-" + token)
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(event, stream, separators=(",", ":"), ensure_ascii=True)
    os.replace(temporary, root / ("event-" + token + ".json"))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spool", required=True)
    parser.add_argument("--host", default="local")
    args = parser.parse_args()
    try:
        raw = sys.stdin.buffer.read(1048577)
        if len(raw) <= 1048576:
            event = normalize(json.loads(raw), args.host)
            if event:
                save(event, args.spool)
    except Exception:
        # Generic diagnostics only: never echo payload or influence tool decisions.
        print("WingRadio collector could not record this event", file=sys.stderr)
    print("{}")

if __name__ == "__main__":
    main()
