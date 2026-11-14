import io
import shutil
import tempfile
from unittest import mock

from django.contrib.auth.models import User
from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory, SimpleTestCase, override_settings
from PIL import Image
from rest_framework import serializers
from rest_framework.test import APITestCase

from apps.common.storage import (
    MAX_IMAGE_SIDE,
    clean_image,
    delete_upload,
    save_upload,
    store_image,
    upload_url,
)
from apps.common.testing import FirestoreTestMixin, ThrottleIsolationMixin


def png(name="avatar.png", color="red"):
    buffer = io.BytesIO()
    Image.new("RGB", (2, 2), color=color).save(buffer, format="PNG")
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/png")


def mpo(name="photo.jpg", size=(4, 4)):
    """A multi-picture JPEG, as phones write for depth maps and HDR gain maps.

    Pillow opens it as format "MPO", not "JPEG".
    """
    buffer = io.BytesIO()
    first = Image.new("RGB", size, color="blue")
    second = Image.new("RGB", size, color="yellow")
    first.save(buffer, format="MPO", save_all=True, append_images=[second])
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/jpeg")


class TempMediaMixin:
    def setUp(self):
        super().setUp()
        media_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media_root, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=media_root)
        media.enable()
        self.addCleanup(media.disable)


class MultiPictureJpegTests(TempMediaMixin, SimpleTestCase):
    """A phone JPEG with an MPF segment is a JPEG, and is stored as a plain one."""

    def test_the_test_image_really_is_an_mpo(self):
        with Image.open(mpo()) as image:
            self.assertEqual(image.format, "MPO")
            self.assertEqual(image.n_frames, 2)

    def test_clean_image_accepts_it_as_a_jpeg(self):
        content, extension = clean_image(mpo())

        self.assertEqual(extension, ".jpg")
        with Image.open(io.BytesIO(content)) as image:
            self.assertEqual(image.format, "JPEG")

    def test_it_is_stored_as_a_single_frame_jpeg_of_the_first_picture(self):
        name = save_upload(mpo(), prefix="profile_images")

        self.assertRegex(name, r"^profile_images/[0-9a-f]{32}\.jpg$")
        with default_storage.open(name) as handle:
            data = handle.read()
        # No MPF (APP2 "MPF\0") segment survives, so nothing reads it as MPO.
        self.assertNotIn(b"MPF\x00", data)
        with Image.open(io.BytesIO(data)) as image:
            self.assertEqual(image.format, "JPEG")
            self.assertEqual(getattr(image, "n_frames", 1), 1)
            red, green, blue = image.convert("RGB").getpixel((0, 0))
            self.assertGreater(blue, 200)
            self.assertLess(red + green, 60)

    def test_delete_upload_removes_it(self):
        name = save_upload(mpo(), prefix="profile_images")

        delete_upload(name, prefix="profile_images")

        self.assertFalse(default_storage.exists(name))

    def test_store_image_names_it_so_delete_upload_can_remove_it(self):
        # clean_image then store_image, as a caller that validates before
        # other checks and stores after them does.
        content, extension = clean_image(mpo())
        name = store_image(content, extension, prefix="profile_images")

        self.assertRegex(name, r"^profile_images/[0-9a-f]{32}\.jpg$")
        with default_storage.open(name) as handle:
            self.assertEqual(handle.read(), content)
        delete_upload(name, prefix="profile_images")
        self.assertFalse(default_storage.exists(name))

    def test_the_side_limit_still_applies(self):
        with self.assertRaises(serializers.ValidationError):
            clean_image(mpo(size=(MAX_IMAGE_SIDE + 1, 1)))


class MultiPictureJpegEndpointTests(
    TempMediaMixin, ThrottleIsolationMixin, FirestoreTestMixin, APITestCase
):
    collections_to_purge = ["user_profiles"]

    def test_a_profile_photo_from_a_phone_is_accepted(self):
        user = User.objects.create_user(username="phone", password="pw")
        self.client.force_authenticate(user=user)

        response = self.client.patch(
            "/api/user/profile/",
            {"profile_image": mpo("IMG_0001.JPG")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertRegex(
            response.data["profile_image"],
            r"/media/user_profiles/[0-9a-f]{32}\.jpg$",
        )


class StorageTests(SimpleTestCase):
    """Naming and URLs. What gets accepted is in test_image_uploads.py."""

    def setUp(self):
        media_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media_root, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=media_root)
        media.enable()
        self.addCleanup(media.disable)

    def test_save_upload_returns_prefixed_name(self):
        name = save_upload(png(), prefix="profile_images")
        self.assertTrue(name.startswith("profile_images/"))
        self.assertTrue(name.endswith(".png"))

    def test_saved_names_do_not_collide(self):
        first = save_upload(png("a.png"), prefix="profile_images")
        second = save_upload(png("a.png"), prefix="profile_images")
        self.assertNotEqual(first, second)

    def test_upload_url_returns_media_url(self):
        name = save_upload(png("b.png"), prefix="profile_images")
        self.assertIn("/media/profile_images/", upload_url(name))

    def test_upload_url_of_none_is_none(self):
        self.assertIsNone(upload_url(None))

    def test_upload_url_of_empty_name_is_none(self):
        # Firestore documents store "" as well as None for "no image".
        self.assertIsNone(upload_url(""))

    def test_upload_url_with_request_is_absolute(self):
        name = save_upload(png("c.png"), prefix="profile_images")
        request = RequestFactory().get("/api/user/profile/")
        url = upload_url(name, request=request)
        self.assertTrue(url.startswith("http://testserver/media/profile_images/"))
        self.assertTrue(url.endswith(".png"))

    def test_save_upload_ignores_the_client_extension_case(self):
        name = save_upload(png("PHOTO.PNG"), prefix="profile_images")
        self.assertTrue(name.endswith(".png"))

    def test_save_upload_discards_original_stem(self):
        # The client-supplied filename never reaches storage.
        name = save_upload(png("Ada Lovelace.png"), prefix="profile_images")
        self.assertNotIn("Lovelace", name)
        self.assertNotIn(" ", name)

    def test_saved_image_keeps_its_pixels(self):
        # Re-encoded, so not byte-for-byte the upload, but the same picture.
        name = save_upload(png("d.png", color="blue"), prefix="profile_images")
        with default_storage.open(name) as handle:
            image = Image.open(handle)
            self.assertEqual(image.size, (2, 2))
            self.assertEqual(image.convert("RGB").getpixel((0, 0)), (0, 0, 255))


class DeleteUploadTests(SimpleTestCase):
    def setUp(self):
        media_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media_root, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=media_root)
        media.enable()
        self.addCleanup(media.disable)

    def test_deletes_a_file_save_upload_stored(self):
        name = save_upload(png(), prefix="profile_images")

        delete_upload(name, prefix="profile_images")

        self.assertFalse(default_storage.exists(name))

    def test_leaves_anything_save_upload_would_not_have_named(self):
        # The field is data; only a name this app gave a photo under this
        # prefix is ever removed.
        other_prefix = save_upload(png(), prefix="user_profiles")
        names = [
            "",
            None,
            other_prefix,
            "profile_images/../secrets.png",
            "profile_images/ada.png",
            "https://example.com/profile_images/" + "a" * 32 + ".png",
            "profile_images/" + "a" * 32 + ".svg",
        ]
        with mock.patch.object(default_storage, "delete") as delete:
            for name in names:
                delete_upload(name, prefix="profile_images")
        delete.assert_not_called()
        self.assertTrue(default_storage.exists(other_prefix))

    def test_a_storage_failure_is_logged_not_raised(self):
        name = save_upload(png(), prefix="profile_images")

        with (
            mock.patch(
                "django.core.files.storage.FileSystemStorage.delete",
                side_effect=OSError("bucket unreachable"),
            ),
            self.assertLogs("apps.common.storage", level="ERROR") as logs,
        ):
            delete_upload(name, prefix="profile_images")

        self.assertIn(name, logs.output[0])


class CloudStorageTests(SimpleTestCase):
    """Uploads through the production backend: django-storages' Cloud Storage.

    The bucket is a mock, so this checks what the app asks Cloud Storage for
    (object name, content type, caching) and the URL it hands the app back,
    without a network. infra/tests checks the bucket's own access rules.
    """

    def setUp(self):
        from google.auth.credentials import AnonymousCredentials
        from storages.backends.gcloud import GoogleCloudStorage

        self.bucket = mock.MagicMock()
        self.bucket.name = "mmf-media"
        self.blobs = {}

        def blob(name, **kwargs):
            if name not in self.blobs:
                b = mock.MagicMock()
                b.name = name
                b.public_url = f"https://storage.googleapis.com/mmf-media/{name}"
                self.blobs[name] = b
            return self.blobs[name]

        self.bucket.blob.side_effect = blob
        # A new object: django-storages looks it up, finds nothing, and makes
        # a Blob to upload to.
        self.bucket.get_blob.return_value = None
        blob_class = mock.patch(
            "storages.backends.gcloud.Blob",
            side_effect=lambda name, bucket, **kwargs: blob(name),
        )
        blob_class.start()
        self.addCleanup(blob_class.stop)
        patcher = mock.patch.object(
            GoogleCloudStorage,
            "bucket",
            new_callable=mock.PropertyMock,
            return_value=self.bucket,
        )
        patcher.start()
        self.addCleanup(patcher.stop)

        options = {
            **_production_storage_options(),
            "credentials": AnonymousCredentials(),
        }
        storages = override_settings(
            STORAGES={
                "default": {
                    "BACKEND": "storages.backends.gcloud.GoogleCloudStorage",
                    "OPTIONS": options,
                },
                "staticfiles": {
                    "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"
                },
            }
        )
        # Changing STORAGES makes Django rebuild default_storage.
        storages.enable()
        self.addCleanup(storages.disable)

    def test_an_upload_is_written_to_the_bucket_under_its_new_name(self):
        name = save_upload(png("selfie.png"), prefix="profile_images")

        self.assertRegex(name, r"^profile_images/[0-9a-f]{32}\.png$")
        blob = self.blobs[name]
        blob.upload_from_file.assert_called_once()
        self.assertEqual(
            blob.upload_from_file.call_args.kwargs["content_type"], "image/png"
        )

    def test_it_doesnt_look_for_a_free_name_first(self):
        # A UUID can't collide. Django's default get_available_name would
        # ask exists() in a loop, a round trip each time.
        with mock.patch(
            "storages.backends.gcloud.GoogleCloudStorage.exists",
            side_effect=AssertionError("checked whether the name was taken"),
        ):
            save_upload(png(), prefix="profile_images")

    def test_objects_are_cached_for_good(self):
        # Names are never reused, so a cached photo can't go stale.
        name = save_upload(png(), prefix="profile_images")

        self.assertEqual(
            self.blobs[name].cache_control, "public, max-age=31536000, immutable"
        )

    def test_the_url_is_the_objects_public_one(self):
        name = save_upload(png(), prefix="profile_images")
        request = RequestFactory().get("/", HTTP_HOST="api.example.com")

        self.assertEqual(
            upload_url(name, request),
            f"https://storage.googleapis.com/mmf-media/{name}",
        )
        self.blobs[name].generate_signed_url.assert_not_called()

    def test_delete_upload_removes_the_object_from_the_bucket(self):
        name = save_upload(png(), prefix="profile_images")

        delete_upload(name, prefix="profile_images")

        self.bucket.delete_blob.assert_called_once()
        self.assertEqual(self.bucket.delete_blob.call_args.args[0], name)


def _production_storage_options():
    """The OPTIONS settings.py gives the bucket backend in production."""
    import importlib.util
    import os

    import config.settings as settings_module

    spec = importlib.util.spec_from_file_location(
        "bucket_settings", settings_module.__file__
    )
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(
        os.environ,
        {"DJANGO_DEBUG": "True", "GS_BUCKET_NAME": "mmf-media"},
    ):
        spec.loader.exec_module(module)
    return dict(module.STORAGES["default"]["OPTIONS"])
