#!/usr/bin/env python3
"""SwiftGibs in-game feedback relay.

The game engine cannot speak TLS, so it POSTs a plain-HTTP form to this relay
(behind nginx: 0.0.0.0:8300/feedback -> 127.0.0.1:8301). The relay validates,
rate-limits per client IP, and opens a GitHub issue on SalukiSwift/swiftgibs
using a server-side fine-grained token (issues-only). The token never leaves
the box and never ships in the client - that is the whole point of the relay.

v2: the client also sends game telemetry (map, mode, position, fps, match
stats) and an optional JPEG screenshot taken at the moment the player pressed
the feedback hotkey. The screenshot is stored under the salukiswift.com web
root and embedded in the issue by URL (the GitHub API cannot take uploads).
A bad or oversized screenshot never fails the feedback - it is just dropped.

Response body: ONE short plaintext line - the game shows the first line of the
HTTP body verbatim as the in-game status message.
"""
import json
import time
import urllib.request
import uuid
from pathlib import Path

from flask import Flask, request

app = Flask(__name__)

TOKEN_PATH = Path("/opt/swiftgibs-feedback/token")
SHOTS_DIR = Path("/var/www/salukiswift/feedback-shots")
SHOTS_URL = "https://salukiswift.com/feedback-shots"
REPO = "SalukiSwift/swiftgibs"
CATEGORIES = {"bug", "idea", "other"}
MAX_TEXT = 4000
MAX_NAME = 32
MAX_SHORT = 24            # version / platform fields
MAX_TELEMETRY = 200       # map/mode/pos/fps/info fields
TITLE_SNIPPET = 60        # first-line length used in the issue title
MAX_SHOT = 8 * 1024 * 1024   # screenshot cap (bytes)
MAX_BODY = 10 * 1024 * 1024  # whole-request cap (nginx matches this)
RATE_LIMIT = 5            # accepted posts per IP per window
RATE_WINDOW = 3600.0      # seconds

app.config["MAX_CONTENT_LENGTH"] = MAX_BODY

_buckets = {}             # ip -> [unix timestamps]; in-memory, resets on restart


def _token():
    return TOKEN_PATH.read_text().strip()


def _allowed(ip):
    now = time.time()
    stamps = [t for t in _buckets.get(ip, []) if now - t < RATE_WINDOW]
    if len(stamps) >= RATE_LIMIT:
        _buckets[ip] = stamps
        return False
    stamps.append(now)
    _buckets[ip] = stamps
    return True


def _save_shot():
    """Store an attached screenshot; returns its public URL or None.
    Never raises past this function - a broken shot must not kill the report."""
    f = request.files.get("shot")
    if f is None:
        return None
    try:
        data = f.read(MAX_SHOT + 1)
        if len(data) > MAX_SHOT:
            return None
        if not data.startswith(b"\xff\xd8\xff"):   # JPEG magic only
            return None
        SHOTS_DIR.mkdir(parents=True, exist_ok=True)
        name = f"{uuid.uuid4().hex}.jpg"
        (SHOTS_DIR / name).write_bytes(data)
        return f"{SHOTS_URL}/{name}"
    except Exception:
        app.logger.exception("screenshot save failed")
        return None


def post_issue(title, body, labels):
    """POST to the GitHub issues API; returns the HTTP status. Stubbed in tests."""
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/issues",
        data=json.dumps({"title": title, "body": body, "labels": labels}).encode(),
        headers={
            "Authorization": f"Bearer {_token()}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.status


@app.errorhandler(413)
def too_large(e):
    return "too big - try without the screenshot\n", 413


@app.post("/feedback")
def feedback():
    ip = request.headers.get("X-Real-IP", request.remote_addr or "?")
    name = (request.form.get("name") or "").strip()[:MAX_NAME] or "anonymous"
    category = (request.form.get("category") or "").strip().lower()
    version = (request.form.get("version") or "?").strip()[:MAX_SHORT]
    platform = (request.form.get("platform") or "?").strip()[:MAX_SHORT]
    text = (request.form.get("text") or "").strip()

    def telemetry(field):
        return (request.form.get(field) or "").strip()[:MAX_TELEMETRY]

    game_map = telemetry("map")
    mode = telemetry("mode")
    pos = telemetry("pos")
    fps = telemetry("fps")
    info = telemetry("info")

    if category not in CATEGORIES:
        category = "other"
    if not text:
        return "nothing to send\n", 400
    if len(text) > MAX_TEXT:
        return "feedback too long\n", 400
    if not _allowed(ip):
        return "slow down - try again in a while\n", 429

    shot_url = _save_shot()

    title = f"[feedback] {category}: {text.splitlines()[0][:TITLE_SNIPPET]}"
    body = (
        f"**From:** {name} (in-game)\n"
        f"**Version:** {version} | **Platform:** {platform}\n\n"
        f"{text}\n"
    )
    if game_map or pos or fps or info:
        body += "\n---\n"
        if game_map or mode:
            where = game_map or "?"
            if mode:
                where += f" ({mode})"
            body += f"**Map:** {where}"
            if pos:
                body += f" @ {pos}"
            body += "\n"
        elif pos:
            body += f"**Position:** {pos}\n"
        if fps:
            body += f"**FPS:** {fps}\n"
        if info:
            body += f"**Match:** {info}\n"
    if shot_url:
        body += f"\n![screenshot]({shot_url})\n"

    try:
        status = post_issue(title, body, ["in-game-feedback", category])
    except Exception:
        app.logger.exception("github post failed")
        return "feedback server error - try again later\n", 502
    if status == 201:
        return "sent - thank you!\n", 200
    app.logger.error("github returned %s", status)
    return "feedback server error - try again later\n", 502


if __name__ == "__main__":
    _token()  # fail fast at startup if the token file is missing/unreadable
    app.run(host="127.0.0.1", port=8301)
