#!/usr/bin/env python3
"""Local-network phone controller bridge for Shadow Fighters."""

from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import json
import os
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent
STATE_FILE = ROOT / "phone_controls.txt"
LOCK = threading.Lock()
PLAYERS = {
    "1": {"buttons": set(), "seen": 0.0, "events": {}},
    "2": {"buttons": set(), "seen": 0.0, "events": {}},
}
ALLOWED = {
    "left", "right", "jump", "crouch", "punch", "kick", "block",
    "mount", "special1", "special2", "special3", "confirm",
}


def write_state():
    lines = []
    for player, state in PLAYERS.items():
        lines.append(f"p{player}_seen={int(state['seen'])}")
        for button in sorted(ALLOWED):
            lines.append(f"p{player}_{button}={1 if button in state['buttons'] else 0}")
            lines.append(f"p{player}_event_{button}={state['events'].get(button, 0)}")
    data = "\n".join(lines) + "\n"
    fd, temp_name = tempfile.mkstemp(prefix="phone_controls_", dir=ROOT)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(data)
        os.replace(temp_name, STATE_FILE)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


class ControllerHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path in ("/", "/controller"):
            self.path = "/controller.html"
        return super().do_GET()

    def do_POST(self):
        if urlparse(self.path).path != "/input":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_error(400, "Invalid JSON")
            return

        player = str(payload.get("player", "1"))
        buttons = payload.get("buttons", [])
        if player not in PLAYERS or not isinstance(buttons, list):
            self.send_error(400, "Invalid controller state")
            return

        with LOCK:
            new_buttons = {str(item) for item in buttons if item in ALLOWED}
            pressed = new_buttons - PLAYERS[player]["buttons"]
            for button in pressed:
                PLAYERS[player]["events"][button] = (
                    PLAYERS[player]["events"].get(button, 0) + 1
                )
            PLAYERS[player]["buttons"] = new_buttons
            PLAYERS[player]["seen"] = time.time()
            write_state()

        response = json.dumps({"ok": True, "player": player}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):
        if args and str(args[1]) != "200":
            super().log_message(format, *args)


if __name__ == "__main__":
    os.chdir(ROOT)
    with LOCK:
        write_state()
    server = ThreadingHTTPServer(("0.0.0.0", 8765), ControllerHandler)
    print("Shadow Fighters phone controller: http://0.0.0.0:8765", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
