import csv
import io
import json
import tempfile
import urllib.error
from pathlib import Path
from unittest import mock

from django.core.management import call_command
from django.test import SimpleTestCase

from apps.airports import reference
from apps.airports.management.commands import fetch_airports

# Captured at import, before any test patches it.
DEFAULT_OUTPUT_PATH = fetch_airports.OUTPUT_PATH

# Column order of the real OurAirports airports.csv.
CSV_COLUMNS = [
    "id",
    "ident",
    "type",
    "name",
    "latitude_deg",
    "longitude_deg",
    "elevation_ft",
    "continent",
    "iso_country",
    "iso_region",
    "municipality",
    "scheduled_service",
    "icao_code",
    "iata_code",
    "gps_code",
    "local_code",
    "home_link",
    "wikipedia_link",
    "keywords",
]


def _airport(ident, type_, name, lat, lon, iata, city="", country="US", continent="NA"):
    return {
        "id": "1",
        "ident": ident,
        "type": type_,
        "name": name,
        "latitude_deg": lat,
        "longitude_deg": lon,
        "elevation_ft": "600",
        "continent": continent,
        "iso_country": country,
        "iso_region": f"{country}-XX",
        "municipality": city,
        "scheduled_service": "yes",
        "icao_code": ident,
        "iata_code": iata,
        "gps_code": ident,
        "local_code": "",
        "home_link": "",
        "wikipedia_link": "",
        "keywords": "",
    }


def _csv(rows):
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=CSV_COLUMNS, quoting=csv.QUOTE_ALL)
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue()


ORD = _airport(
    "KORD", "large_airport", "Chicago O'Hare International Airport",
    "41.9786", "-87.9048", "ORD", city="Chicago",
)  # fmt: skip
MDW = _airport(
    "KMDW", "large_airport", "Chicago Midway International Airport",
    "41.7868", "-87.7522", "MDW", city="Chicago",
)  # fmt: skip
LHR = _airport(
    "EGLL", "large_airport", "London Heathrow Airport",
    "51.4706", "-0.461941", "LHR", city="London", country="GB", continent="EU",
)  # fmt: skip
SBN = _airport(
    "KSBN", "medium_airport", "South Bend International Airport",
    "41.708698", "-86.317299", "SBN", city="South Bend",
)  # fmt: skip


class FetchAirportsCommandTests(SimpleTestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        # Never let a test regenerate the committed dataset.
        self.output = Path(tmp.name) / "airports_export.json"
        patcher = mock.patch.object(fetch_airports, "OUTPUT_PATH", self.output)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _run(self, rows, existing=None):
        if existing is not None:
            self.output.write_text(json.dumps(existing), encoding="utf-8")
        out = io.StringIO()
        body = io.BytesIO(_csv(rows).encode("utf-8"))
        with mock.patch.object(
            fetch_airports.urllib.request, "urlopen", return_value=body
        ) as urlopen:
            call_command("fetch_airports", stdout=out)
        self.urlopen = urlopen
        return json.loads(self.output.read_text(encoding="utf-8")), out.getvalue()

    def test_default_output_is_the_file_the_index_reads(self):
        self.assertEqual(DEFAULT_OUTPUT_PATH, reference.DATA_FILE)

    def test_downloads_ourairports_csv(self):
        self._run([ORD])
        self.urlopen.assert_called_once_with(
            fetch_airports.OURAIRPORTS_CSV_URL, timeout=120
        )

    def test_maps_csv_columns_to_export_schema(self):
        rows, _ = self._run([LHR])
        self.assertEqual(
            rows,
            [
                {
                    "name": "London Heathrow Airport",
                    "iata": "LHR",
                    "icao": "EGLL",
                    "type": "large_airport",
                    "city": "London",
                    "country": "GB",
                    "continent": "EU",
                    "lat": 51.4706,
                    "lon": -0.461941,
                    "id": 1,
                }
            ],
        )

    def test_output_is_loadable_by_reference_index(self):
        self._run([ORD, MDW, SBN])
        with mock.patch.object(reference, "DATA_FILE", self.output):
            reference._load.cache_clear()
            self.addCleanup(reference._load.cache_clear)
            nearest = reference.get_nearby(41.8781, -87.6298, count=1)[0]
        self.assertEqual(nearest.iata_code, "MDW")

    def test_only_large_and_medium_airports_kept(self):
        rows, _ = self._run(
            [
                ORD,
                SBN,
                _airport("K3CK", "small_airport", "Lake In The Hills", "42.2", "-88.3", "LIH"),
                _airport("IL01", "heliport", "Hospital Helipad", "41.9", "-87.6", "HHH"),
                _airport("KCGX", "closed", "Meigs Field", "41.8586", "-87.6079", "CGX"),
                _airport("SPLH", "seaplane_base", "Lake Harbor", "41.8", "-87.5", "SPB"),
            ]
        )  # fmt: skip
        self.assertEqual([r["iata"] for r in rows], ["ORD", "SBN"])

    def test_airports_without_iata_are_skipped(self):
        rows, _ = self._run(
            [ORD, _airport("KDPA", "medium_airport", "DuPage", "41.9", "-88.2", "  ")]
        )
        self.assertEqual([r["iata"] for r in rows], ["ORD"])

    def test_iata_code_is_stripped(self):
        rows, _ = self._run([{**ORD, "iata_code": " ORD "}])
        self.assertEqual(rows[0]["iata"], "ORD")

    def test_duplicate_iata_keeps_first_occurrence(self):
        impostor = {**SBN, "iata_code": "ORD", "name": "Not O'Hare"}
        rows, _ = self._run([ORD, impostor])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["name"], "Chicago O'Hare International Airport")

    def test_rows_with_unparseable_coordinates_are_skipped(self):
        rows, _ = self._run(
            [ORD, {**MDW, "latitude_deg": ""}, {**SBN, "longitude_deg": "n/a"}]
        )
        self.assertEqual([r["iata"] for r in rows], ["ORD"])

    def test_icao_is_first_four_characters_of_ident(self):
        rows, _ = self._run([{**ORD, "ident": "KORDX"}])
        self.assertEqual(rows[0]["icao"], "KORD")

    def test_fresh_ids_follow_iata_order(self):
        rows, _ = self._run([SBN, ORD, MDW, LHR])
        self.assertEqual(
            [(r["iata"], r["id"]) for r in rows],
            [("LHR", 1), ("MDW", 2), ("ORD", 3), ("SBN", 4)],
        )

    def test_existing_ids_are_preserved_by_iata(self):
        # People store preferred_airport ids in Firestore, so a regeneration
        # must never renumber an airport that is still present.
        existing = [
            {"iata": "ORD", "id": 7, "name": "old"},
            {"iata": "MDW", "id": 3, "name": "old"},
        ]
        rows, _ = self._run([ORD, MDW, LHR, SBN], existing=existing)
        ids = {r["iata"]: r["id"] for r in rows}
        self.assertEqual(ids["ORD"], 7)
        self.assertEqual(ids["MDW"], 3)
        # New airports are appended after the highest existing id, in IATA order.
        self.assertEqual(ids["LHR"], 8)
        self.assertEqual(ids["SBN"], 9)
        # Refreshed data replaces the old record contents.
        self.assertEqual(rows[1]["name"], "Chicago O'Hare International Airport")

    def test_output_sorted_by_id(self):
        existing = [{"iata": "SBN", "id": 1}, {"iata": "ORD", "id": 2}]
        rows, _ = self._run([ORD, SBN, MDW], existing=existing)
        self.assertEqual([r["id"] for r in rows], [1, 2, 3])

    def test_existing_rows_missing_id_or_iata_are_ignored(self):
        existing = [{"iata": "ORD"}, {"id": 50}, {"iata": "MDW", "id": 4}]
        rows, _ = self._run([ORD, MDW], existing=existing)
        self.assertEqual({r["iata"]: r["id"] for r in rows}, {"MDW": 4, "ORD": 5})

    def test_airport_missing_from_source_is_dropped(self):
        existing = [{"iata": "ORD", "id": 1}, {"iata": "CGX", "id": 2}]
        rows, _ = self._run([ORD], existing=existing)
        self.assertEqual([r["iata"] for r in rows], ["ORD"])

    def test_writes_utf8_without_escaping(self):
        zurich = _airport(
            "LSZH", "large_airport", "Zürich Airport", "47.4647", "8.5492", "ZRH",
            city="Zürich", country="CH", continent="EU",
        )  # fmt: skip
        self._run([zurich])
        text = self.output.read_text(encoding="utf-8")
        self.assertIn("Zürich Airport", text)
        self.assertTrue(text.endswith("\n"))

    def test_reports_count_and_path(self):
        _, output = self._run([ORD, MDW])
        self.assertIn("Downloading airport data from OurAirports...", output)
        self.assertIn(f"Wrote 2 airports to {self.output}", output)

    def test_network_failure_leaves_existing_file_untouched(self):
        original = json.dumps([{"iata": "ORD", "id": 1}])
        self.output.write_text(original, encoding="utf-8")
        with (
            mock.patch.object(
                fetch_airports.urllib.request,
                "urlopen",
                side_effect=urllib.error.URLError("Name or service not known"),
            ),
            self.assertRaises(urllib.error.URLError),
        ):
            call_command("fetch_airports", stdout=io.StringIO())
        self.assertEqual(self.output.read_text(encoding="utf-8"), original)
