#!/usr/bin/env python3
"""Install pinned, verified Kokoro Core ML assets before building Lexora."""
import hashlib
import json
import sqlite3
import subprocess
import tempfile
from contextlib import closing
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
PACK = TOOLS.parent / "KokoroVoicePack"
MODEL_REPO = "https://huggingface.co/aufklarer/Kokoro-82M-CoreML-INT8/resolve"
MISAKI_REPO = "https://raw.githubusercontent.com/hexgrad/misaki"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(url, path, expected):
    print(f"Downloading {path.name}", flush=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                    "--retry", "3", "--connect-timeout", "15", "--max-time", "600",
                    "--output", str(path), url], check=True)
    if sha256(path) != expected:
        raise ValueError(f"SHA-256 mismatch for {url}")


def lexicon_matches(path, expected):
    if not path.is_file():
        return False
    digest = hashlib.sha256()
    try:
        with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as db:
            for row in db.execute("SELECT accent, word, pronunciation FROM phoneme "
                                  "ORDER BY accent, word COLLATE BINARY"):
                digest.update(("\0".join(row) + "\n").encode("utf-8"))
    except sqlite3.DatabaseError:
        return False
    return digest.hexdigest() == expected


def build_lexicon(path, inputs):
    with closing(sqlite3.connect(path)) as db:
        db.execute("CREATE TABLE phoneme (accent TEXT, word TEXT COLLATE NOCASE, "
                   "pronunciation TEXT NOT NULL, PRIMARY KEY(accent,word)) WITHOUT ROWID")
        for accent in ("gb", "us"):
            # Gold overrides silver; later case variants override earlier ones.
            for quality in ("silver", "gold"):
                data = json.loads((inputs / f"{accent}_{quality}.json").read_text(encoding="utf-8"))
                rows = []
                for word, pronunciation in data.items():
                    if isinstance(pronunciation, dict):
                        pronunciation = pronunciation.get("DEFAULT")
                    if pronunciation:
                        rows.append((accent, word.lower(), pronunciation))
                db.executemany("INSERT OR REPLACE INTO phoneme VALUES (?, ?, ?)", rows)
        db.commit()


def main():
    spec = json.loads((TOOLS / "voice_assets.json").read_text(encoding="utf-8"))
    PACK.mkdir(exist_ok=True)
    # Keep partial downloads and temporary input JSONs outside the bundled resource folder.
    with tempfile.TemporaryDirectory(prefix=".lexora-voice-", dir=PACK.parent) as temporary:
        staging = Path(temporary)
        pending = []
        for name, expected in spec["models"].items():
            target = PACK / name
            if target.is_file() and sha256(target) == expected:
                continue
            output = staging / name
            fetch(f"{MODEL_REPO}/{spec['model_revision']}/{name}", output, expected)
            pending.append((output, target))

        db = PACK / "lexicon.sqlite"
        expected = spec["lexicon_rows_sha256"]
        if not lexicon_matches(db, expected):
            for name, checksum in spec["dictionaries"].items():
                source = f"{MISAKI_REPO}/{spec['misaki_revision']}/misaki/data/{name}"
                fetch(source, staging / name, checksum)
            output = staging / db.name
            build_lexicon(output, staging)
            if not lexicon_matches(output, expected):
                raise ValueError("Kokoro pronunciation lexicon verification failed")
            pending.append((output, db))

        for output, target in pending:
            target.parent.mkdir(parents=True, exist_ok=True)
            output.replace(target)
    print("Kokoro voice pack ready.")


if __name__ == "__main__":
    main()
