#!/usr/bin/env python3
"""SwiftGibs in-game feedback relay.

The game engine cannot speak TLS, so it POSTs a plain-HTTP form to this relay
(behind nginx: 0.0.0.0:8300/feedback -> 127.0.0.1:8301). The relay validates,
rate-limits per client IP, and opens a GitHub issue on SalukiSwift/swiftgibs
using a server-side fine-grained token (issues-only). The token never leaves
the box and never ships in the client - that is the whole point of the relay.

Response body: ONE short plaintext line - the game shows the first line of the
HTTP body verbatim as the in-game status message.
"""
import json
import time
import urllib.request
from pathlib import Path

from flask import Flask, request

app = Flask(__name__)

TOKEN_PATH = Path("/opt/swiftgibs-feedback/token")
REPO = "SalukiSwift/swiftgibs"
CATEGORIES = {"bug", "idea", "other"}
MAX_TEXT = 4000
MAX_NAME = 32
MAX_SHORT = 24            # version / platform fields
TITLE_SNIPPET = 60        # first-line length used in the issue title
RATE_LIMIT = 5            # accepted posts per IP per window
RATE_WINDOW = 3600.0      # seconds

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


@app.post("/feedback")
def feedback():
    ip = request.headers.get("X-Real-IP", request.remote_addr or "?")
    name = (request.form.get("name") or "").strip()[:MAX_NAME] or "anonymous"
    category = (request.form.get("category") or "").strip().lower()
    version = (request.form.get("version") or "?").strip()[:MAX_SHORT]
    platform = (request.form.get("platform") or "?").strip()[:MAX_SHORT]
    text = (request.form.get("text") or "").strip()

    if category not in CATEGORIES:
        category = "other"
    if not text:
        return "nothing to send\n", 400
    if len(text) > MAX_TEXT:
        return "feedback too long\n", 400
    if not _allowed(ip):
        return "slow down - try again in a while\n", 429

    title = f"[feedback] {category}: {text.splitlines()[0][:TITLE_SNIPPET]}"
    body = (
        f"**From:** {name} (in-game)\n"
        f"**Version:** {version} | **Platform:** {platform}\n\n"
        f"{text}\n"
    )
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
