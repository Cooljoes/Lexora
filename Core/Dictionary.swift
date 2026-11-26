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
enum LexiconError: LocalizedError {
    case unreadable
    var errorDescription: String? { "离线词典读取失败，请检查应用资源。" }
}
enum Lexicon {
    static func lookup(_ token: WordToken) throws -> [RankedSense] {
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
        return rank(entries, token: token)
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
