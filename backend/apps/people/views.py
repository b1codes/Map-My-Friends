from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers, status, viewsets
from rest_framework.exceptions import APIException
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.settings import api_settings
from rest_framework.throttling import UserRateThrottle

from apps.common.ownership import owner_key_for
from apps.common.parsers import StrictJSONParser
from apps.common.storage import delete_upload, save_upload

from .repositories import ContactLogRepository, PersonRepository
from .serializers import ContactLogSerializer, PersonSerializer
from .services import GeocodingUnavailable, geocode_address

ADDRESS_FIELDS = ("city", "state", "country", "street")
PHOTO_PREFIX = "profile_images"


class GeocoderUnavailable(APIException):
    """503 for a geocoder outage, shaped like the Firestore-outage response in
    apps.common.exception_handlers ({"error": ...})."""

    status_code = status.HTTP_503_SERVICE_UNAVAILABLE


class PersonViewSet(viewsets.ViewSet):
    """Manage Person documents.

    List and retrieve are public (anonymous callers see only unowned people);
    create, update and delete require authentication.
    """

    parser_classes = [MultiPartParser, FormParser, StrictJSONParser]

    def get_permissions(self):
        if self.action in ["list", "retrieve"]:
            permission_classes = [AllowAny]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    def get_throttles(self):
        if self.action == "create":
            # Stricter throttling for creating people due to geocoding costs
            return [UserRateThrottle()]
        return super().get_throttles()

    @property
    def repository(self):
        return PersonRepository()

    def list(self, request):
        people = self.repository.list_for_owner(owner_key_for(request))
        serializer = PersonSerializer(people, many=True, context={"request": request})
        return Response(serializer.data)

    def retrieve(self, request, pk=None):
        person = self.repository.get_for_owner(pk, owner_key_for(request))
        if person is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(PersonSerializer(person, context={"request": request}).data)

    def create(self, request):
        serializer = PersonSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        payload = self._serialize_dates(dict(serializer.validated_data))
        payload = self._apply_geocoding(payload)
        photo = self._apply_upload(request, payload)

        try:
            person = self.repository.create(owner_key_for(request), payload)
        except Exception:
            delete_upload(photo, PHOTO_PREFIX)
            raise
        return Response(
            PersonSerializer(person, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )

    def update(self, request, pk=None):
        return self._write_update(request, pk, partial=False)

    def partial_update(self, request, pk=None):
        return self._write_update(request, pk, partial=True)

    def _write_update(self, request, pk, partial):
        serializer = PersonSerializer(
            data=request.data, partial=partial, context={"request": request}
        )
        serializer.is_valid(raise_exception=True)
        payload = self._serialize_dates(dict(serializer.validated_data))
        owner_key = owner_key_for(request)
        # Found first, so a request for nobody's person, or someone else's,
        # costs no geocoder lookup and stores no photo.
        current = self.repository.get_for_owner(pk, owner_key)
        if current is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        if any(k in payload for k in ADDRESS_FIELDS):
            payload = self._apply_geocoding(payload, current)
        photo = self._apply_upload(request, payload)

        try:
            person = self.repository.update(pk, owner_key, payload, current=current)
        except Exception:
            delete_upload(photo, PHOTO_PREFIX)
            raise
        if person is None:
            # Deleted since it was found.
            delete_upload(photo, PHOTO_PREFIX)
            return Response(status=status.HTTP_404_NOT_FOUND)
        if photo is not None:
            delete_upload(current.profile_image, PHOTO_PREFIX)
        return Response(PersonSerializer(person, context={"request": request}).data)

    def destroy(self, request, pk=None):
        person = self.repository.delete(pk, owner_key_for(request))
        if person is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        delete_upload(person.profile_image, PHOTO_PREFIX)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @staticmethod
    def _serialize_dates(payload):
        """Firestore rejects datetime.date, so dates go in as ISO strings.

        DRF's DateField hands back a date object; writing it raises
        "Cannot convert to a Firestore Value". trips/ and users/ views do the
        same conversion.
        """
        return {
            k: (v.isoformat() if hasattr(v, "isoformat") else v)
            for k, v in payload.items()
        }

    def _apply_geocoding(self, payload, current=None):
        """Geocode the address the person will have: payload's address fields
        over current's, the person as stored (None for a new person)."""
        address = {f: getattr(current, f) for f in ADDRESS_FIELDS} if current else {}
        address.update({f: payload[f] for f in ADDRESS_FIELDS if f in payload})
        # geocode_address raises Django's ValidationError, which DRF does not
        # translate, so it would otherwise surface as a 500.
        try:
            lat, lng, timezone = geocode_address(
                address.get("city", ""),
                address.get("state", ""),
                address.get("country", ""),
                address.get("street"),
            )
        except GeocodingUnavailable as exc:
            raise GeocoderUnavailable({"error": exc.messages[0]}) from exc
        except DjangoValidationError as exc:
            # The address spans several fields, so the error is not tied to one.
            raise serializers.ValidationError(
                {api_settings.NON_FIELD_ERRORS_KEY: exc.messages}
            ) from exc
        payload["lat"] = lat
        payload["lng"] = lng
        payload["timezone"] = timezone
        return payload

    def _apply_upload(self, request, payload):
        """Store the uploaded photo, if any, and point payload at it. Returns
        the stored name, for the caller to delete if the write fails."""
        uploaded = request.FILES.get("profile_image")
        if uploaded is None:
            return None
        payload["profile_image"] = save_upload(uploaded, prefix=PHOTO_PREFIX)
        return payload["profile_image"]


class ContactLogViewSet(viewsets.ViewSet):
    """Log touchpoints with a Person. All actions require authentication.

    Supports `?person=<id>` to scope the list to a single person.
    """

    permission_classes = [IsAuthenticated]

    @property
    def repository(self):
        return ContactLogRepository()

    def list(self, request):
        # A blank ?person= means no filter, per the usual DRF filter convention.
        logs = self.repository.list_for_owner(
            owner_key_for(request),
            person_id=request.query_params.get("person") or None,
        )
        return Response(ContactLogSerializer(logs, many=True).data)

    def retrieve(self, request, pk=None):
        log = self.repository.get_for_owner(pk, owner_key_for(request))
        if log is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(ContactLogSerializer(log).data)

    def create(self, request):
        serializer = ContactLogSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = dict(serializer.validated_data)
        person_id = payload.pop("person_id")
        payload["contacted_at"] = payload["contacted_at"].isoformat()

        log = self.repository.create(owner_key_for(request), person_id, payload)
        if log is None:
            # The person is absent or belongs to another owner. 400 mirrors the
            # previous queryset-restricted PrimaryKeyRelatedField behaviour.
            return Response(
                {"person": ["Invalid person."]}, status=status.HTTP_400_BAD_REQUEST
            )
        return Response(ContactLogSerializer(log).data, status=status.HTTP_201_CREATED)

    def update(self, request, pk=None):
        return self._write_update(request, pk, partial=False)

    def partial_update(self, request, pk=None):
        return self._write_update(request, pk, partial=True)

    def _write_update(self, request, pk, partial):
        serializer = ContactLogSerializer(data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        payload = dict(serializer.validated_data)
        payload.pop("person_id", None)
        if "contacted_at" in payload:
            payload["contacted_at"] = payload["contacted_at"].isoformat()

        log = self.repository.update(pk, owner_key_for(request), payload)
        if log is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(ContactLogSerializer(log).data)

    def destroy(self, request, pk=None):
        if not self.repository.delete(pk, owner_key_for(request)):
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(status=status.HTTP_204_NO_CONTENT)
