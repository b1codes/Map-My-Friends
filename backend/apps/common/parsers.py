from rest_framework.exceptions import ParseError
from rest_framework.parsers import JSONParser

# Arrays and objects inside one another. No body the API takes comes close;
# the cap keeps code after the parser that recurses over the data (ours or a
# library's) far from Python's recursion limit.
MAX_DEPTH = 64


class StrictJSONParser(JSONParser):
    """DRF's JSON parser, refusing strings that aren't valid Unicode and
    nesting deeper than MAX_DEPTH.

    JSON may spell one half of a UTF-16 surrogate pair on its own
    ("\\ud800"). Python decodes that into a str with no UTF-8 encoding, and
    everything after the parser assumes there is one: rendering a response
    that echoes the value back failed with UnicodeEncodeError (a 500), and
    Firestore stores UTF-8. A well-formed pair ("\\ud83e\\udd84", 🦄) decodes
    to one character and is untouched.

    Deep nesting was a 500 too: json.loads raises RecursionError (which DRF
    doesn't catch) once it overflows the stack, and a recursive check over
    the result hit Python's recursion limit long before that.
    """

    def parse(self, stream, media_type=None, parser_context=None):
        try:
            data = super().parse(stream, media_type, parser_context)
        except RecursionError:
            raise ParseError("JSON parse error - nested too deep.") from None
        _check(data)
        return data


def _check(data) -> None:
    """Walk the parsed body without recursing, so its depth can't matter."""
    stack = [(data, 1)]
    while stack:
        value, depth = stack.pop()
        if isinstance(value, str):
            try:
                value.encode("utf-8")
            except UnicodeEncodeError:
                raise ParseError(
                    "JSON parse error - strings must be valid Unicode "
                    "(a lone surrogate escape such as \\ud800 is not)."
                ) from None
        elif isinstance(value, (dict, list)):
            if depth > MAX_DEPTH:
                raise ParseError(
                    "JSON parse error - nested too deep "
                    f"(at most {MAX_DEPTH} levels of arrays and objects)."
                )
            if isinstance(value, dict):
                stack.extend((key, depth) for key in value)
                stack.extend((item, depth + 1) for item in value.values())
            else:
                stack.extend((item, depth + 1) for item in value)
