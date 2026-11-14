import io
import shutil
import tempfile
from unittest import mock

from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory, SimpleTestCase, override_settings
from PIL import Image

from apps.common.storage import delete_upload, save_upload, upload_url


def png(name="avatar.png", color="red"):
    buffer = io.BytesIO()
    Image.new("RGB", (2, 2), color=color).save(buffer, format="PNG")
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/png")


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
