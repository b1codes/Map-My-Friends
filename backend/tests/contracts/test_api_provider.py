"""Provider verification: replay every contract request against the real API.

Each file in contracts/api/interactions becomes one test. The request is sent
exactly as the Flutter client sends it (frontend/test/contracts checks that
half), against the Firestore emulator, and the response must:

- have the contract's status code,
- validate against the contract's strict JSON Schema,
- hold every value under `expect` (JSON Pointer -> value),
- and the request must not carry fields the API silently drops, other than
  the ones the contract declares under `ignored_request_fields`.
"""

from __future__ import annotations

import json
from unittest import expectedFailure
from unittest.mock import patch
from urllib.parse import urlencode

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin

from .states import REQUEST_SERIALIZERS, STATES, UPLOAD_POINTERS
from .support import (
    api_validator,
    fixtures,
    interactions,
    resolve_pointer,
    schema_errors,
    substitute,
    unconsumed_fields,
)

# A 1x1 transparent PNG, so uploads go through Pillow-readable bytes.
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082"
)


# Gaps between what the Flutter client expects and what the API does, found
# by this suite and not yet fixed. Each runs as an expected failure, so fixing
# one fails the suite until its entry is removed.
KNOWN_GAPS = {
    "trips.create": "Trip stops lack people_detail/airport_detail/station_detail.",
    "trips.list": "Trip stops lack people_detail/airport_detail/station_detail.",
    "trips.update": "Trip stops lack the *_detail fields, and leg edits are lost.",
}


def _geocoder_answer():
    geocoder = fixtures()["geocoder"]
    return geocoder["lat"], geocoder["lng"], geocoder["timezone"]


class ApiProviderContractTests(ThrottleIsolationMixin, FirestoreTestMixin, APITestCase):
    collections_to_purge = ["people", "trips", "user_profiles"]

    def setUp(self):
        super().setUp()
        # Nominatim is a third party with no contract here; every state's
        # addresses resolve to the point fixtures.json names.
        geocoder = patch(
            "apps.people.views.geocode_address", return_value=_geocoder_answer()
        )
        geocoder.start()
        self.addCleanup(geocoder.stop)

    def verify(self, interaction):
        state = STATES[interaction.spec["provider_state"]]()
        placeholders = fixtures()["placeholders"]
        mapping = {
            example: state.roles[role]
            for example, role in placeholders.items()
            if role in state.roles
        }

        response = self._send(interaction, state, mapping)
        expected = interaction.response

        self.assertEqual(
            response.status_code,
            expected["status"],
            f"{interaction.id}: {response.content[:500]!r}",
        )

        if expected.get("schema") is None:
            self.assertEqual(response.content, b"", interaction.id)
            return

        body = json.loads(response.content)
        errors = schema_errors(api_validator(expected["schema"]), body)
        self.assertEqual(errors, [], f"{interaction.id} breaks {expected['schema']}")

        for pointer, value in expected.get("expect", {}).items():
            with self.subTest(expect=pointer):
                self.assertEqual(
                    resolve_pointer(body, pointer), substitute(value, mapping)
                )

        for part, pointer in UPLOAD_POINTERS.get(interaction.id, {}).items():
            self.assertIsNotNone(
                resolve_pointer(body, pointer),
                f"{interaction.id}: {part} was not stored",
            )

    def _send(self, interaction, state, mapping):
        request = interaction.request
        path = "/api/" + substitute(request["path"], mapping)
        if request.get("query"):
            path += "?" + urlencode(substitute(request["query"], mapping))

        auth = request.get("auth", "none")
        if auth == "user":
            token = AccessToken.for_user(state.user)
            self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        elif auth == "invalid":
            self.client.credentials(HTTP_AUTHORIZATION="Bearer not-a-valid-token")

        send = getattr(self.client, request["method"].lower())
        if "json" in request:
            return send(path, substitute(request["json"], mapping), format="json")
        if "multipart" in request:
            multipart = request["multipart"]
            data = substitute(multipart["fields"], mapping)
            for name, upload in multipart["files"].items():
                data[name] = SimpleUploadedFile(
                    upload["filename"], PNG, content_type=upload["content_type"]
                )
            return send(path, data, format="multipart")
        return send(path)


def _provider_test(interaction):
    def test(self):
        self.verify(interaction)

    test.__doc__ = f"{interaction.id}: {interaction.spec['description']}"
    return expectedFailure(test) if interaction.id in KNOWN_GAPS else test


for _interaction in interactions():
    setattr(
        ApiProviderContractTests,
        "test_" + _interaction.id.replace(".", "_"),
        _provider_test(_interaction),
    )


class RequestFieldContractTests(APITestCase):
    """Fields the client sends must reach the server, or be declared ignored.

    Checked against the serializers rather than by replaying, so a request
    that also fails for another reason still gets this signal.
    """

    def test_no_request_field_is_silently_dropped(self):
        for interaction in interactions():
            body = interaction.request_body()
            if body is None:
                continue
            with self.subTest(interaction.id):
                serializer = REQUEST_SERIALIZERS[interaction.id]()
                self.assertEqual(
                    unconsumed_fields(serializer, body),
                    sorted(interaction.spec.get("ignored_request_fields", {})),
                )


class ContractCoverageTests(APITestCase):
    """Every contract has a provider state, and every state is used."""

    def test_every_interaction_names_a_known_provider_state(self):
        for interaction in interactions():
            with self.subTest(interaction.id):
                self.assertIn(interaction.spec["provider_state"], STATES)
                self.assertIn(
                    interaction.spec["provider_state"], fixtures()["provider_states"]
                )

    def test_every_request_body_has_a_consuming_serializer(self):
        with_body = {i.id for i in interactions() if i.request_body() is not None}
        self.assertEqual(with_body, set(REQUEST_SERIALIZERS))

    def test_fixtures_document_exactly_the_provider_states(self):
        self.assertEqual(set(fixtures()["provider_states"]), set(STATES))
