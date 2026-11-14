import io
import json
import re
import tempfile
import urllib.error
import urllib.parse
from pathlib import Path
from unittest import mock

from django.core.management import call_command
from django.test import SimpleTestCase

from apps.stations import reference
from apps.stations.management.commands import fetch_stations
from apps.stations.management.commands.fetch_stations import classify

# Captured at import, before any test patches it.
DEFAULT_OUTPUT_PATH = fetch_stations.OUTPUT_PATH


def _node(osm_id, name, lat, lon, **tags):
    """An Overpass `out body;` node element."""
    element = {"type": "node", "id": osm_id, "lat": lat, "lon": lon, "tags": tags}
    if name is not None:
        element["tags"]["name"] = name
    return element


def _payload(*elements):
    return {
        "version": 0.6,
        "generator": "Overpass API 0.7.62.1 084b4234",
        "osm3s": {
            "timestamp_osm_base": "2026-10-20T12:00:00Z",
            "timestamp_areas_base": "2026-10-20T10:00:00Z",
            "copyright": "The data included in this document is from www.openstreetmap.org.",
        },
        "elements": list(elements),
    }


PROVIDENCE = _node(
    2001, "Providence", 41.8295, -71.4134,
    railway="station", operator="Amtrak", **{"amtrak:code": "PVD", "addr:city": "Providence"},
)  # fmt: skip
KINGSTON = _node(
    2002, "Kingston", 41.4844, -71.5266,
    railway="station", operator="Amtrak", **{"amtrak:code": "KIN"},
)  # fmt: skip
WICKFORD = _node(
    2003, "Wickford Junction", 41.5810, -71.4914,
    railway="station", network="MBTA", operator="Keolis",
)  # fmt: skip
PORTLAND = _node(
    3001, "Portland Union Station", 45.5288, -122.6765,
    railway="station", uic_ref="7400001", **{"addr:city": "Portland"},
)  # fmt: skip


class _FakeOverpass:
    """Stands in for urllib.request.urlopen, answering per ISO subdivision.

    Each state maps to a list of outcomes consumed one per attempt: a dict is
    served as a JSON body, bytes are served raw, and an exception is raised.
    States without an entry get an empty result.
    """

    def __init__(self, responses=None):
        self.responses = {state: list(o) for state, o in (responses or {}).items()}
        self.calls = []

    def __call__(self, request, timeout):
        query = urllib.parse.parse_qs(request.data.decode())["data"][0]
        state = re.search(r'"ISO3166-2"="([^"]+)"', query).group(1)
        self.calls.append({"state": state, "request": request, "timeout": timeout})
        outcomes = self.responses.get(state)
        outcome = outcomes.pop(0) if outcomes else _payload()
        if isinstance(outcome, Exception):
            raise outcome
        if isinstance(outcome, bytes):
            return io.BytesIO(outcome)
        return io.BytesIO(json.dumps(outcome).encode("utf-8"))

    @property
    def states(self):
        return [call["state"] for call in self.calls]


class FetchStationsCommandTests(SimpleTestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        # Never let a test regenerate the committed dataset.
        self.output = Path(tmp.name) / "stations_export.json"
        patcher = mock.patch.object(fetch_stations, "OUTPUT_PATH", self.output)
        patcher.start()
        self.addCleanup(patcher.stop)

        # Backoff and rate-limit pauses are asserted, never actually slept.
        sleep_patcher = mock.patch.object(fetch_stations.time, "sleep")
        self.sleep = sleep_patcher.start()
        self.addCleanup(sleep_patcher.stop)

    def _run(self, responses=None, existing=None, args=("--states", "US-RI")):
        if existing is not None:
            self.output.write_text(json.dumps(existing), encoding="utf-8")
        self.overpass = _FakeOverpass(responses)
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(
            fetch_stations.urllib.request, "urlopen", side_effect=self.overpass
        ):
            call_command("fetch_stations", *args, stdout=out, stderr=err)
        self.stderr = err.getvalue()
        rows = json.loads(self.output.read_text(encoding="utf-8"))
        return rows, out.getvalue()

    def test_default_output_is_the_file_the_index_reads(self):
        self.assertEqual(DEFAULT_OUTPUT_PATH, reference.DATA_FILE)

    def test_request_satisfies_overpass_usage_policy(self):
        # Overpass answers 406 to the default Python-urllib agent.
        self._run()
        call = self.overpass.calls[0]
        request = call["request"]
        self.assertEqual(request.full_url, fetch_stations.OVERPASS_URL)
        self.assertEqual(request.get_method(), "POST")
        self.assertIn("map-my-friends", request.get_header("User-agent"))
        self.assertEqual(request.get_header("Accept"), "application/json")
        self.assertEqual(call["timeout"], 300)

    def test_query_targets_state_area_and_station_nodes(self):
        self._run()
        query = urllib.parse.parse_qs(self.overpass.calls[0]["request"].data.decode())[
            "data"
        ][0]
        self.assertIn('area["ISO3166-2"="US-RI"][admin_level=4]', query)
        self.assertIn('node["railway"="station"](area.a);', query)
        self.assertIn('node["railway"="halt"](area.a);', query)
        self.assertIn("[out:json]", query)

    def test_queries_every_state_by_default(self):
        self._run(args=("--sleep", "0"))
        self.assertEqual(self.overpass.states, fetch_stations.US_STATES)
        self.assertEqual(len(fetch_stations.US_STATES), 51)

    def test_states_option_limits_queries(self):
        self._run(args=("--states", "US-OR", "US-RI"))
        self.assertEqual(self.overpass.states, ["US-OR", "US-RI"])

    def test_maps_nodes_to_export_schema(self):
        rows, _ = self._run({"US-RI": [_payload(PROVIDENCE)]})
        self.assertEqual(
            rows,
            [
                {
                    "name": "Providence",
                    "osm_id": 2001,
                    "station_type": "major_station",
                    "uic_ref": "PVD",
                    "city": "Providence",
                    "country": "USA",
                    "lat": 41.8295,
                    "lon": -71.4134,
                    "id": 1,
                }
            ],
        )

    def test_uic_ref_preferred_over_amtrak_code(self):
        both = _node(1, "Both", 1.0, 2.0, uic_ref="8000105", **{"amtrak:code": "BTH"})
        neither = _node(2, "Neither", 1.0, 2.0)
        rows, _ = self._run({"US-RI": [_payload(both, neither)]})
        self.assertEqual([r["uic_ref"] for r in rows], ["8000105", ""])

    def test_explicit_country_tag_overrides_default(self):
        border = _node(1, "Border Halt", 45.0, -73.0, **{"addr:country": "CA"})
        rows, _ = self._run({"US-RI": [_payload(border)]})
        self.assertEqual(rows[0]["country"], "CA")

    def test_skips_non_nodes_and_incomplete_nodes(self):
        unnamed = _node(10, None, 41.0, -71.0, railway="halt")
        no_lat = {"type": "node", "id": 11, "lon": -71.0, "tags": {"name": "No Lat"}}
        no_lon = {"type": "node", "id": 12, "lat": 41.0, "tags": {"name": "No Lon"}}
        no_id = {"type": "node", "lat": 41.0, "lon": -71.0, "tags": {"name": "No Id"}}
        no_tags = {"type": "node", "id": 13, "lat": 41.0, "lon": -71.0}
        way = {"type": "way", "id": 14, "nodes": [1, 2], "tags": {"name": "Platform"}}
        rows, _ = self._run(
            {
                "US-RI": [
                    _payload(unnamed, no_lat, no_lon, no_id, no_tags, way, KINGSTON)
                ]
            }
        )
        self.assertEqual([r["name"] for r in rows], ["Kingston"])

    def test_zero_coordinates_are_kept(self):
        # lat/lon are checked against None, so 0.0 must not be dropped as falsy.
        null_island = _node(1, "Null Island", 0.0, 0.0)
        rows, _ = self._run({"US-RI": [_payload(null_island)]})
        self.assertEqual((rows[0]["lat"], rows[0]["lon"]), (0.0, 0.0))

    def test_fresh_ids_follow_osm_id_order(self):
        rows, _ = self._run({"US-RI": [_payload(WICKFORD, PROVIDENCE, KINGSTON)]})
        self.assertEqual(
            [(r["osm_id"], r["id"]) for r in rows], [(2001, 1), (2002, 2), (2003, 3)]
        )

    def test_station_returned_by_two_states_is_stored_once(self):
        rows, _ = self._run(
            {"US-RI": [_payload(KINGSTON)], "US-CT": [_payload(KINGSTON)]},
            args=("--states", "US-RI", "US-CT"),
        )
        self.assertEqual(len(rows), 1)

    def test_existing_records_and_ids_are_preserved(self):
        # Trip stops store station ids, so a regeneration must never renumber.
        existing = [
            {**_row(PORTLAND), "id": 5},
            {**_row(PROVIDENCE), "name": "Providence (old name)", "id": 9},
        ]
        rows, output = self._run(
            {"US-RI": [_payload(PROVIDENCE, KINGSTON)]}, existing=existing
        )
        self.assertIn("Loaded 2 existing stations.", output)
        by_osm = {r["osm_id"]: r for r in rows}
        # US-OR was not refetched, so Portland survives untouched.
        self.assertEqual(by_osm[3001]["id"], 5)
        self.assertEqual(by_osm[3001]["name"], "Portland Union Station")
        # Refetched stations keep their id but take the fresh data.
        self.assertEqual(by_osm[2001]["id"], 9)
        self.assertEqual(by_osm[2001]["name"], "Providence")
        # New stations are numbered after the highest existing id.
        self.assertEqual(by_osm[2002]["id"], 10)
        self.assertEqual([r["id"] for r in rows], [5, 9, 10])

    def test_output_is_loadable_by_reference_index(self):
        self._run({"US-RI": [_payload(PROVIDENCE, KINGSTON, WICKFORD)]})
        with mock.patch.object(reference, "DATA_FILE", self.output):
            reference._load.cache_clear()
            self.addCleanup(reference._load.cache_clear)
            nearest = reference.get_nearby(41.82, -71.41, count=1)[0]
        self.assertEqual(nearest.name, "Providence")
        self.assertEqual(nearest.station_type, "major_station")

    def test_write_is_atomic_and_leaves_no_temp_file(self):
        self._run({"US-RI": [_payload(PROVIDENCE)]})
        self.assertFalse(self.output.with_suffix(".json.tmp").exists())
        self.assertTrue(self.output.read_text(encoding="utf-8").endswith("\n"))

    def test_reports_running_total_and_summary(self):
        _, output = self._run({"US-RI": [_payload(PROVIDENCE, KINGSTON)]})
        self.assertIn("Querying US-RI...", output)
        self.assertIn("  running total: 2", output)
        self.assertIn(f"Wrote 2 stations to {self.output}", output)
        self.assertNotIn("failed", output)

    def test_sleeps_between_states(self):
        self._run(args=("--states", "US-RI", "US-CT", "--sleep", "2.5"))
        self.assertEqual(self.sleep.call_args_list, [mock.call(2.5), mock.call(2.5)])

    def test_transient_failure_is_retried_with_exponential_backoff(self):
        rate_limited = urllib.error.HTTPError(
            fetch_stations.OVERPASS_URL, 429, "Too Many Requests", {}, None
        )
        rows, output = self._run(
            {"US-RI": [rate_limited, TimeoutError("timed out"), _payload(KINGSTON)]},
            args=("--states", "US-RI", "--sleep", "1"),
        )
        self.assertEqual([r["name"] for r in rows], ["Kingston"])
        self.assertEqual(self.overpass.states, ["US-RI", "US-RI", "US-RI"])
        # 1s * 2**1, then 1s * 2**2, then the normal between-state pause.
        self.assertEqual(
            self.sleep.call_args_list, [mock.call(2.0), mock.call(4.0), mock.call(1.0)]
        )
        self.assertIn("US-RI attempt 1 failed (HTTP Error 429", self.stderr)
        self.assertIn(
            "US-RI attempt 2 failed (timed out); retrying in 4s.", self.stderr
        )
        self.assertNotIn("state(s) failed", output)

    def test_malformed_json_is_retried(self):
        # Overpass serves an HTML error page with a 200 when overloaded.
        rows, _ = self._run(
            {"US-RI": [b"<html><body>runtime error</body></html>", _payload(KINGSTON)]}
        )
        self.assertEqual([r["name"] for r in rows], ["Kingston"])
        self.assertIn("US-RI attempt 1 failed", self.stderr)

    def test_state_failing_every_attempt_keeps_existing_records(self):
        down = urllib.error.URLError("Connection refused")
        existing = [{**_row(PROVIDENCE), "id": 1}]
        rows, output = self._run(
            {"US-RI": [down, down], "US-CT": [_payload(_node(4001, "New Haven", 41.3, -72.9))]},
            existing=existing,
            args=("--states", "US-RI", "US-CT", "--retries", "2", "--sleep", "1"),
        )  # fmt: skip
        self.assertEqual([r["name"] for r in rows], ["Providence", "New Haven"])
        self.assertEqual(self.overpass.states, ["US-RI", "US-RI", "US-CT"])
        # No backoff after the final attempt, just the between-state pause.
        self.assertEqual(
            self.sleep.call_args_list, [mock.call(2.0), mock.call(1.0), mock.call(1.0)]
        )
        self.assertIn(
            "US-RI failed after 2 attempts (<urlopen error Connection refused>); "
            "keeping any existing records.",
            self.stderr,
        )
        self.assertIn("1 state(s) failed: US-RI", output)
        self.assertIn("manage.py fetch_stations --states US-RI", output)

    def test_every_state_failing_still_writes_previous_dataset(self):
        down = urllib.error.URLError("Connection refused")
        existing = [{**_row(PROVIDENCE), "id": 3}]
        rows, output = self._run(
            {"US-RI": [down], "US-OR": [down]},
            existing=existing,
            args=("--states", "US-RI", "US-OR", "--retries", "1"),
        )
        self.assertEqual(rows, existing)
        self.assertIn("2 state(s) failed: US-RI US-OR", output)


def _row(node):
    """The export record fetch_stations writes for an Overpass node, minus id."""
    tags = node["tags"]
    return {
        "name": tags["name"],
        "osm_id": node["id"],
        "station_type": classify(tags["name"], tags),
        "uic_ref": tags.get("uic_ref", tags.get("amtrak:code", "")),
        "city": tags.get("addr:city", ""),
        "country": "USA",
        "lat": node["lat"],
        "lon": node["lon"],
    }


class ClassifyTests(SimpleTestCase):
    def test_known_major_hub_by_name(self):
        self.assertEqual(classify("Chicago Union Station", {}), "major_station")

    def test_amtrak_signals_mark_major(self):
        cases = {
            "name": ("Amtrak Station", {}),
            "operator": ("Kingston", {"operator": "Amtrak"}),
            "network": ("Kingston", {"network": "Amtrak Northeast Regional"}),
            "amtrak:code": ("Kingston", {"amtrak:code": "KIN"}),
        }
        for signal, (name, tags) in cases.items():
            with self.subTest(signal=signal):
                self.assertEqual(classify(name, tags), "major_station")

    def test_uic_ref_marks_major(self):
        self.assertEqual(classify("Somewhere", {"uic_ref": "123"}), "major_station")

    def test_major_takes_precedence_over_subway(self):
        self.assertEqual(
            classify("Union Station", {"station": "subway", "railway": "subway"}),
            "major_station",
        )

    def test_subway_signals(self):
        cases = {
            "Subway in name": ("Broadway Subway", {}),
            "Metro in name": ("Metro Center", {}),
            "BART in name": ("Powell Street BART", {}),
            "Path Station in name": ("Grove Street Path Station", {}),
            "railway=subway": ("Clark/Lake", {"railway": "subway"}),
            "station=subway": ("Clark/Lake", {"station": "subway"}),
        }
        for signal, (name, tags) in cases.items():
            with self.subTest(signal=signal):
                self.assertEqual(classify(name, tags), "subway_station")

    def test_subway_takes_precedence_over_commuter(self):
        self.assertEqual(
            classify("Metro Center", {"network": "MBTA"}), "subway_station"
        )

    def test_commuter_networks(self):
        for network in fetch_stations.COMMUTER_NETWORKS:
            with self.subTest(network=network):
                self.assertEqual(
                    classify("Hometown", {"network": f"{network} Rail"}),
                    "commuter_rail_station",
                )

    def test_commuter_keyword_in_railway_or_network(self):
        self.assertEqual(
            classify("Hometown", {"railway": "commuter_station"}),
            "commuter_rail_station",
        )
        self.assertEqual(
            classify("Hometown", {"network": "Sounder Commuter Rail"}),
            "commuter_rail_station",
        )

    def test_metro_north_network_is_commuter_not_subway(self):
        # The subway check reads the name only, so a Metro-North *network*
        # tag falls through to the commuter networks.
        self.assertEqual(
            classify("Croton-Harmon", {"network": "Metro-North Railroad"}),
            "commuter_rail_station",
        )

    def test_everything_else_is_regional(self):
        self.assertEqual(classify("Hometown", {}), "regional_station")
        self.assertEqual(
            classify("Hometown", {"railway": "halt", "operator": "Brightline"}),
            "regional_station",
        )
