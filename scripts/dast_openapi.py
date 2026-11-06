#!/usr/bin/env python3
"""Builds the OpenAPI document the ZAP API scan imports, and checks it covers
every route the API serves.

There's no hand-maintained OpenAPI spec (and no drf-spectacular). The
contracts in contracts/api/interactions already hold every request the app
makes, with real example bodies, so the document is built from them, plus
.zap/extra-operations.json for the endpoints the app doesn't call.

    # write the document (scripts/dast.sh does this before each scan)
    scripts/dast_openapi.py --out build/dast/openapi.json \\
        --server http://api:8000 --id person=<id> --id trip=<id> ...

    # fail if it has drifted from the routes Django serves
    docker compose exec -T api python - < scripts/list_api_routes.py > routes.json
    scripts/dast_openapi.py --check-routes routes.json

--id swaps a placeholder id from contracts/api/fixtures.json (by its role,
e.g. person or trip.leg.0) for a real one, so ZAP's requests reach a record
the scanning user owns instead of a 404. --id person@DELETE=<id> uses that
id for DELETE requests only.

Standard library only.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INTERACTIONS = ROOT / "contracts" / "api" / "interactions"
FIXTURES = ROOT / "contracts" / "api" / "fixtures.json"
EXTRAS = ROOT / ".zap" / "extra-operations.json"
API_PREFIX = "api/"


def load_json(path: Path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def id_placeholders() -> dict[str, str]:
    """Placeholder id -> role, for the ids that can appear in a path.

    The refresh token is a placeholder too, but never part of a path.
    """
    placeholders = load_json(FIXTURES)["placeholders"]
    return {value: role for value, role in placeholders.items() if "." not in value}


def param_name(role: str) -> str:
    """person -> person_id, trip.leg.0 -> leg_id."""
    parts = [p for p in role.split(".") if not p.isdigit()]
    return f"{parts[-1]}_id"


def route_key(method: str, path: str, placeholders: dict[str, str]) -> tuple[str, str]:
    """A (METHOD, path) pair with every path parameter written as {}."""
    segments = []
    for segment in path.split("/"):
        if segment in placeholders or re.fullmatch(r"\{\w+\}", segment):
            segment = "{}"
        segments.append(segment)
    return method.upper(), "/".join(segments)


def load_operations() -> tuple[list[dict], dict[str, str]]:
    """Every request to describe: (source name, request) from both files."""
    operations = []
    interactions = [(path, load_json(path)) for path in sorted(INTERACTIONS.glob("*.json"))]
    # Successful requests first: where several contracts share an operation,
    # the first one's body becomes the example ZAP starts from.
    interactions.sort(key=lambda pair: not 200 <= pair[1]["response"]["status"] < 300)
    for path, interaction in interactions:
        operations.append(
            {
                "source": f"contracts/api/interactions/{path.name}",
                "contract": True,
                "request": interaction["request"],
                "status": interaction["response"]["status"],
                "description": interaction.get("description", ""),
            }
        )
    extras = load_json(EXTRAS)
    for i, entry in enumerate(extras["operations"]):
        operations.append(
            {
                "source": f".zap/extra-operations.json operations[{i}]",
                "contract": False,
                "request": entry["request"],
                "status": None,
                "description": "Not called by the app; listed in .zap/extra-operations.json.",
            }
        )
    return operations, extras["excluded_prefixes"]


def substitute(value, ids: dict[str, str]):
    """Swaps placeholder ids anywhere in an example for the given real ids."""
    if isinstance(value, str):
        return ids.get(value, value)
    if isinstance(value, list):
        return [substitute(v, ids) for v in value]
    if isinstance(value, dict):
        return {k: substitute(v, ids) for k, v in value.items()}
    return value


def schema_for(example):
    """A permissive JSON schema shaped like an example, carrying it as the
    example at every level so ZAP sends valid values before it mutates them."""
    if isinstance(example, bool):
        schema = {"type": "boolean"}
    elif isinstance(example, int):
        schema = {"type": "integer"}
    elif isinstance(example, float):
        schema = {"type": "number"}
    elif isinstance(example, str):
        schema = {"type": "string"}
    elif isinstance(example, list):
        schema = {"type": "array", "items": schema_for(example[0]) if example else {}}
    elif isinstance(example, dict):
        schema = {
            "type": "object",
            "properties": {k: schema_for(v) for k, v in example.items()},
        }
    else:  # None
        return {"nullable": True}
    schema["example"] = example
    return schema


def multipart_schema(multipart: dict, ids: dict[str, str]) -> dict:
    fields = substitute(multipart.get("fields", {}), ids)
    properties = {name: {"type": "string", "example": v} for name, v in fields.items()}
    for name in multipart.get("files", {}):
        properties[name] = {"type": "string", "format": "binary"}
    return {"type": "object", "properties": properties}


def build(server: str, ids_by_role: dict[str, str]) -> dict:
    placeholders = id_placeholders()
    operations, _ = load_operations()

    paths: dict[str, dict] = {}
    for op in operations:
        request = op["request"]
        method = request["method"].lower()
        # ROLE@METHOD overrides ROLE for that method's requests.
        ids = {}
        for value, role in placeholders.items():
            chosen = ids_by_role.get(f"{role}@{method.upper()}", ids_by_role.get(role))
            if chosen:
                ids[value] = chosen

        segments, parameters = [], []
        for segment in request["path"].split("/"):
            if segment in placeholders:
                name = param_name(placeholders[segment])
                parameters.append(
                    {
                        "name": name,
                        "in": "path",
                        "required": True,
                        "schema": {"type": "string", "example": ids.get(segment, segment)},
                        "example": ids.get(segment, segment),
                    }
                )
                segment = "{" + name + "}"
            segments.append(segment)
        path = "/" + API_PREFIX + "/".join(segments)

        for name, value in (request.get("query") or {}).items():
            value = substitute(value, ids)
            parameters.append(
                {
                    "name": name,
                    "in": "query",
                    "required": False,
                    "schema": {"type": "string", "example": value},
                    "example": value,
                }
            )

        operation = paths.setdefault(path, {}).get(method)
        if operation is None:
            operation = {
                "operationId": f"{method}_{re.sub(r'[^A-Za-z0-9]+', '_', path).strip('_')}",
                "summary": op["description"],
                "parameters": parameters,
                "responses": {},
                "security": [{"bearerAuth": []}] if request.get("auth") == "user" else [],
            }
            paths[path][method] = operation
        # Several contracts can share an operation (a success and a failure,
        # or a JSON and a multipart body). The first body of each media type
        # wins, and contracts with a 2xx response are read first.
        if "json" in request:
            content = operation.setdefault("requestBody", {"content": {}})["content"]
            content.setdefault(
                "application/json", {"schema": schema_for(substitute(request["json"], ids))}
            )
        if "multipart" in request:
            content = operation.setdefault("requestBody", {"content": {}})["content"]
            content.setdefault(
                "multipart/form-data",
                {"schema": multipart_schema(request["multipart"], ids)},
            )
        status = str(op["status"] or "default")
        operation["responses"].setdefault(status, {"description": op["source"]})

    return {
        "openapi": "3.0.3",
        "info": {
            "title": "Map My Friends API (for the ZAP scan)",
            "version": "generated",
            "description": "Generated by scripts/dast_openapi.py from contracts/api/interactions and .zap/extra-operations.json. Not committed; regenerate rather than edit.",
        },
        "servers": [{"url": server.rstrip("/")}],
        "components": {
            "securitySchemes": {
                "bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}
            }
        },
        "paths": dict(sorted(paths.items())),
    }


def check_routes(routes_file: Path) -> list[str]:
    """Problems that mean the scan no longer matches the API, one per line."""
    placeholders = id_placeholders()
    operations, excluded = load_operations()
    problems = []

    described: dict[tuple[str, str], list[dict]] = {}
    for op in operations:
        key = route_key(op["request"]["method"], API_PREFIX + op["request"]["path"], placeholders)
        described.setdefault(key, []).append(op)

    for key, ops in described.items():
        contracts = [o["source"] for o in ops if o["contract"]]
        for extra in (o for o in ops if not o["contract"]):
            if contracts:
                problems.append(
                    f"{key[0]} {key[1]} now has a contract ({contracts[0]}); "
                    f"remove {extra['source']}."
                )
            elif len([o for o in ops if not o["contract"]]) > 1:
                problems.append(f"{key[0]} {key[1]} is listed twice in .zap/extra-operations.json.")

    served = set()
    for route in load_json(routes_file):
        path = route["path"]
        if any(path.startswith(prefix) for prefix in excluded):
            continue
        if not path.startswith(API_PREFIX):
            problems.append(
                f"{route['method']} {path} is served outside {API_PREFIX} and isn't in "
                "excluded_prefixes in .zap/extra-operations.json; scan it or exclude it with a reason."
            )
            continue
        served.add(route_key(route["method"], path, placeholders))

    for method, path in sorted(served - described.keys()):
        problems.append(
            f"{method} /{path} is served but the scan doesn't know it: add a contract "
            "(contracts/api/interactions) or an entry in .zap/extra-operations.json."
        )
    for method, path in sorted(described.keys() - served):
        sources = ", ".join(o["source"] for o in described[(method, path)])
        problems.append(f"{method} /{path} is described ({sources}) but no route serves it.")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path, help="write the OpenAPI document here")
    parser.add_argument("--server", default="http://api:8000", help="the API's base URL as ZAP sees it")
    parser.add_argument(
        "--id",
        action="append",
        default=[],
        metavar="ROLE[@METHOD]=ID",
        help="use a real id for a placeholder role from contracts/api/fixtures.json",
    )
    parser.add_argument(
        "--check-routes",
        type=Path,
        metavar="ROUTES_JSON",
        help="output of scripts/list_api_routes.py; fail on drift",
    )
    args = parser.parse_args()
    if not args.out and not args.check_routes:
        parser.error("give --out, --check-routes, or both")

    if args.check_routes:
        problems = check_routes(args.check_routes)
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        if problems:
            return 1
        print("The scan's API definition covers every route the API serves.")

    if args.out:
        ids = dict(pair.split("=", 1) for pair in args.id)
        document = build(args.server, ids)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        count = sum(len(ops) for ops in document["paths"].values())
        print(f"Wrote {args.out} ({count} operations on {len(document['paths'])} paths).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
