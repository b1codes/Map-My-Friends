"""Every query the API sends has the index production Firestore needs.

The emulator answers any query, indexed or not, so a query that needs an
index nobody deployed passes every suite and then fails in production with
FAILED_PRECONDITION, a 500. This sends each request in the round-trip budget
table, records the queries the API makes, and checks each one against
firestore.indexes.json (deployed with `firebase deploy --only
firestore:indexes`) and the indexes Firestore builds on its own:

- A query on one collection with only equality filters, or ordered by a
  single field, uses the single-field indexes Firestore keeps for every
  field. Nothing to deploy.
- A collection-group query needs those single-field indexes switched on for
  the collection group, by a fieldOverrides entry per field.
- Equality filters plus an order on another field, or several orders, need a
  composite index with those fields, in either scope.
"""

from __future__ import annotations

import json
from pathlib import Path

from django.conf import settings
from google.cloud.firestore_v1.base_query import FieldFilter
from google.cloud.firestore_v1.types import StructuredQuery

from apps.common import firestore as fs
from apps.common.testing import count_firestore_rpcs
from tests.test_round_trip_budgets import BUDGETS, SMALL, BudgetBase

# backend/ is mounted at /app in Docker and the file at /firestore.indexes.json,
# so this resolves the same in the container as on the host.
INDEXES_FILE = Path(settings.BASE_DIR).parent / "firestore.indexes.json"

EQUALITY_OPS = {
    StructuredQuery.FieldFilter.Operator.EQUAL,
    StructuredQuery.FieldFilter.Operator.IN,
}


def _field_filters(where) -> list:
    """The field filters in a query's where clause, flattened."""
    if where.field_filter.field.field_path:
        return [where.field_filter]
    if where.unary_filter.field.field_path:
        return [where.unary_filter]
    filters = []
    for sub in where.composite_filter.filters:
        filters.extend(_field_filters(sub))
    return filters


def query_shape(query) -> dict:
    """What decides a query's index: its collection and scope, the fields it
    filters by equality, and the fields it orders by (inequalities and other
    operators included, since they order the scan too)."""
    (source,) = query.from_
    equality, ordered = [], []
    for item in _field_filters(query.where):
        op = getattr(item, "op", None)
        if isinstance(item, StructuredQuery.FieldFilter) and op in EQUALITY_OPS:
            equality.append(item.field.field_path)
        else:
            ordered.append((item.field.field_path, "ASCENDING"))
    ordered.extend(
        (order.field.field_path, order.direction.name)
        for order in query.order_by
        if order.field.field_path != "__name__"
    )
    return {
        "collection": source.collection_id,
        "scope": "COLLECTION_GROUP" if source.all_descendants else "COLLECTION",
        "equality": sorted(set(equality)),
        "ordered": list(dict.fromkeys(ordered)),
    }


def _single_field_override(config, collection, field, scope, order) -> bool:
    for override in config.get("fieldOverrides", []):
        if (override["collectionGroup"], override["fieldPath"]) != (collection, field):
            continue
        return any(
            index.get("queryScope") == scope and index.get("order") == order
            for index in override.get("indexes", [])
        )
    # Without an override, Firestore indexes every field for collection scope
    # only.
    return scope == "COLLECTION"


def _composite(config, shape) -> bool:
    for index in config.get("indexes", []):
        if (index["collectionGroup"], index["queryScope"]) != (
            shape["collection"],
            shape["scope"],
        ):
            continue
        fields = [(f["fieldPath"], f.get("order")) for f in index["fields"]]
        n_equality = len(shape["equality"])
        if sorted(name for name, _ in fields[:n_equality]) != shape["equality"]:
            continue
        if fields[n_equality:] == shape["ordered"]:
            return True
    return False


def missing_index(config, shape) -> str | None:
    """Why production can't serve a query of this shape, or None if it can."""
    if shape["ordered"] and (shape["equality"] or len(shape["ordered"]) > 1):
        if _composite(config, shape):
            return None
        return "needs a composite index"
    single = [(field, "ASCENDING") for field in shape["equality"]] + shape["ordered"]
    unindexed = [
        field
        for field, order in single
        if not _single_field_override(
            config, shape["collection"], field, shape["scope"], order
        )
    ]
    if unindexed:
        return f"needs {shape['scope']} single-field indexes on {unindexed}"
    return None


class QueryShapeTests(BudgetBase):
    """The checker itself, on queries built by hand."""

    def test_reads_scope_filters_and_orders(self):
        with count_firestore_rpcs() as counts:
            list(
                fs.get_client()
                .collection_group("contact_logs")
                .where(filter=FieldFilter("owner_key", "==", "x"))
                .where(filter=FieldFilter("log_id", "==", "y"))
                .stream()
            )
            list(
                fs.collection("people")
                .where(filter=FieldFilter("owner_key", "==", "x"))
                .order_by("last_name")
                .stream()
            )
        self.assertEqual(
            [query_shape(q) for q in counts.queries],
            [
                {
                    "collection": "contact_logs",
                    "scope": "COLLECTION_GROUP",
                    "equality": ["log_id", "owner_key"],
                    "ordered": [],
                },
                {
                    "collection": "people",
                    "scope": "COLLECTION",
                    "equality": ["owner_key"],
                    "ordered": [("last_name", "ASCENDING")],
                },
            ],
        )

    def test_flags_what_production_would_refuse(self):
        config = {
            "indexes": [
                {
                    "collectionGroup": "people",
                    "queryScope": "COLLECTION",
                    "fields": [
                        {"fieldPath": "owner_key", "order": "ASCENDING"},
                        {"fieldPath": "last_name", "order": "ASCENDING"},
                    ],
                }
            ],
            "fieldOverrides": [
                {
                    "collectionGroup": "logs",
                    "fieldPath": "owner_key",
                    "indexes": [
                        {"order": "ASCENDING", "queryScope": "COLLECTION_GROUP"}
                    ],
                }
            ],
        }

        def shape(collection, scope, equality, ordered=()):
            return {
                "collection": collection,
                "scope": scope,
                "equality": equality,
                "ordered": list(ordered),
            }

        cases = {
            "single collection, equality": (
                shape("people", "COLLECTION", ["city", "owner_key"]),
                None,
            ),
            "composite present": (
                shape(
                    "people",
                    "COLLECTION",
                    ["owner_key"],
                    [("last_name", "ASCENDING")],
                ),
                None,
            ),
            "composite missing": (
                shape(
                    "people",
                    "COLLECTION",
                    ["owner_key"],
                    [("last_name", "DESCENDING")],
                ),
                "needs a composite index",
            ),
            "group override present": (
                shape("logs", "COLLECTION_GROUP", ["owner_key"]),
                None,
            ),
            "group override missing": (
                shape("logs", "COLLECTION_GROUP", ["owner_key", "log_id"]),
                "needs COLLECTION_GROUP single-field indexes on ['log_id']",
            ),
            # An override replaces the defaults, so one that leaves out
            # collection scope switches it off.
            "override drops collection scope": (
                shape("logs", "COLLECTION", ["owner_key"]),
                "needs COLLECTION single-field indexes on ['owner_key']",
            ),
        }
        for label, (query, expected) in cases.items():
            with self.subTest(label):
                self.assertEqual(missing_index(config, query), expected)


class ProductionIndexTests(BudgetBase):
    def test_every_query_the_api_sends_is_indexed(self):
        config = json.loads(INDEXES_FILE.read_text())
        problems = {}
        for key, budget in BUDGETS.items():
            for query in self.measure(key, budget, SMALL).queries:
                shape = query_shape(query)
                reason = missing_index(config, shape)
                if reason is not None:
                    problems[json.dumps(shape, sort_keys=True)] = (
                        f"{' '.join(key)}: {reason}"
                    )
        self.assertEqual(
            problems,
            {},
            "These queries would fail in production. Add the index to "
            "firestore.indexes.json and deploy it before the code.",
        )
