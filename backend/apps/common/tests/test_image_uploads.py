"""Uploaded profile images: only real images are stored, and only as images.

Uploads are served from /media/ with a content type taken from the stored
extension. Storing whatever arrived under the client's own extension meant an
.html or .svg upload was served as a page on the app's origin (stored XSS),
and any file at all could be parked there.
"""

import io
import shutil
import struct
import tempfile
import zlib
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth.models import User
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, override_settings
from google.api_core import exceptions as gcloud_exceptions
from PIL import Image
from rest_framework import serializers
from rest_framework.test import APITestCase

from apps.common.storage import MAX_IMAGE_BYTES, MAX_IMAGE_SIDE, save_upload
from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin

HTML = b"<html><body><script>alert(document.cookie)</script></body></html>"
SVG = (
    b'<svg xmlns="http://www.w3.org/2000/svg" onload="alert(document.cookie)">'
    b"<circle r='4'/></svg>"
)


def image_bytes(fmt="PNG", size=(4, 4), **save_args):
    buffer = io.BytesIO()
    Image.new("RGB", size, color="teal").save(buffer, format=fmt, **save_args)
    return buffer.getvalue()


def png_header_only(width, height):
    """A PNG that claims a size in its header and holds one empty row."""

    def chunk(kind, body):
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body))
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(b"\0"))
        + chunk(b"IEND", b"")
    )


def upload(name, content, content_type="image/png"):
    return SimpleUploadedFile(name, content, content_type=content_type)


class TempMediaMixin:
    def setUp(self):
        super().setUp()
        media_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media_root, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=media_root)
        media.enable()
        self.addCleanup(media.disable)
        self.media_root = media_root

    def stored_files(self):
        return [p for p in Path(self.media_root).rglob("*") if p.is_file()]


class SaveUploadValidationTests(TempMediaMixin, SimpleTestCase):
    def assertRejected(self, uploaded):
        with self.assertRaises(serializers.ValidationError) as caught:
            save_upload(uploaded, prefix="profile_images")
        self.assertIn("profile_image", caught.exception.detail)
        self.assertEqual(self.stored_files(), [])

    def test_html_is_rejected(self):
        self.assertRejected(upload("page.html", HTML, "text/html"))

    def test_html_claiming_to_be_a_png_is_rejected(self):
        # The name and content type are the client's to choose.
        self.assertRejected(upload("avatar.png", HTML, "image/png"))

    def test_svg_is_rejected(self):
        # SVG is an image to a browser, and runs its scripts.
        self.assertRejected(upload("avatar.svg", SVG, "image/svg+xml"))

    def test_an_image_with_html_appended_is_stored_without_it(self):
        # A polyglot: a valid PNG with a page after its end. Re-encoding keeps
        # the picture and drops everything else.
        name = save_upload(
            upload("avatar.html", image_bytes("PNG") + HTML), prefix="profile_images"
        )

        self.assertTrue(name.endswith(".png"))
        with default_storage.open(name) as handle:
            self.assertNotIn(b"<script>", handle.read())

    def test_truncated_image_is_rejected(self):
        self.assertRejected(upload("avatar.png", image_bytes("PNG")[:20]))

    def test_other_image_formats_are_rejected(self):
        # Only what the app sends (PNG from the cropper) and common photo
        # formats. BMP/TIFF/ICO and the rest widen what Pillow must parse.
        self.assertRejected(upload("avatar.bmp", image_bytes("BMP"), "image/bmp"))
        self.assertRejected(upload("avatar.tiff", image_bytes("TIFF"), "image/tiff"))

    def test_oversized_file_is_rejected(self):
        big = upload("avatar.png", b"\0" * (MAX_IMAGE_BYTES + 1))

        self.assertRejected(big)

    def test_oversized_dimensions_are_rejected(self):
        # A huge, compressible image is small on the wire and large in memory
        # once decoded (a decompression bomb).
        self.assertRejected(
            upload("avatar.png", image_bytes("PNG", size=(MAX_IMAGE_SIDE + 1, 1)))
        )

    def test_a_header_past_pillows_own_pixel_limit_is_rejected(self):
        # Pillow refuses this in Image.open, from the header alone, with an
        # error that is neither OSError nor ValueError. 69 bytes claiming
        # 20000x20000 used to be a 500.
        self.assertRejected(upload("avatar.png", png_header_only(20000, 20000)))

    def test_the_extension_comes_from_the_content(self):
        name = save_upload(
            upload("photo.jpg", image_bytes("PNG"), "image/jpeg"),
            prefix="profile_images",
        )

        self.assertTrue(name.endswith(".png"))

    def test_png_jpeg_and_webp_are_stored(self):
        for fmt, ext in (("PNG", ".png"), ("JPEG", ".jpg"), ("WEBP", ".webp")):
            with self.subTest(fmt=fmt):
                name = save_upload(
                    upload(f"avatar{ext}", image_bytes(fmt)), prefix="profile_images"
                )

                self.assertTrue(name.endswith(ext))
                with default_storage.open(name) as handle:
                    self.assertEqual(Image.open(handle).format, fmt)

    def test_a_cmyk_jpeg_is_stored_as_rgb(self):
        # Print-oriented JPEGs are CMYK, which browsers draw unreliably.
        buffer = io.BytesIO()
        Image.new("CMYK", (4, 4)).save(buffer, format="JPEG")
        name = save_upload(upload("print.jpg", buffer.getvalue()), "profile_images")

        with default_storage.open(name) as handle:
            self.assertEqual(Image.open(handle).mode, "RGB")

    def test_photo_metadata_is_stripped(self):
        # Phone photos carry the GPS position they were taken at; a profile
        # photo shouldn't publish where someone lives.
        exif = Image.Exif()
        exif[0x8825] = {2: (51.0, 30.0, 0.0), 4: (0.0, 7.0, 0.0)}  # GPSInfo
        exif[0x010F] = "PhoneMaker"  # Make
        name = save_upload(
            upload("photo.jpg", image_bytes("JPEG", exif=exif.tobytes())),
            prefix="profile_images",
        )

        with default_storage.open(name) as handle:
            stored = Image.open(handle)
            self.assertEqual(dict(stored.getexif()), {})

    def test_orientation_is_applied_before_the_metadata_goes(self):
        # EXIF orientation 6 = rotate 90° to display. Dropping the tag without
        # applying it would show the photo on its side.
        exif = Image.Exif()
        exif[0x0112] = 6
        name = save_upload(
            upload("photo.jpg", image_bytes("JPEG", size=(8, 4), exif=exif.tobytes())),
            prefix="profile_images",
        )

        with default_storage.open(name) as handle:
            self.assertEqual(Image.open(handle).size, (4, 8))


class UploadEndpointTests(TempMediaMixin, FirestoreTestMixin, APITestCase):
    collections_to_purge = ["people", "user_profiles"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="uploader", password="pw")
        self.client.force_authenticate(user=self.user)

    def test_profile_rejects_html(self):
        response = self.client.patch(
            "/api/user/profile/",
            {"profile_image": upload("x.html", HTML, "text/html")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("profile_image", response.data)
        self.assertEqual(self.stored_files(), [])

    @patch(
        "apps.people.views.geocode_address",
        return_value=(51.5074, -0.1278, "Europe/London"),
    )
    def test_person_rejects_svg(self, _geocode):
        response = self.client.post(
            "/api/people/",
            {
                "first_name": "Ada",
                "last_name": "Lovelace",
                "city": "London",
                "country": "UK",
                "tag": "FRIEND",
                "profile_image": upload("x.svg", SVG, "image/svg+xml"),
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("profile_image", response.data)
        self.assertEqual(self.stored_files(), [])


LONDON = (51.5074, -0.1278, "Europe/London")
PERSON = {"first_name": "Ada", "city": "London", "country": "UK", "tag": "FRIEND"}


@patch("apps.people.views.geocode_address", return_value=LONDON)
class PersonPhotoLifecycleTests(
    ThrottleIsolationMixin, TempMediaMixin, FirestoreTestMixin, APITestCase
):
    """The bucket serves every object to anyone with its URL, cached for a
    year, so a person's photo is stored only once the write it belongs to is
    sure to land, and goes when it stops being theirs."""

    collections_to_purge = ["people"]

    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user(username="uploader", password="pw")
        self.other = User.objects.create_user(username="other", password="pw")
        self.client.force_authenticate(user=self.user)

    def photo(self):
        return upload("avatar.png", image_bytes("PNG"))

    def create_with_photo(self):
        response = self.client.post(
            "/api/people/",
            {**PERSON, "profile_image": self.photo()},
            format="multipart",
        )
        self.assertEqual(response.status_code, 201)
        [stored] = self.stored_files()
        return response.data["id"], stored

    def test_a_patch_for_an_unknown_person_stores_nothing(self, geocode):
        response = self.client.patch(
            "/api/people/not-a-real-id/",
            {"city": "Paris", "profile_image": self.photo()},
            format="multipart",
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.stored_files(), [])
        geocode.assert_not_called()

    def test_a_patch_for_someone_elses_person_stores_nothing(self, geocode):
        person_id, _ = self.create_with_photo()
        geocode.reset_mock()
        before = self.stored_files()
        self.client.force_authenticate(user=self.other)

        response = self.client.patch(
            f"/api/people/{person_id}/",
            {"city": "Paris", "profile_image": self.photo()},
            format="multipart",
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.stored_files(), before)
        geocode.assert_not_called()

    def test_a_create_with_a_bad_photo_is_refused_before_geocoding(self, geocode):
        response = self.client.post(
            "/api/people/",
            {**PERSON, "profile_image": upload("x.svg", SVG, "image/svg+xml")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("profile_image", response.data)
        self.assertEqual(self.stored_files(), [])
        geocode.assert_not_called()

    def test_an_update_with_a_bad_photo_is_refused_before_geocoding(self, geocode):
        person_id, first = self.create_with_photo()
        geocode.reset_mock()

        response = self.client.patch(
            f"/api/people/{person_id}/",
            {"city": "Paris", "profile_image": upload("x.html", HTML, "text/html")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("profile_image", response.data)
        self.assertEqual(self.stored_files(), [first])
        geocode.assert_not_called()

    def test_a_bad_address_stores_no_photo(self, geocode):
        geocode.side_effect = DjangoValidationError("Could not geocode address")

        response = self.client.post(
            "/api/people/",
            {**PERSON, "profile_image": self.photo()},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.stored_files(), [])

    def test_a_failed_create_removes_the_photo_it_stored(self, _geocode):
        with patch(
            "apps.people.repositories.PersonRepository.create",
            side_effect=gcloud_exceptions.ServiceUnavailable("down"),
        ):
            response = self.client.post(
                "/api/people/",
                {**PERSON, "profile_image": self.photo()},
                format="multipart",
            )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.stored_files(), [])

    def test_a_failed_update_removes_the_photo_it_stored(self, _geocode):
        person_id, first = self.create_with_photo()

        with patch(
            "apps.people.repositories.PersonRepository.update",
            side_effect=gcloud_exceptions.ServiceUnavailable("down"),
        ):
            response = self.client.patch(
                f"/api/people/{person_id}/",
                {"profile_image": self.photo()},
                format="multipart",
            )

        self.assertEqual(response.status_code, 503)
        # The old photo is still the person's, so it stays.
        self.assertEqual(self.stored_files(), [first])

    def test_replacing_a_photo_deletes_the_old_one(self, _geocode):
        person_id, first = self.create_with_photo()

        response = self.client.patch(
            f"/api/people/{person_id}/",
            {"profile_image": self.photo()},
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        [second] = self.stored_files()
        self.assertNotEqual(second, first)
        self.assertTrue(
            response.data["properties"]["profile_image"].endswith(second.name)
        )

    def test_a_patch_without_a_photo_keeps_it(self, _geocode):
        person_id, first = self.create_with_photo()

        response = self.client.patch(
            f"/api/people/{person_id}/", {"first_name": "Augusta"}, format="multipart"
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.stored_files(), [first])

    def test_deleting_a_person_deletes_their_photo(self, _geocode):
        person_id, _ = self.create_with_photo()

        response = self.client.delete(f"/api/people/{person_id}/")

        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.stored_files(), [])

    def test_a_storage_failure_does_not_fail_the_delete(self, _geocode):
        person_id, _ = self.create_with_photo()

        with (
            patch(
                "django.core.files.storage.FileSystemStorage.delete",
                side_effect=OSError("down"),
            ),
            self.assertLogs("apps.common.storage", level="ERROR"),
        ):
            response = self.client.delete(f"/api/people/{person_id}/")

        self.assertEqual(response.status_code, 204)
