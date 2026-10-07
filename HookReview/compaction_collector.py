"""Metadata-only compaction hook collector; does not read transcript or summary text."""
import argparse
import json
import os
from pathlib import Path
import stat
import sys
import time
import uuid

EVENTS = {"PreCompact", "PostCompact"}

def short(value, limit=256):
    return value[:limit] if isinstance(value, str) else ""

def normalize(payload, host="local", now=None):
    if not isinstance(payload, dict):
        return None
    event = payload.get("hook_event_name")
    session = short(payload.get("session_id"))
    if event not in EVENTS or not session:
        return None
    # Only event identity and correlation metadata cross the boundary.
    # Multiple compactions within one turn are legitimate; never deduplicate by turn alone.
    return {"id": uuid.uuid4().hex, "host": short(host, 128), "session": session,
            "turn": short(payload.get("turn_id")), "agent": short(payload.get("agent_id")) or None,
            "toolUse": "", "event": event, "status": "compacting" if event == "PreCompact" else None,
            "receivedAt": time.time() if now is None else now}

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
        print("Codex Radio compaction collector could not record this event", file=sys.stderr)
    # Observe only; never block, alter or inject content into compaction.
    print("{}")

if __name__ == "__main__":
    main()
