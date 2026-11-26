import SwiftUI
import SwiftData
import NaturalLanguage
import Translation

struct ReaderView: View {
    let item: Reading
    @State private var tokens: [WordToken] = []
    @State private var word: WordToken?
    @ScaledMetric(relativeTo: .title3) private var textSize = 23
    var focus: [WordToken] {
        var seen = Set<String>()
        return tokens.filter { $0.isFocus && seen.insert($0.lemma).inserted }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.origin, systemImage: item.text == Featured.text ? "leaf" : "text.alignleft")
                        .font(.caption.weight(.semibold)).foregroundStyle(Ink.green)
                    Text(item.title).font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(Ink.text)
                    HStack(spacing: 8) {
                        Text(item.created.formatted(date: .abbreviated, time: .omitted))
                        if !tokens.isEmpty { Text("·"); Text("\(tokens.count) 词") }
                    }.font(.caption).foregroundStyle(Ink.muted)
                }
                Divider()
                VStack(alignment: .leading, spacing: 13) {
                    SectionLine(title: "英文原文", detail: "轻点单词查阅")
                    Text(annotated)
                        .font(.custom("Baskerville", fixedSize: textSize)).lineSpacing(8)
                        .foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                        .environment(\.openURL, OpenURLAction { url in
                            guard url.scheme == "lexora-word", let index = Int(url.lastPathComponent),
                                  let match = tokens.first(where: { $0.id == index }) else { return .systemAction }
                            word = match
                            return .handled
                        })
                    if item.text == Featured.text {
                        Link("Charles Darwin · 1859 年初版，第 490 页", destination: Featured.source).font(.caption)
                    }
                }
                if !focus.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLine(title: "重点词汇", detail: "\(focus.count) 个")
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(focus) { token in
                                    Button(token.lemma) { word = token }.font(.subheadline.weight(.medium))
                                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                                        .accessibilityIdentifier("focus-" + token.lemma)
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                }
                TranslationBlock(item: item).id(item.id)
            }.padding(22).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Ink.paper).navigationTitle("精读").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: item.text) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享原文")
            }
        }
        .task(id: item.id) {
            let input = item.text
            let result = await Task.detached(priority: .userInitiated) { TextAnalysis.analyze(input) }.value
            if !Task.isCancelled { tokens = result }
        }
        .sheet(item: $word) { WordSheet(token: $0) }
    }
    private var annotated: AttributedString {
        // Walk the original string once so repeated words, newlines and emoji retain exact offsets.
        let original = item.text as NSString
        var result = AttributedString()
        var cursor = 0
        for token in tokens {
            guard token.location >= cursor, token.location + token.length <= original.length else { continue }
            result += AttributedString(original.substring(with: NSRange(location: cursor, length: token.location - cursor)))
            var part = AttributedString(token.surface)
            part.link = URL(string: "lexora-word://token/\(token.location)")
            part.foregroundColor = token.isFocus ? Ink.green : Ink.text
            if token.isFocus {
                part.backgroundColor = Ink.highlight
                part.underlineStyle = .single
            } else { part.underlineStyle = Text.LineStyle(pattern: .solid, color: .clear) }
            result += part
            cursor = token.location + token.length
        }
        result += AttributedString(original.substring(from: cursor))
        return result
    }
}

struct TranslationBlock: View {
    let item: Reading
    @Environment(\.modelContext) private var context
    @State private var state = "正在检查英语与简体中文语言包…"
    @State private var configuration: TranslationSession.Configuration?
    @State private var retry = 0
    @State private var canRetry = false
    let source = Locale.Language(identifier: "en")
    let target = Locale.Language(identifier: "zh-Hans")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("全文译文", systemImage: "translate").font(.headline).foregroundStyle(Ink.green)
            if !item.translated.isEmpty {
                Text(item.translated).lineSpacing(5).textSelection(.enabled)
            } else {
                Text(state).font(.subheadline).foregroundStyle(Ink.muted)
                if canRetry { Button("重新翻译") { retry += 1 }.buttonStyle(.bordered) }
            }
        }
        .padding(17).frame(maxWidth: .infinity, alignment: .leading).paperCard()
        .task(id: retry) { await begin() }
        .translationTask(configuration) { session in
            guard item.translated.isEmpty else { return }
            do {
                state = "正在准备 Apple 翻译…"
                try await session.prepareTranslation()
                try Task.checkCancellation()
                state = "正在翻译全文…"
                let translation = try await FullTextTranslator.translate(item.text, using: session)
                try Task.checkCancellation()
                item.translated = translation
                try Library.commit(context)
            } catch {
                if !Task.isCancelled {
                    state = "翻译未完成。\(error.localizedDescription)"
                    canRetry = true
                }
            }
        }
    }
    @MainActor private func begin() async {
        guard item.translated.isEmpty else { return }
        canRetry = false
        #if targetEnvironment(simulator)
        state = "Apple 翻译需要在支持的真机上运行。离线词典可在此使用。"
        #else
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled else { return }
        if status == .unsupported {
            state = "此设备当前不支持英语到简体中文的翻译。"
            canRetry = true
            return
        }
        state = status == .installed ? "正在翻译全文…" : "首次使用需要下载苹果语言包，请按系统提示继续。"
        if configuration == nil { configuration = .init(source: source, target: target) }
        else { configuration?.invalidate() }
        #endif
    }
}
