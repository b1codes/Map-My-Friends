"""Tests for smoke.py, against a fake API on localhost.

A smoke test that passes when the API is broken is worse than none, so these
check each way it should fail, and that it cleans up after itself even then.
Run with `python3 -m unittest discover smoke` (the Smoke Test job does).
"""

import io
import json
import os
import socketserver
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

import smoke

ORIGIN = "https://app.example.test"


class FakeApi:
    """Answers like the real API; a test breaks one behaviour at a time.

    Like Cloud Run until GCIP, it can have several instances, each with its
    own users (SQLite), taking requests in turn. Trips are shared (Firestore).
    """

    def __init__(self):
        self.trips = {}
        self.requests = []
        self.health = (200, {"status": "ok"})
        self.nearest_code = "LHR"
        self.list_hides_trips = False
        self.delete_status = 204
        self.cors_origin = ORIGIN
        self.registered = []
        self.instances = 1
        self.users = {}  # instance -> {username: password}
        self.standing = {"watcher": "pw"}  # on every instance
        self.sign_in_broken = False
        self.served = 0

    def handle(self, method, path, body, headers):
        self.requests.append((method, path))
        instance = self.served % self.instances
        self.served += 1
        users = {**self.standing, **self.users.setdefault(instance, {})}
        if path == "/health":
            return self.health
        if path == "/api/user/auth/register/":
            if body["username"] in users:
                return 400, {"username": ["A user with that username already exists."]}
            self.users[instance][body["username"]] = body["password"]
            self.registered.append(body["username"])
            return 201, {"username": body["username"]}
        if path == "/api/user/auth/token/":
            if self.sign_in_broken or users.get(body["username"]) != body["password"]:
                return 401, {
                    "detail": "No active account found with the given credentials",
                    "code": "no_active_account",
                }
            return 200, {"access": f"token:{body['username']}", "refresh": "r"}
        auth = headers.get("authorization", "")
        if method != "OPTIONS":
            if not auth.startswith("Bearer token:"):
                return 401, {"detail": "not signed in"}
            if auth.removeprefix("Bearer token:") not in users:
                return 401, {"detail": "User not found", "code": "user_not_found"}
        if path.startswith("/api/airports/nearest/"):
            return 200, {
                "type": "FeatureCollection",
                "features": [{"properties": {"iata_code": self.nearest_code}}],
            }
        if path == "/api/trips/" and method == "OPTIONS":
            return 200, None
        if path == "/api/trips/" and method == "POST":
            trip_id = f"trip{len(self.trips) + 1}"
            self.trips[trip_id] = body
            return 201, {"id": trip_id, **body}
        if path == "/api/trips/" and method == "GET":
            if self.list_hides_trips:
                return 200, []
            return 200, [{"id": t} for t in self.trips]
        if path.startswith("/api/trips/"):
            trip_id = path.split("/")[3]
            if method == "DELETE":
                if self.delete_status == 204:
                    self.trips.pop(trip_id, None)
                return self.delete_status, None
            if method == "GET":
                return (200, {"id": trip_id}) if trip_id in self.trips else (404, None)
        return 404, None


class _LocalServer(ThreadingHTTPServer):
    # HTTPServer looks up the machine's FQDN on bind, which can take many
    # seconds on a machine with slow reverse DNS. Nothing here needs it.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def serve(api):
    class Handler(BaseHTTPRequestHandler):
        def _respond(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length)) if length else None
            status, payload = api.handle(
                self.command,
                self.path,
                body,
                {k.lower(): v for k, v in self.headers.items()},
            )
            data = b"" if payload is None else json.dumps(payload).encode()
            self.send_response(status)
            if self.command == "OPTIONS" and api.cors_origin:
                self.send_header("Access-Control-Allow-Origin", api.cors_origin)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_DELETE = do_OPTIONS = _respond

        def log_message(self, *args):
            pass

    server = _LocalServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeApi()
        self.server = serve(self.api)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        env = mock.patch.dict(os.environ, {"SMOKE_WEB_ORIGIN": ORIGIN}, clear=False)
        env.start()
        self.addCleanup(env.stop)
        for name in ("SMOKE_USERNAME", "SMOKE_PASSWORD"):
            os.environ.pop(name, None)

    def run_smoke(self):
        out = io.StringIO()
        ok = smoke.run(smoke.Client(self.url, timeout=5), out=out)
        return ok, out.getvalue()

    def test_passes_against_a_working_api(self):
        ok, out = self.run_smoke()

        self.assertTrue(ok, out)
        self.assertEqual(out.count("ok "), len(smoke.CHECKS))

    def test_leaves_no_trip_behind(self):
        self.run_smoke()

        self.assertEqual(self.api.trips, {})

    def test_registers_a_throwaway_account_without_credentials(self):
        self.run_smoke()

        self.assertEqual(len(self.api.registered), 1)
        self.assertTrue(self.api.registered[0].startswith("smoke-"))

    def test_signs_in_with_the_given_account_and_registers_none(self):
        with mock.patch.dict(
            os.environ, {"SMOKE_USERNAME": "watcher", "SMOKE_PASSWORD": "pw"}
        ):
            ok, out = self.run_smoke()

        self.assertTrue(ok, out)
        self.assertEqual(self.api.registered, [])

    def test_passes_when_requests_land_on_instances_without_the_account(self):
        # Each request goes to the next instance in turn, so the account
        # registered on one is missing on the instance that signs in, and on
        # some that serve the checks after. With two or four, a retry that
        # registered once each time would stay in step with the rotation.
        for instances in (2, 3, 4):
            with self.subTest(instances=instances):
                self.setUp()
                self.api.instances = instances

                ok, out = self.run_smoke()

                self.assertTrue(ok, out)
                self.assertEqual(self.api.trips, {})
                self.assertEqual(len(set(self.api.registered)), 1, "one account")

    def test_fails_when_sign_in_never_works_and_stops_retrying(self):
        self.api.instances = 3
        self.api.sign_in_broken = True

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("FAIL  sign in", out)
        # /health, registering, then each sign-in and at most two registrations.
        self.assertLessEqual(len(self.api.requests), 2 + 3 * smoke.ATTEMPTS)

    def test_fails_when_a_token_is_refused_for_another_reason(self):
        smoke_client = smoke.Client(self.url, timeout=5)
        smoke_client.token = "not-a-token"
        smoke_client.account = {"username": "smoke-x", "password": "pw"}

        response = smoke_client.request("GET", "/api/trips/")

        self.assertEqual(response.status, 401)
        self.assertEqual(self.api.registered, [], "re-registered for a bad token")

    def test_a_standing_account_is_never_registered(self):
        self.api.instances = 3
        with mock.patch.dict(
            os.environ, {"SMOKE_USERNAME": "watcher", "SMOKE_PASSWORD": "wrong"}
        ):
            ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("signing in", out)
        self.assertEqual(self.api.registered, [])

    def test_fails_when_health_does(self):
        self.api.health = (503, {"status": "down"})

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("FAIL  the API is up", out)

    def test_fails_when_reference_data_is_wrong(self):
        self.api.nearest_code = "LGW"

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("not LHR", out)

    def test_fails_when_a_saved_trip_isnt_listed_and_still_deletes_it(self):
        self.api.list_hides_trips = True

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("isn't in the trip list", out)
        self.assertEqual(self.api.trips, {}, "the trip was left behind")
        self.assertIn(("DELETE", "/api/trips/trip1/"), self.api.requests)

    def test_a_failed_cleanup_is_reported_without_hiding_the_first_failure(self):
        self.api.list_hides_trips = True
        self.api.delete_status = 500

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        lines = [line for line in out.splitlines() if line.startswith("FAIL")]
        self.assertIn("isn't in the trip list", lines[0])
        self.assertIn("cleanup", lines[1])

    def test_fails_when_delete_does(self):
        self.api.delete_status = 500

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("deleting the trip", out)

    def test_fails_when_cors_refuses_the_web_app(self):
        self.api.cors_origin = None

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("doesn't allow the web app's origin", out)

    def test_cors_is_skipped_without_an_origin(self):
        with mock.patch.dict(os.environ, {"SMOKE_WEB_ORIGIN": ""}):
            ok, out = self.run_smoke()

        self.assertTrue(ok, out)
        self.assertIn("skipped", out)

    def test_fails_when_nothing_answers(self):
        self.server.shutdown()
        self.server.server_close()

        ok, out = self.run_smoke()

        self.assertFalse(ok)
        self.assertIn("no answer", out)

    def test_main_exits_non_zero_on_failure(self):
        self.api.health = (500, None)
        with (
            mock.patch.dict(os.environ, {"SMOKE_BASE_URL": self.url}),
            mock.patch("sys.stdout", new_callable=io.StringIO),
        ):
            self.assertEqual(smoke.main(), 1)

    def test_main_needs_a_url(self):
        with (
            mock.patch.dict(os.environ, {"SMOKE_BASE_URL": ""}),
            mock.patch("sys.stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(smoke.main(), 2)


if __name__ == "__main__":
    unittest.main()
