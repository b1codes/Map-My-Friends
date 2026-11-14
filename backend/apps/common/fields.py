from django.core.validators import RegexValidator
from rest_framework import serializers


class PinColorField(serializers.CharField):
    """A pin colour as "#RRGGBB", the only form the app can draw.

    The app parses it with int.parse on the hex digits, so anything else
    ("7", "red", "#12345") throws on every screen that shows the pin. The
    profile contract already says so (contracts/api/schema.json).
    """

    default_error_messages = {
        "invalid": 'Use a colour like "#2196F3": "#" and six hex digits.',
    }

    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", 7)
        super().__init__(**kwargs)
        self.validators.append(
            RegexValidator(
                r"^#[0-9A-Fa-f]{6}\Z", message=self.error_messages["invalid"]
            )
        )
