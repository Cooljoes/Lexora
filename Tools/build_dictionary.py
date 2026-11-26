"""Build the offline subset from two Wiktextract JSONL gzip files and a selection word list.

Usage: python3 Tools/build_dictionary.py en.jsonl.gz zh.jsonl.gz common.txt new.sqlite
Refuses to overwrite an existing output. Sources, licenses and hashes are in README.
"""
import gzip
import json
import re
import sqlite3
import sys
from pathlib import Path

en_file, zh_file, common_file, destination = map(Path, sys.argv[1:])
if destination.exists():
    raise SystemExit("Choose a new database path")
chosen = set(common_file.read_text().split()) | set(
    "grand grandeur breathe originally whilst planet cycle fixed law gravity beginning endless "
    "beautiful wonderful evolve several power life form resilience resilient resiliently banking "
    "curiosity curious unravel ephemeral serendipity microscope biodiversity photosynthesis "
    "observe observation remarkable unfamiliar leaf fern forest foliage ecology botanical "
    "read reading reader river bank deposit water shore lend loan current language".split()
)
db = sqlite3.connect(destination)
db.executescript("""
CREATE TABLE entry(word TEXT NOT NULL, pos TEXT NOT NULL, edition TEXT NOT NULL, detail TEXT NOT NULL);
CREATE TABLE inflection(form TEXT, lemma TEXT, pos TEXT, PRIMARY KEY(form,lemma,pos)) WITHOUT ROWID;
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
""")
is_word = re.compile("[a-z]+(?:['-][a-z]+)*").fullmatch
words_in = re.compile(r"[a-z]{3,}")
parts_templates = {"af", "affix", "pre", "prefix", "suf", "suffix", "compound", "com", "confix", "circumfix", "surface analysis", "surf"}
regional = {"uk": {"UK", "Received-Pronunciation", "British", "英國", "英国", "標準英音"},
            "us": {"US", "General-American", "美國", "美国", "通用美式"}}

def entry_detail(item, edition):
    pronunciations = {}
    for sound in item.get("sounds", []):
        ipa = sound.get("ipa")
        tags = set(sound.get("tags", [])) | set(sound.get("raw_tags", []))
        if not ipa or tags & {"obsolete", "archaic", "dated", "nonstandard"}:
            continue
        for region, labels in regional.items():
            if tags & labels:
                pronunciations.setdefault(region, ipa)
        if not tags:
            pronunciations.setdefault("general", ipa)
    etym = item.get("etymology_text") or "\n".join(item.get("etymology_texts", []))
    # Extraction trees can precede the human-written paragraph. Exclude tree markup.
    if etym.startswith("Etymology tree"):
        match = re.search(r"^(?:From |Borrowed |Inherited |Derived |Probably |Perhaps |Possibly |Unknown origin|Uncertain origin|First attested |Equivalent to ).+", etym, re.M)
        etym = match.group(0) if match else ""
    etym = "\n".join(line for line in etym.splitlines() if not any(x in line for x in ('{', '[[', '▲', '▼', 'Etymology tree')))
    formation = []
    for template in item.get("etymology_templates", []):
        if template.get("name") in parts_templates and template.get("args", {}).get("1") == "en":
            expansion = template.get("expansion", "").strip()
            if expansion and len(expansion) <= 250 and expansion not in formation:
                formation.append(expansion)
    if not formation:
        # The field sometimes contains a plain-text decomposition instead of a template.
        direct = re.fullmatch(r"(?:From |Equivalent to )?([A-Za-z-]+(?: \+ [A-Za-z-]+)+)\.?", etym.strip())
        if direct:
            formation.append(direct.group(1))
    senses = []
    for sense in item.get("senses", []):
        if sense.get("tags") and "no-gloss" in sense["tags"]:
            continue
        gloss = " · ".join(sense.get("glosses", []))
        if not gloss: continue
        # Cues are an unordered vocabulary from the source gloss and usage examples.
        # No copyrighted illustrative quotations are reproduced in the database.
        cue_text = " ".join([gloss] + [e.get("text", "") for e in sense.get("examples", [])[:3]])
        cues = list(dict.fromkeys(words_in.findall(cue_text.lower())))[:85]
        senses.append({"gloss": gloss, "cues": cues})
        if len(senses) == 20: break
    if not senses: return
    return dict(ipa=pronunciations, etymology=etym.strip()[:2500], parts=formation[:4], senses=senses)

for edition, filename in [("zh", zh_file), ("en", en_file)]:
    with gzip.open(filename) as stream:
        for raw in stream:
            obj = json.loads(raw)
            word = obj.get("word", "")
            if obj.get("lang_code") != "en" or not is_word(word): continue
            if word not in chosen:
                if edition == "zh" and len(chosen) < 32000:
                    chosen.add(word)
                else: continue
            if edition == "en":
                for inflected in obj.get("forms", []):
                    form = inflected.get("form", "")
                    tags = set(inflected.get("tags", []))
                    if form != word and is_word(form) and tags & {"plural", "past", "participle", "third-person", "comparative", "superlative"}:
                        db.execute("INSERT OR IGNORE INTO inflection VALUES(?,?,?)", (form, word, obj["pos"]))
            detail = entry_detail(obj, edition)
            if detail:
                db.execute("INSERT INTO entry VALUES(?,?,?,?)", (word, obj["pos"], edition, json.dumps(detail, ensure_ascii=False, separators=(",", ":"))))
    db.commit()
db.execute("CREATE INDEX word_index ON entry(word)")
# Some source entries describe an inflection without carrying an importable gloss.
db.execute("DELETE FROM inflection WHERE NOT EXISTS (SELECT 1 FROM entry WHERE entry.word=inflection.lemma AND entry.pos=inflection.pos)")
count = db.execute("SELECT count(distinct word) FROM entry").fetchone()[0]
db.executemany("INSERT INTO metadata VALUES(?,?)", [("headwords", str(count)), ("schema_version", "1")])
db.commit()
assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
print(f"{count} headwords, {db.execute('SELECT count(*) FROM entry').fetchone()[0]} entries")
db.close()
