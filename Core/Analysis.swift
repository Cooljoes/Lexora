import Foundation
import NaturalLanguage

struct WordToken: Identifiable, Hashable, Sendable {
    let surface: String
    let lemma: String
    let pos: String
    let location: Int
    let length: Int
    let sentence: String
    var id: Int { location }
    var dictionaryFallback = false
    var isFocus = false
    static func standalone(_ word: String, pos: String = "", sentence: String = "") -> Self {
        let spelling = word.lowercased()
        let form = pos.isEmpty && sentence.isEmpty ? FormIndex()?.searchForm(for: spelling) : nil
        return Self(surface: word, lemma: form?.lemma ?? spelling, pos: form?.pos ?? pos,
                    location: 0, length: word.utf16.count, sentence: sentence)
    }
}

enum TextAnalysis {
    static let stop = Set("the and this that these those they them their there here where with from will would could should have has had been being were was are is be can could might must may one two not very also more most into over when which while about what for you your she him her his who how then than only but all some said say get did does doing thing things make made much such".split(separator: " ").map(String.init))
    static func analyze(_ text: String) -> [WordToken] {
        let words = NLTokenizer(unit: .word)
        words.string = text
        words.setLanguage(.english)
        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = text
        sentences.setLanguage(.english)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        let whole = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: whole)
        let posMap: [NLTag: String] = [.noun:"noun", .verb:"verb", .adjective:"adj", .adverb:"adv", .pronoun:"pron", .preposition:"prep", .determiner:"det", .conjunction:"conj", .number:"num", .interjection:"intj"]
        var result: [WordToken] = []
        let index = FormIndex()
        var cachedForms: [String: (String, String)] = [:]
        words.enumerateTokens(in: whole) { range, _ in
            let surface = String(text[range])
            guard surface.range(of: "[A-Za-z]", options: .regularExpression) != nil else { return true }
            let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
            let (base, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            let ns = NSRange(range, in: text)
            let sentence = String(text[sentences.tokenRange(at: range.lowerBound)]).trimmingCharacters(in: .whitespacesAndNewlines)
            let systemPOS = tag.flatMap { posMap[$0] } ?? ""
            let key = surface.lowercased()
            var lemma = base?.rawValue.lowercased() ?? key
            var pos = systemPOS
            let needsFallback = base == nil || pos.isEmpty
            if needsFallback {
                let previous = result.last?.surface.lowercased() ?? ""
                let contextHint = ["a", "an", "the", "these", "those"].contains(previous) ? "noun" : (previous == "to" ? "verb" : "")
                let cacheKey = key + "|" + pos + "|" + contextHint
                let resolved = cachedForms[cacheKey] ?? index?.resolve(key, preferredPOS: pos, contextualPOS: contextHint) ?? (key, pos)
                cachedForms[cacheKey] = resolved
                if base == nil { lemma = resolved.0 }
                if pos.isEmpty { pos = resolved.1 }
            }
            result.append(WordToken(surface: surface, lemma: lemma,
                                    pos: pos, location: ns.location,
                                    length: ns.length, sentence: sentence, dictionaryFallback: needsFallback))
            return true
        }
        // Select at most six distinct content words. Keep all instances tappable.
        let candidates = result.filter { ["noun","verb","adj","adv"].contains($0.pos) && $0.lemma.count >= 4 && !stop.contains($0.lemma) }
        let sorted = candidates.sorted {
            let a = $0.lemma.count + ($0.pos == "noun" ? 2 : 0)
            let b = $1.lemma.count + ($1.pos == "noun" ? 2 : 0)
            return a == b ? $0.location < $1.location : a > b
        }
        var focus = Set<String>()
        for token in sorted where focus.count < min(6, max(1, result.count / 6)) { focus.insert(token.lemma) }
        for index in result.indices { result[index].isFocus = focus.contains(result[index].lemma) }
        return result
    }
    static func partName(_ pos: String) -> String {
        ["noun":"名词", "verb":"动词", "adj":"形容词", "adv":"副词", "pron":"代词", "prep":"介词", "det":"限定词", "conj":"连词", "num":"数词", "intj":"感叹词", "name":"专名", "article":"冠词"][pos] ?? (pos.isEmpty ? "未识别词性" : pos)
    }
}

enum Featured {
    static let title = "物种起源"
    static let text = "There is grandeur in this view of life, with its several powers, having been originally breathed into a few forms or into one; and that, whilst this planet has gone cycling on according to the fixed law of gravity, from so simple a beginning endless forms most beautiful and most wonderful have been, and are being, evolved."
    static let source = URL(string: "https://darwin-online.org.uk/Variorum/1859/1859-490-dns.html")!
}
