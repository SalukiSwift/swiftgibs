"""Tests for the SwiftGibs feedback relay. Run: python3 test_app.py
Stdlib unittest only (mirrors the repo's no-pytest convention). The GitHub
poster is stubbed - no network, no real issues."""
import unittest

import app as relay


class RelayTest(unittest.TestCase):
    def setUp(self):
        relay._buckets.clear()
        self.calls = []

        def fake_post_issue(title, body, labels):
            self.calls.append((title, body, labels))
            return 201

        self._real = relay.post_issue
        relay.post_issue = fake_post_issue
        self.client = relay.app.test_client()

    def tearDown(self):
        relay.post_issue = self._real

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


if __name__ == "__main__":
    unittest.main()
