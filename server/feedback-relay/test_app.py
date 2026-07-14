"""Tests for the SwiftGibs feedback relay. Run: python3 test_app.py
Stdlib unittest only (mirrors the repo's no-pytest convention). The GitHub
poster is stubbed - no network, no real issues."""
import io
import pathlib
import tempfile
import unittest

import app as relay

JPEG = b"\xff\xd8\xff\xe0" + b"fakejpegdata" * 4


class RelayTest(unittest.TestCase):
    def setUp(self):
        relay._buckets.clear()
        self.calls = []

        def fake_post_issue(title, body, labels):
            self.calls.append((title, body, labels))
            return 201

        self._real = relay.post_issue
        relay.post_issue = fake_post_issue
        self._shots = tempfile.TemporaryDirectory()
        self._real_shots = relay.SHOTS_DIR
        relay.SHOTS_DIR = pathlib.Path(self._shots.name)
        self.client = relay.app.test_client()

    def tearDown(self):
        relay.post_issue = self._real
        relay.SHOTS_DIR = self._real_shots
        self._shots.cleanup()

    def post(self, ip="1.2.3.4", **form):
        return self.client.post("/feedback", data=form,
                                headers={"X-Real-IP": ip})

    def test_happy_path_creates_issue(self):
        r = self.post(name="Swift", category="bug", version="1.1.4",
                      platform="windows", text="the thing broke\nmore detail")
        self.assertEqual(r.status_code, 200)
        self.assertIn(b"thank you", r.data)
        self.assertEqual(len(self.calls), 1)
        title, body, labels = self.calls[0]
        self.assertEqual(title, "[feedback] bug: the thing broke")
        self.assertIn("**From:** Swift (in-game)", body)
        self.assertIn("1.1.4", body)
        self.assertIn("windows", body)
        self.assertIn("more detail", body)
        self.assertEqual(labels, ["in-game-feedback", "bug"])

    def test_empty_text_rejected(self):
        r = self.post(name="Swift", category="bug", text="")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(len(self.calls), 0)

    def test_oversized_text_rejected(self):
        r = self.post(name="Swift", category="bug", text="x" * 4001)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(len(self.calls), 0)

    def test_unknown_category_coerced_to_other(self):
        r = self.post(name="Swift", category="'; DROP TABLE", text="hi")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self.calls[0][2], ["in-game-feedback", "other"])

    def test_long_name_truncated(self):
        r = self.post(name="N" * 100, category="idea", text="hi")
        self.assertEqual(r.status_code, 200)
        self.assertIn("N" * 32 + " (in-game)", self.calls[0][1])
        self.assertNotIn("N" * 33, self.calls[0][1])

    def test_missing_name_defaults_anonymous(self):
        r = self.post(category="idea", text="hi")
        self.assertEqual(r.status_code, 200)
        self.assertIn("**From:** anonymous", self.calls[0][1])

    def test_rate_limit_per_ip(self):
        for i in range(relay.RATE_LIMIT):
            r = self.post(text=f"msg {i}")
            self.assertEqual(r.status_code, 200)
        r = self.post(text="one too many")
        self.assertEqual(r.status_code, 429)
        self.assertIn(b"slow down", r.data)
        # a different IP is not affected
        r = self.post(ip="5.6.7.8", text="different player")
        self.assertEqual(r.status_code, 200)

    def test_github_failure_is_502(self):
        def boom(title, body, labels):
            raise OSError("github down")
        relay.post_issue = boom
        r = self.post(text="hi")
        self.assertEqual(r.status_code, 502)

    def test_title_first_line_truncated_to_60(self):
        r = self.post(category="bug", text="A" * 200)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self.calls[0][0], "[feedback] bug: " + "A" * 60)

    # ---- v2: telemetry + screenshot ----

    def test_telemetry_lands_in_body(self):
        r = self.post(text="laggy here", map="ot", mode="instagib",
                      pos="512 301 88", fps="187",
                      info="frags 12 deaths 3 damage 1200 shots 15 beststreak 7")
        self.assertEqual(r.status_code, 200)
        body = self.calls[0][1]
        self.assertIn("**Map:** ot (instagib)", body)
        self.assertIn("512 301 88", body)
        self.assertIn("187", body)
        self.assertIn("frags 12 deaths 3", body)

    def test_no_telemetry_no_block(self):
        r = self.post(text="hi")
        self.assertEqual(r.status_code, 200)
        self.assertNotIn("**Map:**", self.calls[0][1])
        self.assertNotIn("Telemetry", self.calls[0][1])

    def test_screenshot_saved_and_linked(self):
        r = self.client.post("/feedback",
                             data={"text": "look at this",
                                   "shot": (io.BytesIO(JPEG), "feedbackshot.jpg")},
                             headers={"X-Real-IP": "1.2.3.4"},
                             content_type="multipart/form-data")
        self.assertEqual(r.status_code, 200)
        saved = list(relay.SHOTS_DIR.glob("*.jpg"))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_bytes(), JPEG)
        self.assertIn(f"{relay.SHOTS_URL}/{saved[0].name}", self.calls[0][1])
        self.assertIn("![screenshot]", self.calls[0][1])

    def test_bad_magic_shot_ignored_feedback_still_sent(self):
        r = self.client.post("/feedback",
                             data={"text": "hi",
                                   "shot": (io.BytesIO(b"not a jpeg"), "x.jpg")},
                             headers={"X-Real-IP": "1.2.3.4"},
                             content_type="multipart/form-data")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(list(relay.SHOTS_DIR.iterdir()), [])
        self.assertNotIn("![screenshot]", self.calls[0][1])

    def test_oversize_shot_ignored_feedback_still_sent(self):
        big = b"\xff\xd8\xff\xe0" + b"x" * (relay.MAX_SHOT + 1)
        r = self.client.post("/feedback",
                             data={"text": "hi",
                                   "shot": (io.BytesIO(big), "x.jpg")},
                             headers={"X-Real-IP": "1.2.3.4"},
                             content_type="multipart/form-data")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(list(relay.SHOTS_DIR.iterdir()), [])
        self.assertNotIn("![screenshot]", self.calls[0][1])

    def test_413_returns_short_plaintext(self):
        r = self.client.post("/feedback", data=b"x" * (relay.MAX_BODY + 1024),
                             content_type="application/x-www-form-urlencoded")
        self.assertEqual(r.status_code, 413)
        self.assertLess(len(r.data), 80)
        self.assertNotIn(b"<", r.data)


class VersionTest(unittest.TestCase):
    def setUp(self):
        relay._version_cache.update(tag=None, at=0.0)
        self.fetches = 0

        def fake_fetch():
            self.fetches += 1
            return "v9.9.9"

        self._real = relay.fetch_latest_tag
        relay.fetch_latest_tag = fake_fetch
        self.client = relay.app.test_client()

    def tearDown(self):
        relay.fetch_latest_tag = self._real
        relay._version_cache.update(tag=None, at=0.0)

    def test_returns_latest_tag(self):
        r = self.client.get("/version")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, b"v9.9.9\n")

    def test_cached_within_ttl(self):
        self.client.get("/version")
        self.client.get("/version")
        self.assertEqual(self.fetches, 1)

    def test_fetch_failure_without_cache_is_503(self):
        def boom():
            raise OSError("github down")
        relay.fetch_latest_tag = boom
        r = self.client.get("/version")
        self.assertEqual(r.status_code, 503)

    def test_fetch_failure_serves_stale_cache(self):
        self.client.get("/version")                    # primes the cache
        relay._version_cache["at"] = 0.0               # expire it

        def boom():
            raise OSError("github down")
        relay.fetch_latest_tag = boom
        r = self.client.get("/version")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, b"v9.9.9\n")


if __name__ == "__main__":
    unittest.main()
