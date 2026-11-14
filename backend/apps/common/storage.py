"""File storage helpers.

Django's ImageField previously handled naming, saving and URL generation. With
the models gone those steps become explicit. Everything routes through
`default_storage`, so the STORAGES setting alone decides between the local
filesystem and Cloud Storage — no code branches on environment.
"""

from __future__ import annotations

import io
import logging
import re
import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from PIL import Image, ImageOps, UnidentifiedImageError
from rest_framework import serializers

logger = logging.getLogger(__name__)

# The app uploads a cropped PNG of at most 1024x1024 (add_edit_person_screen
# and the profile screen); these leave room for a phone photo sent directly.
MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_SIDE = 4096

# Pillow format -> stored extension. Only formats a browser shows as a plain
# picture: no SVG (it runs scripts), and nothing exotic for Pillow to parse.
IMAGE_FORMATS = {"PNG": ".png", "JPEG": ".jpg", "WEBP": ".webp"}


def _invalid(message: str) -> serializers.ValidationError:
    return serializers.ValidationError({"profile_image": [message]})


def clean_image(uploaded_file) -> tuple[bytes, str]:
    """Check an upload is a real image and re-encode it.

    Returns the new bytes and the extension to store them under. The upload's
    own name and content type are the client's to choose, so neither decides
    anything: the format Pillow finds does. Re-encoding keeps only the pixels,
    which drops anything appended after the image (an HTML/image polyglot)
    and the metadata, including the GPS position a phone photo was taken at.
    Raises a 400-shaped ValidationError for anything else.
    """
    if uploaded_file.size > MAX_IMAGE_BYTES:
        raise _invalid(f"Images must be under {MAX_IMAGE_BYTES // (1024 * 1024)} MB.")

    data = uploaded_file.read()
    too_large = _invalid(
        f"Images must be at most {MAX_IMAGE_SIDE} pixels on each side."
    )
    try:
        with Image.open(io.BytesIO(data)) as probe:
            fmt = probe.format
            width, height = probe.size
        if fmt not in IMAGE_FORMATS:
            raise _invalid("Upload a PNG, JPEG or WebP image.")
        # Checked before decoding: a small, highly compressed file can
        # decode to gigabytes.
        if max(width, height) > MAX_IMAGE_SIDE:
            raise too_large
        with Image.open(io.BytesIO(data)) as image:
            image.load()
            # Applies the EXIF orientation to the pixels, since the tag that
            # records it is about to be dropped with the rest.
            upright = ImageOps.exif_transpose(image)
    except Image.DecompressionBombError as e:
        # Pillow's own pixel limit, which Image.open enforces from the header
        # alone, before the side check above sees the size. It is a plain
        # Exception, not one of the decoder errors below.
        raise too_large from e
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as e:
        # Pillow reports a truncated or corrupt file as OSError (or, for some
        # decoders, SyntaxError/ValueError).
        raise _invalid("Upload a PNG, JPEG or WebP image.") from e

    if fmt == "JPEG" and upright.mode not in ("RGB", "L"):
        upright = upright.convert("RGB")
    out = io.BytesIO()
    save_args = {"quality": 90} if fmt in ("JPEG", "WEBP") else {}
    upright.save(out, format=fmt, **save_args)
    return out.getvalue(), IMAGE_FORMATS[fmt]


def save_upload(uploaded_file, prefix: str) -> str:
    """Validate an uploaded image and persist it under `prefix/`.

    Returns the storage name. The stem is a UUID, so identically named uploads
    don't collide and the client's filename never reaches storage, and the
    extension is the image's real format, which is what decides the content
    type /media/ serves it with.
    """
    content, extension = clean_image(uploaded_file)
    name = f"{prefix}/{uuid.uuid4().hex}{extension}"
    return default_storage.save(name, ContentFile(content))


def delete_upload(name: str | None, prefix: str) -> None:
    """Delete a file save_upload stored under `prefix/`, if name is one.

    For a photo that stopped being anyone's: its person was deleted, or it
    was replaced. The bucket serves every object to anyone with its URL, so
    one left behind stays readable. Only a name save_upload could have given
    under this prefix is deleted; the field is data, and anything else in it
    is not this app's file to remove.

    Best effort: the change that orphaned the file has already been saved,
    so a storage failure is logged rather than raised.
    """
    extensions = "|".join(re.escape(ext) for ext in IMAGE_FORMATS.values())
    pattern = rf"{re.escape(prefix)}/[0-9a-f]{{32}}(?:{extensions})"
    if not name or not re.fullmatch(pattern, name):
        return
    try:
        default_storage.delete(name)
    except Exception:
        logger.exception("Could not delete the stored upload %s", name)


def upload_url(name: str | None, request=None) -> str | None:
    """Absolute URL for a stored file name, or None when unset."""
    if not name:
        return None
    url = default_storage.url(name)
    if request is not None:
        return request.build_absolute_uri(url)
    return url
