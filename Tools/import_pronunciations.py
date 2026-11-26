"""Import pinned Britfone and CMUdict headword pronunciations into a Lexora SQLite file.

Usage: python3 Tools/import_pronunciations.py path/to/Dictionary.sqlite
Add --sources DIR to read the two upstream files from disk instead of HTTPS.
Use --headwords-only to limit output to the dictionary and any --extra-word entries.
Both modes verify SHA-256. Run after build_dictionary.py. The import is atomic
and safe to repeat. Sources and transcription conventions are documented in
Resources/Pronunciation-Licenses.txt.
"""
import argparse
from collections import defaultdict
from hashlib import sha256
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile


UK_FILENAME = "britfone.main.3.0.1.csv"
US_FILENAME = "cmudict.dict"
SOURCES = {
    UK_FILENAME: (
        "https://raw.githubusercontent.com/JoseLlarena/Britfone/"
        "1062be14adc96c358f2087ac5449d72130c7a6f4/",
        "59f197e98520856d1cc88e380beb54e4314d8712efc4d588b6778819c502d920",
    ),
    US_FILENAME: (
        "https://raw.githubusercontent.com/cmusphinx/cmudict/"
        "74790861f652b15e4ac49015a90074ad62a27690/",
        "81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22",
    ),
}
CMU_PHONES = {
    "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ",
    "EH": "ɛ", "ER": "ɝ", "EY": "eɪ", "IH": "ɪ", "IY": "i", "OW": "oʊ",
    "OY": "ɔɪ", "UH": "ʊ", "UW": "u",
    "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "F": "f", "G": "ɡ",
    "HH": "h", "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n",
    "NG": "ŋ", "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t",
    "TH": "θ", "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ",
}
VOWELS = set("ɑ æ ə ʌ ɔ aʊ aɪ ɛ ɚ ɝ eɪ ɪ i oʊ ɔɪ ʊ u ɐ ɑː ɒ ɔː əʊ ɛə ɜː ɪə iː ʊə uː".split())
STRESS = {"0": "", "1": "ˈ", "2": "ˌ"}

# English onset maximisation for placing a written stress mark. Syllabification
# does not add, remove or replace phonemes. A standalone /ŋ/ stays in the coda.
COMPLEX_ONSETS = set("""
pɹ bɹ tɹ dɹ kɹ ɡɹ fɹ θɹ ʃɹ pl bl kl ɡl fl sl ʃl tw dw kw ɡw sw θw
sp st sk sm sn sf ʃm ʃn pj bj tj dj kj ɡj fj vj θj sj zj hj mj nj lj
spɹ stɹ skɹ spl skl skw spj stj skj smj snj sklj
""".split())


def source_text(filename, directory):
    base, expected = SOURCES[filename]
    if directory:
        data = (directory / filename).read_bytes()
    else:
        with tempfile.TemporaryDirectory() as temporary:
            download = Path(temporary) / filename
            subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                            "--retry", "2", "--retry-all-errors", "--max-time", "90",
                            "--output", str(download), base + filename], check=True)
            data = download.read_bytes()
    if sha256(data).hexdigest() != expected:
        raise ValueError(f"Unexpected SHA-256 for {filename}; use the pinned upstream file.")
    return data.decode("utf-8")


def cmu_phone(token):
    """Return an IPA phoneme and the source's stress, without using spelling."""
    if token[-1].isdigit():
        name, stress = token[:-1], token[-1]
        if token == "AH0":
            return "ə", ""
        if token == "ER0":
            return "ɚ", ""
        return CMU_PHONES[name], STRESS[stress]
    return CMU_PHONES[token], ""


def britfone_phone(token):
    if token.startswith(("ˈ", "ˌ")):
        return token[1:], token[0]
    return token, ""


def broad_ipa(phones):
    symbols = [symbol for symbol, _ in phones]
    nuclei = [i for i, symbol in enumerate(symbols) if symbol in VOWELS]
    if len(nuclei) > 1:
        previous = -1
        marks = {}
        for nucleus in nuclei:
            stress = phones[nucleus][1]
            if stress:
                if previous == -1:
                    onset = 0
                else:
                    onset = nucleus
                    for candidate in range(previous + 1, nucleus):
                        cluster = symbols[candidate:nucleus]
                        if (len(cluster) == 1 and cluster[0] != "ŋ") or "".join(cluster).replace("g", "ɡ") in COMPLEX_ONSETS:
                            onset = candidate
                            break
                marks[onset] = stress
            previous = nucleus
        for start, mark in marks.items():
            symbols[start] = mark + symbols[start]
    return "/" + "".join(symbols) + "/"


def pronunciations(text, region):
    by_word = defaultdict(dict)
    for line in text.splitlines():
        if region == "uk":
            headword, transcription = line.split(",", 1)
            headword = headword.replace("_", " ").lower()
            phones = [britfone_phone(t) for t in transcription.split()]
        else:
            headword, transcription = line.split(" ", 1)
            phones = [cmu_phone(t) for t in transcription.partition("#")[0].split()]
        word = re.sub(r"\(\d+\)$", "", headword)
        if not word or not phones:
            raise ValueError(f"Empty transcription in {region}: {line!r}")
        by_word[word][broad_ipa(phones)] = None
    for word, readings in by_word.items():
        for variant, ipa in enumerate(readings, start=1):
            yield word, region, variant, ipa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--sources", type=Path, help="Directory containing both pinned pronunciation files")
    parser.add_argument("--headwords-only", action="store_true", help="Import pronunciations only for words in the entry table and --extra-word")
    parser.add_argument("--extra-word", action="append", default=[], help="Include a pronunciation-only headword (with --headwords-only)")
    args = parser.parse_args()
    if args.extra_word and not args.headwords_only:
        parser.error("--extra-word requires --headwords-only")
    uk = source_text(UK_FILENAME, args.sources)
    us = source_text(US_FILENAME, args.sources)
    db = sqlite3.connect(args.database.resolve().as_uri() + "?mode=rw", uri=True)
    try:
        with db:
            db.execute("BEGIN IMMEDIATE")
            selected = None
            if args.headwords_only:
                selected = {row[0] for row in db.execute("SELECT DISTINCT word FROM entry")}
                selected.update(word.lower() for word in args.extra_word)
            db.execute("SELECT 1 FROM entry LIMIT 1")  # Require an existing Lexora dictionary.
            db.execute("DROP TABLE IF EXISTS reference_ipa")
            db.execute("""CREATE TABLE reference_ipa (
                word TEXT NOT NULL, region TEXT NOT NULL, variant INTEGER NOT NULL, ipa TEXT NOT NULL,
                PRIMARY KEY(word,region,variant)) WITHOUT ROWID""")
            for region, source in [("uk", uk), ("us", us)]:
                rows = pronunciations(source, region)
                if selected is not None:
                    rows = (row for row in rows if row[0] in selected)
                db.executemany("INSERT INTO reference_ipa VALUES(?,?,?,?)", rows)
            db.execute("INSERT OR REPLACE INTO metadata(key, value) VALUES('schema_version', '2')")
        for row in db.execute("SELECT region, count(DISTINCT word), count(*) FROM reference_ipa GROUP BY region"):
            print(f"{row[0]}: {row[1]:,} headwords, {row[2]:,} readings")
    finally:
        db.close()


if __name__ == "__main__":
    main()
