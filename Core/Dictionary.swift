import Foundation
import SQLite3

struct Sense: Decodable, Sendable {
    let gloss: String
    let cues: [String]
}
struct LexicalDetail: Decodable, Sendable {
    let ipa: [String: String]
    let etymology: String
    let parts: [String]
    let senses: [Sense]
}
struct DictionaryEntry: Sendable {
    let rowID: Int64
    let word: String
    let pos: String
    let edition: String
    let detail: LexicalDetail
    var sourceName: String { edition == "zh" ? "中文维基词典" : "English Wiktionary" }
    var sourceURL: URL {
        URL(string: "https://\(edition).wiktionary.org/wiki/")!.appendingPathComponent(word)
    }
}
struct RankedSense: Identifiable, Sendable {
    let id: Int
    let entry: DictionaryEntry
    let sense: Sense
    let score: Int
}
struct WordLookup: Sendable {
    let senses: [RankedSense]
    /// Word-level variants in the source dictionary's order, independent of any sense.
    let referenceIPA: [String: [String]]

    // Supplement a Chinese entry only when one unambiguous English entry of the
    // same part of speech exists, with its own source link displayed beside the fields.
    func englishSupplement(for entry: DictionaryEntry) -> DictionaryEntry? {
        guard entry.edition == "zh" else { return nil }
        let english = senses.filter { $0.entry.edition == "en" && $0.entry.pos == entry.pos && $0.entry.word == entry.word }
        guard Set(english.map { $0.entry.rowID }).count == 1 else { return nil }
        return english.first?.entry
    }

    func sourcedIPA(_ key: String, primary: DictionaryEntry?, extra: DictionaryEntry?) -> (value: String, entry: DictionaryEntry)? {
        let sources = [primary, extra].compactMap { $0 }
        // English entries can explicitly distinguish stress by part of speech (e.g. record).
        if let extra, let value = contrastingIPA(for: extra, key: key) { return (value, extra) }
        for entry in sources {
            if let value = entry.detail.ipa[key], !value.isEmpty { return (value, entry) }
        }
        return nil
    }

    private func contrastingIPA(for entry: DictionaryEntry, key: String) -> String? {
        guard let value = entry.detail.ipa[key], !value.isEmpty else { return nil }
        let differs = senses.contains { hit in
            let peer = hit.entry
            guard peer.edition == entry.edition, peer.word == entry.word, peer.pos != entry.pos,
                  let other = peer.detail.ipa[key], !other.isEmpty else { return false }
            return other != value
        }
        return differs ? value : nil
    }

    func speechHint(for entry: DictionaryEntry, region: String) -> String? {
        let source = englishSupplement(for: entry) ?? entry
        guard let value = contrastingIPA(for: source, key: region),
              value.first == "/", value.last == "/", value.count > 2 else { return nil }
        let phones = value.dropFirst().dropLast().replacingOccurrences(of: ".", with: "")
        // Optional segments and alternatives are useful to read, but aren't one spoken form.
        guard !phones.isEmpty, phones.unicodeScalars.allSatisfy({
            CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }) else { return nil }
        return phones
    }
}
enum LexiconError: LocalizedError {
    case unreadable
    var errorDescription: String? { "离线词典读取失败，请检查应用资源。" }
}
enum Lexicon {
    static func lookup(_ token: WordToken) throws -> [RankedSense] {
        try lookupWord(token).senses
    }
    static func lookupWord(_ token: WordToken) throws -> WordLookup {
        guard let url = Bundle.main.url(forResource: "Dictionary", withExtension: "sqlite") else { throw LexiconError.unreadable }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw LexiconError.unreadable }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT word,pos,edition,detail,rowid FROM entry WHERE word=? ORDER BY rowid", -1, &statement, nil) == SQLITE_OK else { throw LexiconError.unreadable }
        var entries: [DictionaryEntry] = []
        for key in [token.lemma, token.surface.lowercased()] where entries.isEmpty {
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                func string(_ index: Int32) -> String { String(cString: sqlite3_column_text(statement, index)) }
                let detail = try JSONDecoder().decode(LexicalDetail.self, from: Data(string(3).utf8))
                entries.append(.init(rowID: sqlite3_column_int64(statement, 4), word: string(0), pos: string(1), edition: string(2), detail: detail))
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { throw LexiconError.unreadable }
        }
        let headword = entries.first?.word ?? token.lemma.lowercased()
        let sql = "SELECT region,ipa FROM reference_ipa WHERE word=? ORDER BY region,variant"
        var pronunciationQuery: OpaquePointer?
        defer { sqlite3_finalize(pronunciationQuery) }
        if sqlite3_prepare_v2(database, sql, -1, &pronunciationQuery, nil) != SQLITE_OK {
            // Dictionaries built with the original importer only contain entry-level IPA.
            var legacyCheck: OpaquePointer?
            defer { sqlite3_finalize(legacyCheck) }
            guard sqlite3_prepare_v2(database, "SELECT value FROM metadata WHERE key='schema_version'", -1, &legacyCheck, nil) == SQLITE_OK,
                  sqlite3_step(legacyCheck) == SQLITE_ROW, sqlite3_column_int(legacyCheck, 0) == 1 else { throw LexiconError.unreadable }
            return WordLookup(senses: rank(entries, token: token), referenceIPA: [:])
        }
        guard sqlite3_bind_text(pronunciationQuery, 1, headword, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK
        else { throw LexiconError.unreadable }
        var referenceIPA: [String: [String]] = [:]
        var status = sqlite3_step(pronunciationQuery)
        while status == SQLITE_ROW {
            let region = String(cString: sqlite3_column_text(pronunciationQuery, 0))
            let ipa = String(cString: sqlite3_column_text(pronunciationQuery, 1))
            referenceIPA[region, default: []].append(ipa)
            status = sqlite3_step(pronunciationQuery)
        }
        guard status == SQLITE_DONE else { throw LexiconError.unreadable }
        return WordLookup(senses: rank(entries, token: token), referenceIPA: referenceIPA)
    }
    static func rank(_ entries: [DictionaryEntry], token: WordToken) -> [RankedSense] {
        let terms = Set(token.sentence.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 })
            .subtracting(TextAnalysis.stop).subtracting([token.surface.lowercased(), token.lemma])
        var senses: [RankedSense] = []
        for entry in entries {
            for (index, sense) in entry.detail.senses.enumerated() {
                let matches = terms.intersection(sense.cues).count
                let score = (entry.pos == token.pos ? 100 : 0) + min(5, matches) * 6
                    + (entry.edition == "zh" ? 10 : 0) + max(0, 3 - index)
                senses.append(.init(id: senses.count, entry: entry, sense: sense, score: score))
            }
        }
        return senses.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
    }
}

// Systems without downloaded NaturalLanguage tagger assets can still resolve explicitly
// attested inflections. Ambiguous forms retain their surface spelling.
final class FormIndex {
    private var database: OpaquePointer?
    private var statement: OpaquePointer?
    init?() {
        guard let url = Bundle.main.url(forResource: "Dictionary", withExtension: "sqlite"),
              sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        let sql = """
        SELECT lemma,pos FROM inflection WHERE form=?
        UNION ALL
        SELECT word,pos FROM entry WHERE word=? GROUP BY word,pos ORDER BY 1,2
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    }
    deinit { sqlite3_finalize(statement); sqlite3_close(database) }
    func resolve(_ surface: String, preferredPOS: String, contextualPOS: String) -> (String, String) {
        sqlite3_reset(statement)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for column in 1...2 { sqlite3_bind_text(statement, Int32(column), surface, -1, transient) }
        var candidates: [(String,String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            candidates.append((String(cString: sqlite3_column_text(statement, 0)), String(cString: sqlite3_column_text(statement, 1))))
        }
        if !preferredPOS.isEmpty { candidates = candidates.filter { $0.1 == preferredPOS } }
        let bases = Set(candidates.filter { $0.0 != surface }.map(\.0))
        let lemma = bases.count == 1 ? bases.first! : surface
        let classes = Set(candidates.filter { $0.0 == lemma }.map(\.1))
        return (lemma, classes.count == 1 ? classes.first! : (classes.contains(contextualPOS) ? contextualPOS : preferredPOS))
    }
}
