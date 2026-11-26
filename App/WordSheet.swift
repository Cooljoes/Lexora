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
    @State private var choosingSense = false
    @State private var showingSentence = false
    @State private var loaded = false
    @State private var lookupError: String?
    @State private var speechError: String?
    @State private var saveError: String?
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
                        Text(token.lemma).font(.custom("Baskerville-SemiBold", size: 41, relativeTo: .largeTitle))
                            .fixedSize(horizontal: false, vertical: true).foregroundStyle(Ink.text)
                        Text([TextAnalysis.partName(token.pos.isEmpty ? (chosen?.entry.pos ?? "") : token.pos), token.lemma == token.surface.lowercased() ? nil : "文中词形 " + token.surface].compactMap { $0 }.joined(separator: "  ·  "))
                            .font(.subheadline).foregroundStyle(Ink.muted)
                    }
                    if !loaded { ProgressView("查阅离线词典…") }
                    else if let choice = chosen {
                        VStack(alignment: .leading, spacing: 9) {
                            SectionLine(title: token.sentence.isEmpty ? "词典释义" : "语境候选释义", detail: TextAnalysis.partName(choice.entry.pos))
                            Text(choice.sense.gloss).font(.title3).lineSpacing(3).textSelection(.enabled)
                            Link(choice.entry.sourceName, destination: choice.entry.sourceURL).font(.caption)
                            if senses.count > 1 {
                                Button { choosingSense = true } label: {
                                    HStack {
                                        Text("查看其他释义")
                                        Spacer()
                                        Image(systemName: "chevron.forward").font(.caption).accessibilityHidden(true)
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.font(.subheadline).accessibilityIdentifier("sensePicker")
                            }
                        }.padding(15).paperCard()
                        let primary = choice.entry
                        let extra = englishSupplement(for: primary)
                        let parts = primary.detail.parts.isEmpty ? (extra ?? primary) : primary
                        let etym = primary.detail.etymology.isEmpty ? (extra ?? primary) : primary
                        pronunciation(primary: primary, extra: extra)
                        sentenceSection
                        Divider()
                        section("词根与词缀", parts.detail.parts.isEmpty ? "此来源未提供明确的构词拆分。" : parts.detail.parts.joined(separator: "\n"))
                        if !parts.detail.parts.isEmpty {
                            Link(parts.sourceName + " · 构词", destination: parts.sourceURL).font(.caption)
                        }
                        section("词源", etym.detail.etymology.isEmpty ? "此词条未收录词源说明。" : etym.detail.etymology)
                        if !etym.detail.etymology.isEmpty {
                            Link(etym.sourceName + " · 词源", destination: etym.sourceURL).font(.caption)
                        }
                    } else {
                        if let lookupError {
                            Text(lookupError).font(.footnote).foregroundStyle(.red)
                        } else {
                            Label("离线词库未收录此词", systemImage: "book.closed").foregroundStyle(Ink.muted)
                        }
                        pronunciation(primary: nil, extra: nil)
                        sentenceSection
                    }
                    if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                }.padding(22).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Ink.paper).navigationTitle("词条").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $choosingSense) {
                let currentID = chosen?.id
                List(senses) { hit in
                    Button {
                        selected = hit.id
                        choosingSense = false
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TextAnalysis.partName(hit.entry.pos) + " · " + hit.entry.sourceName)
                                    .font(.caption).foregroundStyle(Ink.muted)
                                Text(hit.sense.gloss).font(.body).foregroundStyle(Ink.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if currentID == hit.id {
                                Image(systemName: "checkmark").foregroundStyle(Ink.green).accessibilityHidden(true)
                            }
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(currentID == hit.id ? .isSelected : [])
                    .accessibilityIdentifier("sense-\(hit.id)")
                    .listRowBackground(Ink.card)
                }
                .scrollContentBackground(.hidden).background(Ink.paper)
                .navigationTitle("选择释义").navigationBarTitleDisplayMode(.inline)
            }
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
            senses = []
            selected = nil
            showingSentence = false
            lookupError = nil
            speechError = nil
            saveError = nil
            do {
                let matches = try await Task.detached { try Lexicon.lookup(token) }.value
                guard !Task.isCancelled else { return }
                senses = matches
                if let preferredGloss { selected = senses.first { $0.sense.gloss == preferredGloss }?.id }
            } catch {
                guard !Task.isCancelled else { return }
                lookupError = error.localizedDescription
            }
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
        let english = senses.filter { $0.entry.edition == "en" && $0.entry.pos == entry.pos && $0.entry.word == entry.word }
        guard Set(english.map { $0.entry.rowID }).count == 1 else { return nil }
        return english.first?.entry
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).lineSpacing(4).foregroundStyle(Ink.muted).textSelection(.enabled)
        }
    }
    @ViewBuilder private var sentenceSection: some View {
        if !token.sentence.isEmpty {
            DisclosureGroup(isExpanded: $showingSentence) {
                Text(token.sentence)
                    .font(.system(.body, design: .serif).italic()).lineSpacing(3)
                    .foregroundStyle(Ink.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } label: {
                Text("文中原句").font(.headline).foregroundStyle(Ink.text)
            }
            .padding(15).paperCard()
        }
    }
    private func pronunciation(primary: DictionaryEntry?, extra: DictionaryEntry?) -> some View {
        let sources = [primary, extra].compactMap { $0 }
        func ipa(_ key: String) -> (value: String, entry: DictionaryEntry)? {
            for entry in sources {
                if let value = entry.detail.ipa[key], !value.isEmpty { return (value, entry) }
            }
            return nil
        }
        let uk = ipa("uk"), us = ipa("us"), general = ipa("general")
        return VStack(alignment: .leading, spacing: 8) {
            SectionLine(title: "音标与发音")
            soundRow("英式", uk?.value, "en-GB")
            soundRow("美式", us?.value, "en-US")
            if let uk, let us, uk.entry.rowID == us.entry.rowID {
                Link(uk.entry.sourceName + " · 地区 IPA", destination: uk.entry.sourceURL).font(.caption)
            } else {
                if let uk { Link(uk.entry.sourceName + " · 英式 IPA", destination: uk.entry.sourceURL).font(.caption) }
                if let us { Link(us.entry.sourceName + " · 美式 IPA", destination: us.entry.sourceURL).font(.caption) }
            }
            if let general {
                Text("未分地区  " + general.value).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("generalIPA")
                Link(general.entry.sourceName + " · 未分地区 IPA", destination: general.entry.sourceURL)
                    .font(.caption).accessibilityIdentifier("generalIPASource")
            }
            if let speechError { Text(speechError).font(.footnote).foregroundStyle(.red) }
        }
    }
    private func soundRow(_ label: String, _ ipa: String?, _ locale: String) -> some View {
        let region = Text(label).font(.caption.weight(.medium)).foregroundStyle(Ink.green)
        let phonetics = Text(ipa ?? "来源未标注").font(.body).foregroundStyle(ipa == nil ? Ink.muted : Ink.text)
        return HStack {
            ViewThatFits(in: .horizontal) {
                HStack { region; phonetics }.fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    region
                    phonetics.fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button {
                playback?.cancel()
                speechError = nil
                let word = chosen?.entry.word ?? token.lemma
                preparingVoice = locale
                playback = Task {
                    let available = await player.play(word, locale: locale)
                    guard !Task.isCancelled else { return }
                    preparingVoice = nil
                    if !available { speechError = "此设备尚无\(label)英语语音，可在系统设置中下载。" }
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
        saveError = nil
        if savedMatches.isEmpty { context.insert(SavedWord(token: token, gloss: chosen?.sense.gloss ?? "")) }
        else { savedMatches.forEach { context.delete($0) } }
        do { try Library.commit(context) } catch { saveError = error.localizedDescription }
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
