"""Loading and checking the shared contracts in the repo-root contracts/ folder.

The same files are read by the Flutter consumer tests (frontend/test/contracts),
so nothing here may encode Django-specific behaviour into the contract itself;
Django specifics live in states.py.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from django.conf import settings
from jsonschema import Draft202012Validator
from rest_framework import serializers

# backend/ is mounted at /app in Docker and contracts/ at /contracts, so the
# repo-relative path resolves the same way inside the container and on a host.
CONTRACTS_DIR = Path(settings.BASE_DIR).parent / "contracts"


def load_json(relative_path: str):
    with (CONTRACTS_DIR / relative_path).open(encoding="utf-8") as handle:
        return json.load(handle)


@dataclass(frozen=True)
class Interaction:
    id: str
    spec: dict

    @property
    def request(self) -> dict:
        return self.spec["request"]

    @property
    def response(self) -> dict:
        return self.spec["response"]

    def request_body(self) -> dict | None:
        """The text fields the client sends, JSON or multipart."""
        if "json" in self.request:
            return self.request["json"]
        if "multipart" in self.request:
            return self.request["multipart"]["fields"]
        return None


@cache
def interactions() -> tuple[Interaction, ...]:
    paths = sorted((CONTRACTS_DIR / "api" / "interactions").glob("*.json"))
    return tuple(
        Interaction(id=path.stem, spec=load_json(f"api/interactions/{path.name}"))
        for path in paths
    )


@cache
def fixtures() -> dict:
    return load_json("api/fixtures.json")


@cache
def _api_defs() -> dict:
    return load_json("api/schema.json")["$defs"]


def api_validator(definition: str) -> Draft202012Validator:
    """A validator for one named shape in contracts/api/schema.json."""
    defs = _api_defs()
    if definition not in defs:
        raise KeyError(f"contracts/api/schema.json has no $defs/{definition}")
    return Draft202012Validator({"$defs": defs, "$ref": f"#/$defs/{definition}"})


def file_validator(relative_path: str) -> Draft202012Validator:
    """A validator for a standalone schema file, e.g. an external provider's."""
    schema = load_json(relative_path)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def schema_errors(validator: Draft202012Validator, instance) -> list[str]:
    """Every violation, each prefixed with the JSON path it occurred at."""
    return [
        f"{error.json_path}: {error.message}"
        for error in sorted(validator.iter_errors(instance), key=lambda e: e.path)
    ]


def substitute(value, mapping: dict[str, str]):
    """Swap contract placeholders for real values, recursively.

    Whole strings are replaced, plus placeholders embedded in a URL path such
    as "people/<id>/".
    """
    if isinstance(value, dict):
        return {k: substitute(v, mapping) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute(v, mapping) for v in value]
    if isinstance(value, str):
        if value in mapping:
            return mapping[value]
        for placeholder, real in mapping.items():
            if f"/{placeholder}/" in f"/{value}":
                value = value.replace(placeholder, real)
        return value
    return value


def resolve_pointer(document, pointer: str):
    """RFC 6901 lookup; raises LookupError naming the pointer when absent."""
    current = document
    for raw in pointer.lstrip("/").split("/") if pointer else []:
        token = raw.replace("~1", "/").replace("~0", "~")
        try:
            current = current[int(token) if isinstance(current, list) else token]
        except (KeyError, IndexError, ValueError, TypeError):
            raise LookupError(f"{pointer} is not present in the response") from None
    return current


def unconsumed_fields(serializer, data: dict, prefix: str = "") -> list[str]:
    """Request keys the serializer would silently drop.

    DRF ignores unknown and read-only keys rather than rejecting them, so a
    client field that never reaches the server fails silently. Nested lists
    are reported as `parent[].child`.
    """
    found: list[str] = []
    for key, value in data.items():
        name = f"{prefix}{key}"
        field = serializer.fields.get(key)
        if field is None or field.read_only:
            found.append(name)
        elif isinstance(field, serializers.ListSerializer) and isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    found += unconsumed_fields(field.child, item, f"{name}[].")
        elif isinstance(field, serializers.Serializer) and isinstance(value, dict):
            found += unconsumed_fields(field, value, f"{name}.")
    return sorted(set(found))


@dataclass(frozen=True)
class ExternalContract:
    """One third-party interaction under contracts/external/<provider>/."""

    provider: str
    name: str
    spec: dict

    @property
    def id(self) -> str:
        return f"{self.provider}/{self.name}"

    def validator(self) -> Draft202012Validator:
        schema = self.spec.get("schema") or self.spec["response"]["schema"]
        return file_validator(f"external/{self.provider}/{schema}")

    def example(self):
        if "example" in self.spec:
            return self.spec["example"]
        return self.spec["response"]["example"]


@cache
def external_contracts() -> tuple[ExternalContract, ...]:
    found = []
    for path in sorted((CONTRACTS_DIR / "external").glob("*/*.json")):
        if path.name.endswith(".schema.json"):
            continue
        provider = path.parent.name
        found.append(
            ExternalContract(
                provider=provider,
                name=path.stem,
                spec=load_json(f"external/{provider}/{path.name}"),
            )
        )
    return tuple(found)


def external_contract(contract_id: str) -> ExternalContract:
    return next(c for c in external_contracts() if c.id == contract_id)


def normalize_whitespace(text: str) -> str:
    return " ".join(text.split())
