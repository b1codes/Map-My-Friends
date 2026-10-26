from django.core.files.storage import default_storage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory, SimpleTestCase

from apps.common.storage import save_upload, upload_url


class StorageTests(SimpleTestCase):
    def test_save_upload_returns_prefixed_name(self):
        upload = SimpleUploadedFile(
            "avatar.png", b"fake-image-bytes", content_type="image/png"
        )
        name = save_upload(upload, prefix="profile_images")
        self.assertTrue(name.startswith("profile_images/"))
        self.assertTrue(name.endswith(".png"))

    def test_saved_names_do_not_collide(self):
        first = save_upload(
            SimpleUploadedFile("a.png", b"one", content_type="image/png"),
            prefix="profile_images",
        )
        second = save_upload(
            SimpleUploadedFile("a.png", b"two", content_type="image/png"),
            prefix="profile_images",
        )
        self.assertNotEqual(first, second)

    def test_upload_url_returns_media_url(self):
        name = save_upload(
            SimpleUploadedFile("b.png", b"bytes", content_type="image/png"),
            prefix="profile_images",
        )
        self.assertIn("/media/profile_images/", upload_url(name))

    def test_upload_url_of_none_is_none(self):
        self.assertIsNone(upload_url(None))

    def test_upload_url_of_empty_name_is_none(self):
        # Firestore documents store "" as well as None for "no image".
        self.assertIsNone(upload_url(""))

    def test_upload_url_with_request_is_absolute(self):
        name = save_upload(
            SimpleUploadedFile("c.png", b"bytes", content_type="image/png"),
            prefix="profile_images",
        )
        self.addCleanup(default_storage.delete, name)
        request = RequestFactory().get("/api/user/profile/")
        url = upload_url(name, request=request)
        self.assertTrue(url.startswith("http://testserver/media/profile_images/"))
        self.assertTrue(url.endswith(".png"))

    def test_save_upload_lowercases_extension(self):
        name = save_upload(
            SimpleUploadedFile("PHOTO.JPG", b"bytes", content_type="image/jpeg"),
            prefix="profile_images",
        )
        self.addCleanup(default_storage.delete, name)
        self.assertTrue(name.endswith(".jpg"))

    def test_save_upload_discards_original_stem(self):
        # The client-supplied filename never reaches storage, only its suffix.
        name = save_upload(
            SimpleUploadedFile("Ada Lovelace.png", b"x", content_type="image/png"),
            prefix="profile_images",
        )
        self.addCleanup(default_storage.delete, name)
        self.assertNotIn("Lovelace", name)
        self.assertNotIn(" ", name)

    def test_saved_file_content_round_trips(self):
        name = save_upload(
            SimpleUploadedFile("d.png", b"payload-bytes", content_type="image/png"),
            prefix="profile_images",
        )
        self.addCleanup(default_storage.delete, name)
        with default_storage.open(name) as handle:
            self.assertEqual(handle.read(), b"payload-bytes")
