"""
Central upload validation — content-based (magic-byte) media checking with
bounded reading and atomic, self-cleaning writes.

Why not trust the client content_type / filename?
  The iOS client hardcodes some MIME types (e.g. clip uploads declare
  "video/mp4" even when the bytes are a QuickTime .mov) and filenames are fully
  attacker-controlled. So the ACCEPT decision is made from the file's real
  signature, and the stored extension is derived from the detected bytes — never
  from the declared type or the client filename.

Public helpers:
  read_upload_capped(upload, max_bytes, label)  — async, memory-bounded read
  validate_media(data, allowed, max_bytes, label) -> (kind, ext)
  save_bytes_atomic(directory, filename, data) -> final_path   (temp + rename)
  sniff_media_kind(data) -> kind | None                         (strict)

All rejections raise HTTPException (400 empty/unrecognized, 413 too large,
415 unsupported) — safe, user-facing messages with no paths or internals.
"""
import os
import uuid as _uuid

from fastapi import HTTPException, status

MB = 1024 * 1024
_READ_CHUNK = 1 * MB

# Canonical media kinds → stored extension.
_EXT = {
    "jpeg": ".jpg",
    "png": ".png",
    "webp": ".webp",
    "gif": ".gif",
    "mp4": ".mp4",
    "mov": ".mov",
}

IMAGE_KINDS = frozenset({"jpeg", "png", "webp"})
IMAGE_KINDS_WITH_GIF = frozenset({"jpeg", "png", "webp", "gif"})
VIDEO_KINDS = frozenset({"mp4", "mov"})

# ── ISO Base Media File Format brands ───────────────────────────────────────
# MP4-family major/compatible brands we accept. iOS-exported MP4 commonly uses
# isom / mp42 / M4V ; the rest are standard interoperable brands.
_MP4_BRANDS = {
    b"isom", b"iso2", b"iso4", b"iso5", b"iso6", b"mp41", b"mp42",
    b"avc1", b"mmp4", b"dash", b"cmfc", b"M4V ", b"M4A ", b"M4P ", b"M4B ",
    b"MSNV", b"NDSC", b"NDSM",
}
# QuickTime / MOV. iOS camera/PhotosPicker .mov files use major brand "qt  ".
_MOV_BRANDS = {b"qt  "}
# HEIC/HEIF still-image brands — recognized so we can reject them clearly
# (no surface currently accepts them) rather than mis-store them as video.
_HEIC_BRANDS = {b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1", b"heim", b"heis"}

_MAX_FTYP_BOX = 4096  # a real ftyp box is tiny; anything larger is implausible


def _sniff_iso_bmff(data: bytes) -> str | None:
    """Strictly validate an ISO-BMFF header and classify MP4 vs MOV vs HEIC.

    Requires a well-formed `ftyp` box as the FIRST box (offset 0):
      [4-byte big-endian box size][b'ftyp'][4-byte major brand][4-byte minor]...
    Rejects a planted 'ftyp' at a wrong offset, implausible/oversized/zero box
    sizes, truncated boxes, and unknown brands.
    """
    if len(data) < 16:
        return None
    if data[4:8] != b"ftyp":
        return None
    box_size = int.from_bytes(data[0:4], "big")
    # ftyp never uses 64-bit largesize (size==1) and is always small.
    if box_size < 16 or box_size > _MAX_FTYP_BOX:
        return None
    if box_size > len(data):
        return None  # truncated: header claims more than we received
    major = data[8:12]
    # Compatible brands run from offset 16 to the end of the box, 4 bytes each.
    brands = {major}
    off = 16
    while off + 4 <= box_size:
        brands.add(data[off:off + 4])
        off += 4
    if _MOV_BRANDS & brands:
        return "mov"
    if _MP4_BRANDS & brands:
        return "mp4"
    if _HEIC_BRANDS & brands:
        return "heic"
    return None


def sniff_media_kind(data: bytes) -> str | None:
    """Return the canonical media kind from magic bytes, or None if the bytes
    are not a recognized image/video container."""
    if len(data) < 12:
        return None
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[4:8] == b"ftyp":
        return _sniff_iso_bmff(data)
    return None


async def read_upload_capped(upload, max_bytes: int, label: str = "File") -> bytes:
    """Read an UploadFile in chunks, stopping as soon as the surface limit is
    exceeded. Memory is bounded to at most max_bytes + one chunk; we never read
    a whole oversized upload into memory. Raises 413 on overflow."""
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await upload.read(_READ_CHUNK)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"{label} is too large. Maximum size is {max_bytes // MB} MB.",
            )
        chunks.append(chunk)
    return b"".join(chunks)


def validate_media(data: bytes, *, allowed: frozenset, max_bytes: int, label: str = "File"):
    """Validate bytes by size and real content type. Returns (kind, ext).
    Raises HTTPException — call BEFORE writing anything so a rejected upload
    leaves no artifacts."""
    size = len(data)
    if size == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="The selected file is empty.")
    if size > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"{label} is too large. Maximum size is {max_bytes // MB} MB.",
        )
    kind = sniff_media_kind(data)
    if kind is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="The selected file is not a supported media file.")
    if kind not in allowed:
        allowed_exts = ", ".join(sorted({_EXT[k].lstrip('.').upper() for k in allowed}))
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported {label.lower()} format. Allowed: {allowed_exts}.",
        )
    return kind, _EXT[kind]


def save_bytes_atomic(directory: str, filename: str, data: bytes) -> str:
    """Write bytes to `directory/filename` atomically: write to a per-request
    temp file, fsync, then os.replace() into place. On any failure the temp
    file is removed so no partial/final file is left behind. Returns the final
    path. Raises OSError on failure (caller maps to a generic 500)."""
    os.makedirs(directory, exist_ok=True)
    final_path = os.path.join(directory, filename)
    tmp_path = os.path.join(directory, f".{_uuid.uuid4().hex}.part")
    try:
        with open(tmp_path, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, final_path)  # atomic rename within the same dir
    except Exception:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise
    return final_path
