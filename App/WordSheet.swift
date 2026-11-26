import SwiftUI
import SwiftData
import AVFAudio

struct WordSheet: View {
    let token: WordToken
    var preferredGloss: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedWord]
    @State private var senses: [RankedSense] = []
    @State private var selected: Int?
    @State private var loaded = false
    @State private var error: String?
    @State private var player = WordPronunciation()
    @State private var playback: Task<Void, Never>?
    @State private var preparingVoice: String?
    var chosen: RankedSense? { senses.first { $0.id == selected } ?? senses.first }
    var savedMatches: [SavedWord] { saved.filter { $0.lemma == token.lemma && $0.pos == token.pos } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(token.lemma).font(.custom("Baskerville-SemiBold", size: 41, relativeTo: .largeTitle)).foregroundStyle(Ink.text)
                        Text([TextAnalysis.partName(token.pos.isEmpty ? (chosen?.entry.pos ?? "") : token.pos), token.lemma == token.surface.lowercased() ? nil : "文中词形 " + token.surface].compactMap { $0 }.joined(separator: "  ·  "))
                            .font(.subheadline).foregroundStyle(Ink.muted)
                    }
                    if !token.sentence.isEmpty {
                        Text(token.sentence).font(.system(.body, design: .serif).italic()).lineSpacing(3)
                            .foregroundStyle(Ink.muted).padding(.leading, 12)
                            .overlay(alignment: .leading) { Rectangle().fill(Ink.green).frame(width: 2) }
                    }
                    if !loaded { ProgressView("查阅离线词典…") }
                    else if let choice = chosen {
                        VStack(alignment: .leading, spacing: 9) {
                            SectionLine(title: token.sentence.isEmpty ? "词典释义" : "语境候选释义", detail: TextAnalysis.partName(choice.entry.pos))
                            Text(choice.sense.gloss).font(.title3).lineSpacing(3).textSelection(.enabled)
                            Link(choice.entry.sourceName, destination: choice.entry.sourceURL).font(.caption)
                            if senses.count > 1 {
                                DisclosureGroup("查看其他释义") {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(senses) { hit in
                                            Button {
                                                selected = hit.id
                                            } label: {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(TextAnalysis.partName(hit.entry.pos) + " · " + hit.entry.sourceName).font(.caption2).foregroundStyle(Ink.muted)
                                                    Text(hit.sense.gloss).font(.subheadline).foregroundStyle(Ink.text)
                                                }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            Divider()
                                        }
                                    }
                                }.font(.subheadline)
                            }
                        }.padding(15).paperCard()
                        let primary = choice.entry
                        let extra = englishSupplement(for: primary)
                        let uk = primary.detail.ipa["uk"] == nil ? (extra ?? primary) : primary
                        let us = primary.detail.ipa["us"] == nil ? (extra ?? primary) : primary
                        let parts = primary.detail.parts.isEmpty ? (extra ?? primary) : primary
                        let etym = primary.detail.etymology.isEmpty ? (extra ?? primary) : primary
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLine(title: "音标与发音")
                            soundRow("英式", uk.detail.ipa["uk"], "en-GB")
                            soundRow("美式", us.detail.ipa["us"], "en-US")
                            if let unspecific = primary.detail.ipa["general"] {
                                Text("未分地区  " + unspecific).font(.subheadline).foregroundStyle(Ink.muted)
                            }
                            if uk.rowID == us.rowID {
                                Link(uk.sourceName + " · 地区 IPA", destination: uk.sourceURL).font(.caption)
                            } else {
                                Link(uk.sourceName + " · 英式 IPA", destination: uk.sourceURL).font(.caption)
                                Link(us.sourceName + " · 美式 IPA", destination: us.sourceURL).font(.caption)
                            }
                        }
                        Divider()
                        section("词根与词缀", parts.detail.parts.isEmpty ? "此来源未提供明确的构词拆分。" : parts.detail.parts.joined(separator: "\n"))
                        if !parts.detail.parts.isEmpty {
                            Link(parts.sourceName + " · 构词", destination: parts.sourceURL).font(.caption)
                        }
                        section("词源", etym.detail.etymology.isEmpty ? "此词条未收录词源说明。" : etym.detail.etymology)
                        Link(etym.sourceName + " · 词源", destination: etym.sourceURL).font(.caption)
                    } else if error == nil {
                        Label("离线词库未收录此词", systemImage: "book.closed").foregroundStyle(Ink.muted)
                        soundRow("英式", nil, "en-GB")
                        soundRow("美式", nil, "en-US")
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(22).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Ink.paper).navigationTitle("词条").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { toggle() } label: {
                        Label(savedMatches.isEmpty ? "收藏" : "取消收藏", systemImage: savedMatches.isEmpty ? "bookmark" : "bookmark.fill")
                    }.accessibilityIdentifier("toggleFavorite").disabled(!loaded)
                }
            }
        }
        .task(id: token) {
            loaded = false
            do {
                senses = try await Task.detached { try Lexicon.lookup(token) }.value
                if let preferredGloss { selected = senses.first { $0.sense.gloss == preferredGloss }?.id }
            }
            catch { self.error = error.localizedDescription }
            loaded = true
        }
        .onDisappear {
            playback?.cancel()
            Task { await player.stop() }
        }
    }
    // Supplement a Chinese entry only when one unambiguous English entry of the
    // same part of speech exists, with its own source link displayed beside the fields.
    private func englishSupplement(for entry: DictionaryEntry) -> DictionaryEntry? {
        guard entry.edition == "zh" else { return nil }
        let english = senses.filter { $0.entry.edition == "en" && $0.entry.pos == entry.pos }
        guard Set(english.map { $0.entry.rowID }).count == 1 else { return nil }
        return english.first?.entry
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).lineSpacing(4).foregroundStyle(Ink.muted).textSelection(.enabled)
        }
    }
    private func soundRow(_ label: String, _ ipa: String?, _ locale: String) -> some View {
        HStack {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Ink.green)
            Text(ipa ?? "来源未标注").font(.body).foregroundStyle(ipa == nil ? Ink.muted : Ink.text)
            Spacer()
            Button {
                playback?.cancel()
                let word = chosen?.entry.word ?? token.lemma
                preparingVoice = locale
                playback = Task {
                    let available = await player.play(word, locale: locale)
                    guard !Task.isCancelled else { return }
                    preparingVoice = nil
                    if !available { error = "此设备尚无该英语语音，可在系统设置中下载。" }
                }
            } label: {
                Group {
                    if preparingVoice == locale { ProgressView().controlSize(.small) }
                    else { Image(systemName: "speaker.wave.2") }
                }.frame(minWidth: 44, minHeight: 44)
            }
                .accessibilityLabel("播放" + label + "发音")
        }
    }
    private func toggle() {
        if savedMatches.isEmpty { context.insert(SavedWord(token: token, gloss: chosen?.sense.gloss ?? "")) }
        else { savedMatches.forEach { context.delete($0) } }
        do { try Library.commit(context) } catch { self.error = error.localizedDescription }
    }
}

// Voice lookup can synchronously wait for the system speech-assets service on a cold device.
// Keep both voice discovery and synthesis off the main actor and serialize playback.
private actor WordPronunciation {
    private var synthesizer: AVSpeechSynthesizer?
    func play(_ word: String, locale: String) -> Bool {
        guard !Task.isCancelled else { return false }
        guard let voice = AVSpeechSynthesisVoice(language: locale),
              voice.language.caseInsensitiveCompare(locale) == .orderedSame else { return false }
        guard !Task.isCancelled else { return false }
        let speech = synthesizer ?? AVSpeechSynthesizer()
        synthesizer = speech
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        speech.speak(utterance)
        return true
    }
    func stop() { synthesizer?.stopSpeaking(at: .immediate) }
}
