"""Prints every (method, path) the Django API serves, as JSON.

scripts/dast_openapi.py compares this with the OpenAPI document it builds for
the ZAP scan, so a new endpoint can't go unscanned without anyone noticing.

It needs Django, so it runs inside the API container, from stdin:

    docker compose exec -T api python - < scripts/list_api_routes.py

Paths come out the way the contracts write them: relative to /api/, with each
URL parameter as {name}. DRF's format-suffix variants (.json) and the router's
browsable root views are left out; they are the same views again.
"""

import json
import os
import re
import sys

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
sys.path.insert(0, os.getcwd())
django.setup()

from django.urls import URLPattern, URLResolver, get_resolver  # noqa: E402

METHODS = ("get", "post", "put", "patch", "delete")


def pattern_text(pattern):
    """The path piece a URL pattern matches, with parameters as {name}."""
    text = str(pattern.pattern)
    text = text.lstrip("^").rstrip("$")
    # Regex groups from DRF's routers, e.g. (?P<pk>[^/.]+)
    text = re.sub(r"\(\?P<(\w+)>[^)]*\)", r"{\1}", text)
    # Converters from path(), e.g. <int:pk>
    text = re.sub(r"<(?:\w+:)?(\w+)>", r"{\1}", text)
    return text.replace("\\", "")


def methods_for(callback):
    """The HTTP methods a view answers, besides HEAD and OPTIONS."""
    actions = getattr(callback, "actions", None)
    if actions:  # a DRF ViewSet route maps each method to an action
        return sorted(m.upper() for m in actions if m in METHODS)
    view_class = getattr(callback, "view_class", None) or getattr(
        callback, "cls", None
    )
    if view_class is None:
        return ["GET"]
    allowed = getattr(view_class, "http_method_names", METHODS)
    return sorted(
        m.upper() for m in METHODS if m in allowed and hasattr(view_class, m)
    )


def walk(patterns, prefix=""):
    for entry in patterns:
        text = prefix + pattern_text(entry)
        if isinstance(entry, URLResolver):
            yield from walk(entry.url_patterns, text)
        elif isinstance(entry, URLPattern):
            if "{format}" in text or entry.name == "api-root":
                continue
            for method in methods_for(entry.callback):
                yield method, text


routes = sorted(set(walk(get_resolver().url_patterns)))
print(json.dumps([{"method": m, "path": p} for m, p in routes], indent=2))
