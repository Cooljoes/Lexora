"""Build the offline subset from two Wiktextract JSONL gzip files and a selection word list.

Usage: python3 Tools/build_dictionary.py en.jsonl.gz zh.jsonl.gz headwords.txt new.sqlite [--all-chinese]
With --all-chinese, keep all glossed English headwords from the Chinese edition
and use the list to select entries from the English edition.
Refuses to overwrite an existing output. Sources, licenses and hashes are in README.
"""
import argparse
import gzip
import json
import re
import sqlite3
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("en_file", type=Path)
parser.add_argument("zh_file", type=Path)
parser.add_argument("headword_file", type=Path)
parser.add_argument("destination", type=Path)
parser.add_argument("--all-chinese", action="store_true", help="Also import all glossed English spellings from the Chinese edition")
args = parser.parse_args()
destination = args.destination
if destination.exists():
    raise SystemExit("Choose a new database path")
chosen = set(args.headword_file.read_text(encoding="utf-8").split())
if not chosen:
    raise SystemExit("The headword file is empty")
db = sqlite3.connect(destination)
db.executescript("""
CREATE TABLE entry(word TEXT NOT NULL, pos TEXT NOT NULL, edition TEXT NOT NULL, detail TEXT NOT NULL);
CREATE TABLE inflection(form TEXT, lemma TEXT, pos TEXT, PRIMARY KEY(form,lemma,pos)) WITHOUT ROWID;
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
""")
is_word = re.compile("[a-z]+(?:['-][a-z]+)*").fullmatch
words_in = re.compile(r"[a-z]{3,}")
parts_templates = {"af", "affix", "pre", "prefix", "suf", "suffix", "compound", "com", "confix", "circumfix", "surface analysis", "surf"}
regional = {"uk": {"UK", "Received-Pronunciation", "British", "英國", "英国", "標準英音", "标准英音", "標準南英音"},
            "us": {"US", "General-American", "美國", "美国", "通用美式"}}
pos_tags = {"noun": "noun", "名詞": "noun", "名词": "noun", "verb": "verb", "動詞": "verb", "动词": "verb",
            "adjective": "adj", "形容詞": "adj", "形容词": "adj", "adverb": "adv", "副詞": "adv", "副词": "adv",
            "助詞": "particle", "限定詞": "det", "主要爲名詞": "noun", "主要爲動詞": "verb"}
excluded_labels = {"obsolete", "archaic", "dated", "nonstandard", "historical", "dialectal",
                   "過時", "过时", "古代", "舊式", "旧式", "近代", "非標準", "非标准", "部份方言"}
note_regions = {"General American": "General-American", "Received Pronunciation": "Received-Pronunciation",
                "UK": "UK", "US": "US", "Canada": "Canada", "Australia": "Australia", "New Zealand": "New-Zealand"}
sound_variants = {"rhotic", "non-rhotic", "strong form", "stressed form", "weak vowel merger", "weak vowel distinction",
                  "non-merged vowel", "merged vowel", "stressed initial syllable", "unstressed initial syllable"}
raw_regions = set.union(*regional.values()) | {
    "加拿大", "澳大利亞", "澳洲", "新西蘭", "紐西蘭", "北英格蘭", "蘇格蘭", "愛爾蘭", "威爾士", "通用南非", "通用澳式"
}
neutral_raw_tags = {"en", "強讀形式", "重讀形式", "標準"}
phonological_note = re.compile(
    r"(?:without (?:the )?)?(?:[\w/̯ː–-]+ (?:merger|raising|split|distinction|tensing)|"
    r"[\w/-]+-(?:flapping|dropping|coalescence|vocalization|vocalizing|tensing))"
)

def entry_pronunciations(item):
    candidates = {}
    for sound in item.get("sounds", []):
        if sound.get("topics") or sound.get("form", item["word"]) != item["word"]:
            continue
        ipa = sound.get("ipa", "").strip()
        pair = re.fullmatch(r"(/[^/]+/)\s+\[.+\]", ipa)
        if pair:
            ipa = pair.group(1)
        if len(ipa) < 3 or (ipa[0], ipa[-1]) not in {("/", "/"), ("[", "]")}:
            continue
        if ipa[1] in "-…" or ipa[-2] in "-…" or "..." in ipa:
            continue  # A source may abbreviate a variant to a prefix or suffix.
        tags = set(sound.get("tags", []))
        # Chinese raw labels sometimes contain both an accent and a meaning
        # (e.g. mobile as a phone or as a sculpture). Keep scoped labels only
        # when this importer can represent their meaning.
        raw_tags = {t.strip() for raw in sound.get("raw_tags", []) for t in re.split(r"[,，、;；]", raw) if t.strip()}
        if raw_tags.difference(raw_regions, pos_tags, neutral_raw_tags):
            continue
        tags.update(raw_tags - neutral_raw_tags)
        note = sound.get("note", "").strip()
        # Some English-edition records carry the actual dialect in the note.
        # Accept named dialects and phonetic variants, but reject notes tied to
        # a specific meaning, inflected form, historical period or phrase.
        notes = [part.strip() for part in re.split(r"[,;]", note) if part.strip()]
        if any(part not in note_regions and part not in pos_tags and part not in sound_variants
               and not phonological_note.fullmatch(part) for part in notes):
            continue
        tags.update(note_regions[part] for part in notes if part in note_regions)
        tags.update(part for part in notes if part in pos_tags)
        if tags & excluded_labels or {"Early", "Modern"} <= tags:
            continue
        classes = {pos_tags[tag] for tag in tags if tag in pos_tags}
        if classes and item.get("pos") not in classes:
            continue
        tags.difference_update(pos_tags)
        tags.discard("en")
        regions = [region for region, labels in regional.items() if tags & labels]
        if not tags:
            regions = ["general"]
        for region in regions:
            # Prefer an explicitly scoped part of speech and a complete phonemic transcription.
            # Keep source order for alternatives of equal priority.
            priority = (bool(classes), ipa.startswith("/"), not note)
            if region not in candidates or priority > candidates[region][0]:
                candidates[region] = (priority, ipa)
    return {region: v[1] for region, v in candidates.items()}

def entry_detail(item, edition):
    pronunciations = entry_pronunciations(item)
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

for edition, filename in [("zh", args.zh_file), ("en", args.en_file)]:
    form_headwords = chosen
    if edition == "en" and args.all_chinese:
        form_headwords = chosen.union(row[0] for row in db.execute("SELECT DISTINCT word FROM entry"))
    with gzip.open(filename) as stream:
        for raw in stream:
            obj = json.loads(raw)
            word = obj.get("word", "")
            if obj.get("lang_code") != "en" or not is_word(word): continue
            if edition == "en":
                if word not in form_headwords:
                    continue
                for inflected in obj.get("forms", []):
                    form = inflected.get("form", "")
                    tags = set(inflected.get("tags", []))
                    if form != word and is_word(form) and tags & {"plural", "past", "participle", "third-person", "comparative", "superlative"}:
                        db.execute("INSERT OR IGNORE INTO inflection VALUES(?,?,?)", (form, word, obj["pos"]))
            if word not in chosen and not (args.all_chinese and edition == "zh"):
                continue
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
