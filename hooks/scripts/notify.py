"""Claude Code hook script — sends events to Claudeer app via Unix socket."""

import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claudeer.sock"


def send_event(state, session_id, pid, cwd):
    """Send an event to the Claudeer app. Fail silently if app isn't running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(2)
            sock.connect(SOCKET_PATH)
            payload = {"state": state, "session_id": session_id, "pid": pid}
            if cwd:
                payload["cwd"] = cwd
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

    if hook_event == "SessionStart":
        send_event("idle", session_id, pid, cwd)
    elif hook_event == "UserPromptSubmit":
        send_event("working", session_id, pid, cwd)
    elif hook_event == "Stop":
        send_event("idle", session_id, pid, cwd)
    elif hook_event == "Notification":
        send_event("idle", session_id, pid, cwd)

    print(json.dumps({"continue": True}))


if __name__ == "__main__":
    main()
