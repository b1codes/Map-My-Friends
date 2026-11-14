from rest_framework.throttling import SimpleRateThrottle


class ClientIPRateThrottle(SimpleRateThrottle):
    """Limits every caller by client IP, signed in or not.

    The sign-up, password-reset and login views accept anyone. DRF's
    AnonRateThrottle skips any request that carries a valid token, so on these
    views a token from a throwaway account used to switch the limit off.
    """

    def get_cache_key(self, request, view):
        return self.cache_format % {
            "scope": self.scope,
            "ident": self.get_ident(request),
        }


class BurstAnonRateThrottle(ClientIPRateThrottle):
    scope = "anon_burst"


class SustainedAnonRateThrottle(ClientIPRateThrottle):
    scope = "anon_sustained"


class LoginBurstRateThrottle(ClientIPRateThrottle):
    """Password guesses back to back. The daily anon limit still applies."""

    scope = "login_burst"
