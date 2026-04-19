"""Claude Code hook script — sends events to Claude Speaki app via Unix socket."""

import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-speaki.sock"


def send_event(event_type, session_id, pid=None):
    """Send an event to the Speaki app. Fail silently if app isn't running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(2)
            sock.connect(SOCKET_PATH)
            payload = {"event": event_type, "session_id": session_id}
            if pid is not None:
                payload["pid"] = pid
            sock.send(json.dumps(payload).encode() + b"\n")
            sock.recv(1024)
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        pass


def main():
    hook_input = json.load(sys.stdin)
    session_id = hook_input.get("session_id", "unknown")
    hook_event = hook_input.get("hook_event_name", "")

    if hook_event == "SessionStart":
        pid = os.getppid()
        send_event("session_start", session_id, pid)

    elif hook_event == "Stop":
        send_event("session_end", session_id)

    elif hook_event == "Notification":
        send_event("need_input", session_id)

    print(json.dumps({"continue": True}))


if __name__ == "__main__":
    main()
