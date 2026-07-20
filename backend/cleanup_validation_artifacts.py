"""
Dev-only cleanup for validation/smoke/E2E artifacts.

WHY THIS EXISTS
Live smoke/E2E validation used to create real, user-visible rows (posts, clips)
and leave them behind, polluting the app. The fix is a discipline + a helper:

    FUTURE VALIDATION CONTRACT
    - Any row a test/smoke creates MUST be tagged with the reserved marker prefix
      below (e.g. content/title = "__validation_<uuid> ..."), and
    - the test SHOULD call cleanup in a try/finally so the row is removed even if
      the test fails partway.

This helper deletes ONLY rows whose text starts with the reserved marker. It does
NOT match generic words like "test" or "smoke" (those can appear in legitimate
content), and it is NOT wired into any API/route — it is a manual dev tool only.

Usage:
    cd backend
    ./.venv/bin/python cleanup_validation_artifacts.py          # dry run (report)
    ./.venv/bin/python cleanup_validation_artifacts.py --apply  # actually delete

Never import this from product code. Never add a purge API endpoint.
"""
import os
import sqlite3
import sys

DB_PATH = os.path.join(os.path.dirname(__file__), "sportshub.db")
VIDEO_DIR = os.path.join(os.path.dirname(__file__), "uploads", "videos")

# The ONE reserved marker. Tag any validation-created row's primary text with this.
VALIDATION_MARKER = "__validation_"


def _matches(*values: object) -> bool:
    return any(str(v or "").startswith(VALIDATION_MARKER) for v in values)


def cleanup(apply: bool = False) -> None:
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    removed_files = []

    # Clips: delete the row and its exclusively-owned media file.
    clip_ids = []
    for r in db.execute("SELECT id, title, description, video_url FROM clips"):
        if _matches(r["title"], r["description"]):
            clip_ids.append(r["id"])
            if r["video_url"]:
                fname = str(r["video_url"]).rsplit("/", 1)[-1]
                others = db.execute(
                    "SELECT COUNT(*) FROM clips WHERE video_url=? AND id<>?",
                    (r["video_url"], r["id"]),
                ).fetchone()[0]
                if others == 0:
                    removed_files.append(os.path.join(VIDEO_DIR, fname))

    post_ids = [r["id"] for r in db.execute("SELECT id, content FROM posts") if _matches(r["content"])]

    print(f"[cleanup] validation posts: {len(post_ids)}  clips: {len(clip_ids)}  "
          f"exclusive media files: {len(removed_files)}  (apply={apply})")

    if not apply:
        print("[cleanup] dry run — pass --apply to delete.")
        db.close()
        return

    if post_ids:
        db.execute(f"DELETE FROM posts WHERE id IN ({','.join('?'*len(post_ids))})", post_ids)
    if clip_ids:
        db.execute(f"DELETE FROM clips WHERE id IN ({','.join('?'*len(clip_ids))})", clip_ids)
    db.commit()
    db.close()

    for path in removed_files:
        if os.path.exists(path):
            os.remove(path)
            print(f"[cleanup] removed media: {path}")

    print(f"[cleanup] done — deleted {len(post_ids)} posts, {len(clip_ids)} clips.")


if __name__ == "__main__":
    cleanup(apply="--apply" in sys.argv)
