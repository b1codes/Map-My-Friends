from rest_framework.exceptions import ParseError
from rest_framework.parsers import JSONParser


class StrictJSONParser(JSONParser):
    """DRF's JSON parser, refusing strings that aren't valid Unicode.

    JSON may spell one half of a UTF-16 surrogate pair on its own
    ("\\ud800"). Python decodes that into a str with no UTF-8 encoding, and
    everything after the parser assumes there is one: rendering a response
    that echoes the value back failed with UnicodeEncodeError (a 500), and
    Firestore stores UTF-8. A well-formed pair ("\\ud83e\\udd84", 🦄) decodes
    to one character and is untouched.
    """

    def parse(self, stream, media_type=None, parser_context=None):
        data = super().parse(stream, media_type, parser_context)
        if not _valid_unicode(data):
            raise ParseError(
                "JSON parse error - strings must be valid Unicode "
                "(a lone surrogate escape such as \\ud800 is not)."
            )
        return data


def _valid_unicode(value) -> bool:
    if isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            return False
        return True
    if isinstance(value, dict):
        return all(_valid_unicode(k) and _valid_unicode(v) for k, v in value.items())
    if isinstance(value, list):
        return all(_valid_unicode(item) for item in value)
    return True
