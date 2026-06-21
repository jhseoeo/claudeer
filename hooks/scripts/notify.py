"""Claude Code hook script — sends events to Claudeer app via Unix socket."""

import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claudeer.sock"


def read_session_title(transcript_path):
    """Return the current session title from the transcript JSONL, or None.

    Claude Code records the session title as append-only `ai-title` records
    ({"type": "ai-title", "aiTitle": "..."}); the last one is current. A
    `/rename` sets a custom title — its exact record shape is unconfirmed, so
    we also accept any record whose type mentions "title"/"rename".
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    title = None
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                low = line.lower()
                if "title" not in low and "rename" not in low:
                    continue
                try:
                    obj = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if not isinstance(obj, dict):
                    continue
                kind = obj.get("type", "")
                if kind == "ai-title":
                    val = obj.get("aiTitle")
                    if isinstance(val, str) and val.strip():
                        title = val.strip()
                elif isinstance(kind, str) and ("title" in kind or "rename" in kind):
                    for key in ("customTitle", "title", "aiTitle", "name"):
                        val = obj.get(key)
                        if isinstance(val, str) and val.strip():
                            title = val.strip()
                            break
    except OSError:
        return None
    return title


def session_name(hook_input, cwd, session_id):
    """Human-readable name for the session: live transcript title, else the
    SessionStart title, else the working-directory folder, else a short id."""
    title = read_session_title(hook_input.get("transcript_path"))
    if not title:
        start_title = hook_input.get("session_title")
        if isinstance(start_title, str) and start_title.strip():
            title = start_title.strip()
    if title:
        return title
    if cwd:
        base = os.path.basename(cwd.rstrip("/"))
        if base:
            return base
    return session_id[:8] if session_id else None


def send_event(state, session_id, pid, cwd, name):
    """Send an event to the Claudeer app. Fail silently if app isn't running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(2)
            sock.connect(SOCKET_PATH)
            payload = {"state": state, "session_id": session_id, "pid": pid}
            if cwd:
                payload["cwd"] = cwd
            if name:
                payload["name"] = name
            sock.send(json.dumps(payload).encode() + b"\n")
            sock.recv(1024)
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        pass


def main():
    hook_input = json.load(sys.stdin)
    session_id = hook_input.get("session_id", "unknown")
    hook_event = hook_input.get("hook_event_name", "")
    cwd = hook_input.get("cwd")
    pid = os.getppid()
    name = session_name(hook_input, cwd, session_id)

    if hook_event == "SessionStart":
        send_event("idle", session_id, pid, cwd, name)
    elif hook_event == "UserPromptSubmit":
        send_event("working", session_id, pid, cwd, name)
    elif hook_event == "Stop":
        send_event("idle", session_id, pid, cwd, name)
    elif hook_event == "Notification":
        send_event("idle", session_id, pid, cwd, name)

    print(json.dumps({"continue": True}))


if __name__ == "__main__":
    main()
