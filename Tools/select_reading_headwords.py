"""Print the word selection for Lexora's public reading dictionary.

Use the Simple English Wiktionary dump and Britfone revision documented in
docs/dictionary.md. The English and Chinese editions supply the actual entries.
"""
import argparse
import gzip
from hashlib import sha256
import json
from pathlib import Path
import re

from import_pronunciations import UK_FILENAME, source_text


SIMPLE_SHA256 = "79afd871e342db3b87c3f2044ed21efa312e4c4ee006814b57c4cf4536ef70a1"
HEADWORD = re.compile("[a-z]+(?:['-][a-z]+)*")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simple_dump", type=Path, help="Kaikki simple-extract.jsonl.gz")
    parser.add_argument("--sources", type=Path, help="Directory containing the pinned Britfone CSV")
    args = parser.parse_args()
    if sha256(args.simple_dump.read_bytes()).hexdigest() != SIMPLE_SHA256:
        parser.error("The Simple English dump does not match the documented SHA-256.")

    chosen = set()
    for name in ("starter-headwords.txt", "modern-reading-headwords.txt"):
        chosen.update(Path(__file__).with_name(name).read_text(encoding="utf-8").split())
    for line in source_text(UK_FILENAME, args.sources).splitlines():
        spelling = line.partition(",")[0].lower()
        chosen.add(re.sub(r"\(\d+\)$", "", spelling))

    with gzip.open(args.simple_dump) as stream:
        for line in stream:
            entry = json.loads(line)
            if entry.get("lang_code") != "en":
                continue
            # A gloss with an example is evidence of use in a learner's context.
            for sense in entry.get("senses", []):
                if sense.get("glosses") and any(ex.get("text", "").strip() for ex in sense.get("examples", [])):
                    chosen.add(entry["word"])
                    break

    for word in sorted(chosen):
        if HEADWORD.fullmatch(word):
            print(word)


if __name__ == "__main__":
    main()
