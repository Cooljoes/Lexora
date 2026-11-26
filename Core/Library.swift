import Foundation
import SwiftData

@Model final class Reading {
    var id: UUID = UUID()
    var text: String = ""
    var title: String = ""
    var origin: String = ""
    var translated: String = ""
    var created: Date = Date()
    var lastRead: Date = Date()
    init(_ text: String, title: String, origin: String, id: UUID = UUID(), date: Date = .now) {
        self.id = id
        self.text = text
        self.title = title
        self.origin = origin
        self.created = date
        self.lastRead = date
    }
}

@Model final class SavedWord {
    var lemma: String = ""
    var surface: String = ""
    var pos: String = ""
    var sentence: String = ""
    var gloss: String = ""
    var created: Date = Date()
    init(token: WordToken, gloss: String) {
        lemma = token.lemma
        surface = token.surface
        pos = token.pos
        sentence = token.sentence
        self.gloss = gloss
    }
    var token: WordToken {
        .init(surface: surface, lemma: lemma, pos: pos, location: 0, length: surface.utf16.count, sentence: sentence)
    }
}

enum Library {
    static var schema: Schema { Schema([Reading.self, SavedWord.self]) }
    static func container() throws -> ModelContainer {
        let cloud: ModelConfiguration.CloudKitDatabase
        #if targetEnvironment(simulator)
        cloud = .none
        #else
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "LexoraCloudContainer") as? String else {
            throw CocoaError(.coderValueNotFound)
        }
        cloud = .private(identifier)
        #endif
        let spec = schema
        let config = ModelConfiguration("ReadingLibrary", schema: spec, groupContainer: .none, cloudKitDatabase: cloud)
        return try ModelContainer(for: spec, configurations: [config])
    }
    @MainActor static func store(_ raw: String, origin: String, in context: ModelContext) throws -> Reading {
        let text = try PassageInput.clean(raw)
        var fetch = FetchDescriptor<Reading>(predicate: #Predicate { $0.text == text }, sortBy: [SortDescriptor(\.lastRead, order: .reverse)])
        fetch.fetchLimit = 1
        let item: Reading
        if let existing = try context.fetch(fetch).first {
            item = existing
            item.lastRead = .now
        } else {
            item = Reading(text, title: title(for: text), origin: origin)
            context.insert(item)
        }
        try commit(context)
        return item
    }
    static func title(for text: String) -> String {
        if text == Featured.text { return Featured.title }
        let snippet = text.split(whereSeparator: { $0.isWhitespace }).prefix(9).joined(separator: " ")
        return snippet.count < text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").count ? snippet + "…" : snippet
    }
    @MainActor static func importInbox(_ inbox: ShareInbox, into context: ModelContext) throws {
        var firstError: Error?
        for file in try inbox.files() {
            do {
                let share = try JSONDecoder().decode(SharedPassage.self, from: Data(contentsOf: file))
                let id = share.id
                var query = FetchDescriptor<Reading>(predicate: #Predicate { $0.id == id })
                query.fetchLimit = 1
                if try context.fetch(query).isEmpty {
                    let text = try PassageInput.clean(share.text)
                    context.insert(Reading(text, title: title(for: text), origin: "系统分享", id: id, date: share.date))
                    try commit(context)
                }
                try FileManager.default.removeItem(at: file)
            } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }
    @MainActor static func commit(_ context: ModelContext) throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
