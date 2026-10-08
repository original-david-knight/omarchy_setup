"""Observable calendar helper behavior with a mocked Everything App response."""

import contextlib
from datetime import datetime, timedelta
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.error
import urllib.parse
from unittest.mock import patch


sys.dont_write_bytecode = True
HELPER = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins/david.meeting/calendar"
loader = importlib.machinery.SourceFileLoader("meeting_calendar", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
calendar = importlib.util.module_from_spec(spec)
loader.exec_module(calendar)


def event(event_id, **changes):
    row = {"id": event_id, "title": "Work review", "account": "work", "all_day": False,
           "declined": False, "starts_at": "2026-10-02T09:00:00-07:00",
           "ends_at": "2026-10-02T09:30:00-07:00", "calendar_name": "Work", "location": "Room 2"}
    row.update(changes)
    return row


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def read(self, *_):
        return self.body


WORK_CALENDARS = {"calendars": [
    {"account": "work", "calendar_id": "work@example.test", "enabled": True},
    {"account": "work", "calendar_id": "hidden@example.test", "enabled": False},
    {"account": "personal", "calendar_id": "work@example.test", "enabled": True},
    {"account": "personal", "calendar_id": "home@example.test", "enabled": True}]}


class FakeOpener:
    def __init__(self, bodies=None, error=None):
        self.bodies = bodies or {}
        self.error = error
        self.requests = []

    def open(self, request, timeout):
        self.requests.append((request, timeout))
        if self.error:
            raise self.error
        return FakeResponse(json.dumps(self.bodies[urllib.parse.urlsplit(request.full_url).path]).encode())


class CalendarCliTests(unittest.TestCase):
    def run_calendar(self, body=None, error=None, config=None, calendars=WORK_CALENDARS):
        opener = FakeOpener({"/api/today": body, "/api/today/calendars": calendars}, error)
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "config.json").write_text(json.dumps(config or {
                "service_url": "https://calendar.example.test/", "token": "fixture-secret"}))
            output = io.StringIO()
            with patch.dict(os.environ, {"EVERYTHING_AGENT_CONFIG_DIR": folder}), \
                 patch.object(calendar.urllib.request, "build_opener", return_value=opener), \
                 contextlib.redirect_stdout(output):
                code = calendar.main()
        return code, json.loads(output.getvalue()), output.getvalue(), opener.requests

    def today(self, events, **changes):
        body = {"date": datetime.now().astimezone().date().isoformat(),
                "connected": True, "events": events, "last_sync": "9:15 AM", "last_error": ""}
        body.update(changes)
        return body

    def test_returns_all_eligible_events_including_ended_and_uses_only_today_routes(self):
        rows = [event("later", starts_at="2026-10-02T16:00:00-07:00", ends_at="2026-10-02T16:30:00-07:00"),
                event("ended"), event("personal", account="personal"),
                event("all-day", all_day=True), event("declined", declined=True),
                event("canceled", canceled=True)]
        code, result, _, requests = self.run_calendar(self.today(rows))
        self.assertEqual(code, 0)
        self.assertEqual(result, {"status": "ready", "date": self.today([])["date"],
            "events": [
                {"id": "ended", "title": "Work review", "starts_at": "2026-10-02T09:00:00-07:00",
                 "ends_at": "2026-10-02T09:30:00-07:00", "calendar_name": "Work", "location": "Room 2",
                 "meet_url": "", "html_link": ""},
                {"id": "later", "title": "Work review", "starts_at": "2026-10-02T16:00:00-07:00",
                 "ends_at": "2026-10-02T16:30:00-07:00", "calendar_name": "Work", "location": "Room 2",
                 "meet_url": "", "html_link": ""}],
            "last_sync": "9:15 AM", "warning": ""})
        self.assertEqual([request.full_url for request, _ in requests],
                         ["https://calendar.example.test/api/today", "https://calendar.example.test/api/today/calendars"])
        for request, timeout in requests:
            self.assertEqual(request.get_header("Authorization"), "Bearer fixture-secret")
            self.assertEqual(timeout, 20)

    def test_work_calendar_shared_with_personal_account_still_counts_as_work(self):
        # The feed keeps one copy of an event both accounts can see, preferring
        # the personal account's, so a work meeting can arrive labeled personal.
        rows = [event("shared", account="personal", calendar_id="work@example.test"),
                event("home", account="personal", calendar_id="home@example.test"),
                event("hidden", account="personal", calendar_id="hidden@example.test")]
        code, result, _, _ = self.run_calendar(self.today(rows))
        self.assertEqual(code, 0)
        self.assertEqual([row["id"] for row in result["events"]], ["shared"])

    def test_passes_through_only_meet_and_calendar_links(self):
        rows = [event("meet", meet_url="https://meet.google.com/abc-defg-hij",
                      html_link="https://www.google.com/calendar/event?eid=bWVldA"),
                event("zoom", meet_url="https://zoom.example.test/j/1",
                      html_link="https://calendar.google.com/calendar/event?eid=em9vbQ"),
                event("lookalike", meet_url="https://meet.google.com.example.test/x",
                      html_link="https://www.google.com/search?q=calendar"),
                event("unsafe", meet_url="https://meet.google.com/abc def", html_link=["not", "text"])]
        code, result, _, _ = self.run_calendar(self.today(rows))
        self.assertEqual(code, 0)
        self.assertEqual({row["id"]: (row["meet_url"], row["html_link"]) for row in result["events"]}, {
            "meet": ("https://meet.google.com/abc-defg-hij", "https://www.google.com/calendar/event?eid=bWVldA"),
            "zoom": ("", "https://calendar.google.com/calendar/event?eid=em9vbQ"),
            "lookalike": ("", ""), "unsafe": ("", "")})

    def test_unreadable_calendar_list_never_looks_like_an_empty_calendar(self):
        for listing in ({}, {"calendars": None}, {"calendars": ["work@example.test"]}, []):
            with self.subTest(listing=listing):
                code, result, _, _ = self.run_calendar(self.today([event("one")]), calendars=listing)
                self.assertEqual((code, result["status"]), (1, "error"))
                self.assertNotIn("events", result)

    def test_sync_warning_keeps_valid_events_but_never_exposes_server_error(self):
        code, result, raw, _ = self.run_calendar(self.today([event("one")], last_error="fixture-secret host.internal"))
        self.assertEqual(code, 0)
        self.assertEqual(result["events"][0]["id"], "one")
        self.assertEqual(result["warning"], "Calendar sync reported an error; events may be outdated")
        self.assertNotIn("fixture-secret", raw)
        self.assertNotIn("host.internal", raw)

    def test_stale_and_disconnected_are_explicit_failures(self):
        stale = self.today([event("one")], date=(datetime.now().astimezone().date() - timedelta(days=1)).isoformat())
        code, result, _, _ = self.run_calendar(stale)
        self.assertEqual((code, result["status"]), (1, "stale"))
        self.assertNotIn("events", result)
        code, result, _, _ = self.run_calendar(self.today([event("one")], connected=False))
        self.assertEqual((code, result["status"]), (1, "disconnected"))
        self.assertNotIn("events", result)

    def test_not_yet_synced_never_looks_like_an_empty_calendar(self):
        code, result, _, _ = self.run_calendar(self.today([], last_sync=""))
        self.assertEqual((code, result["status"]), (1, "stale"))
        self.assertEqual(result["message"], "Waiting for Everything App to sync today's calendar")
        self.assertNotIn("events", result)

    def test_malformed_feed_never_looks_like_an_empty_calendar(self):
        cases = [self.today(None), self.today([event("one", starts_at="2026-10-02T09:00:00")]),
                 self.today([event("one", ends_at="2026-10-02T08:00:00-07:00")]),
                 self.today([event("one", all_day="false")]),
                 self.today([], date="2026-99-99"), {"connected": True, "events": []}]
        for body in cases:
            with self.subTest(body=body):
                code, result, _, _ = self.run_calendar(body)
                self.assertEqual((code, result["status"]), (1, "error"))
                self.assertNotIn("events", result)

    def test_transport_and_config_errors_do_not_reveal_credentials_or_host(self):
        code, result, raw, _ = self.run_calendar(error=urllib.error.URLError("fixture-secret host.internal"))
        self.assertEqual((code, result["status"]), (1, "error"))
        self.assertNotIn("fixture-secret", raw)
        self.assertNotIn("host.internal", raw)
        code, result, raw, _ = self.run_calendar(config={"service_url": "https://bad.example/", "token": ""})
        self.assertEqual((code, result["status"]), (1, "error"))
        self.assertNotIn("bad.example", raw)
        code, result, raw, _ = self.run_calendar(config={"service_url": "https://bad.example/", "token": "fixture-secret\nInjected: 1"})
        self.assertEqual((code, result["status"]), (1, "error"))
        self.assertNotIn("fixture-secret", raw)

    def test_redirect_is_refused_before_any_bearer_can_be_forwarded(self):
        request = calendar.urllib.request.Request("https://calendar.example.test/api/today",
            headers={"Authorization": "Bearer fixture-secret"})
        self.assertIsNone(calendar.NoRedirect().redirect_request(
            request, None, 302, "Moved", {}, "https://other.example.test/collect"))


if __name__ == "__main__":
    unittest.main()
