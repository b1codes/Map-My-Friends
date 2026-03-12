from rest_framework.throttling import AnonRateThrottle


class BurstAnonRateThrottle(AnonRateThrottle):
    scope = 'anon_burst'


class SustainedAnonRateThrottle(AnonRateThrottle):
    scope = 'anon_sustained'
