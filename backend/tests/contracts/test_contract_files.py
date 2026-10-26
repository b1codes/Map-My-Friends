"""The contract files are consistent with themselves.

The Flutter tests parse each interaction's `example`, so an example that
drifts from its schema would test the client against a response the server
can never send.
"""

from __future__ import annotations

import re

from django.test import SimpleTestCase
from jsonschema import Draft202012Validator

from .support import api_validator, fixtures, interactions, load_json, schema_errors

INTERACTION_KEYS = {
    "description",
    "consumer",
    "provider_state",
    "request",
    "response",
    "ignored_request_fields",
}
REQUEST_KEYS = {"method", "path", "query", "auth", "json", "multipart"}
RESPONSE_KEYS = {"status", "schema", "example", "expect"}
FIRESTORE_ID = re.compile(r"^[A-Za-z0-9]{20}$")


class ContractFileTests(SimpleTestCase):
    def test_api_schema_is_valid_json_schema(self):
        Draft202012Validator.check_schema(load_json("api/schema.json"))

    def test_interactions_exist(self):
        self.assertGreater(len(interactions()), 0)

    def test_interactions_use_only_known_keys(self):
        for interaction in interactions():
            with self.subTest(interaction.id):
                self.assertLessEqual(set(interaction.spec), INTERACTION_KEYS)
                self.assertLessEqual(set(interaction.request), REQUEST_KEYS)
                self.assertLessEqual(set(interaction.response), RESPONSE_KEYS)
                self.assertIn(interaction.request["auth"], {"none", "user", "invalid"})
                self.assertFalse(interaction.request["path"].startswith("/"))
                self.assertTrue(interaction.request["path"].endswith("/"))
                self.assertFalse(
                    "json" in interaction.request and "multipart" in interaction.request
                )

    def test_examples_match_their_schema(self):
        for interaction in interactions():
            response = interaction.response
            with self.subTest(interaction.id):
                if response.get("schema") is None:
                    self.assertNotIn("example", response)
                    continue
                errors = schema_errors(
                    api_validator(response["schema"]), response["example"]
                )
                self.assertEqual(errors, [])

    def test_expectations_hold_in_the_example(self):
        from .support import resolve_pointer

        for interaction in interactions():
            for pointer, value in interaction.response.get("expect", {}).items():
                with self.subTest(interaction.id, expect=pointer):
                    self.assertEqual(
                        resolve_pointer(interaction.response["example"], pointer), value
                    )

    def test_placeholders_look_like_what_they_stand_for(self):
        for example, role in fixtures()["placeholders"].items():
            with self.subTest(role):
                if role != "refresh_token":
                    self.assertRegex(example, FIRESTORE_ID)
