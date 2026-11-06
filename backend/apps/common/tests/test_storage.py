import io
import shutil
import tempfile

from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory, SimpleTestCase, override_settings
from PIL import Image

from apps.common.storage import save_upload, upload_url


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
