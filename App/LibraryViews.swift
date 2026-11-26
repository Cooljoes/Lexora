import SwiftUI
import SwiftData
import CloudKit

struct HistoryView: View {
    @Query(sort: \Reading.lastRead, order: .reverse) private var records: [Reading]
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var error: String?
    let open: (Reading) -> Void
    var body: some View {
        let matches = records.filter {
            search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search)
        }
        List {
            ForEach(matches) { item in
                Button { open(item) } label: { PassageRow(item: item) }.buttonStyle(.plain)
                    .listRowBackground(Ink.card)
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            context.delete(item)
                            do { try Library.commit(context) } catch { self.error = error.localizedDescription }
                        }
                    }
            }
        }.scrollContentBackground(.hidden).background(Ink.paper)
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("还没有阅读记录", systemImage: "clock", description: Text("从书桌打开一段英文，即可在这里继续阅读。"))
            } else if matches.isEmpty {
                ContentUnavailableView("未找到相关记录", systemImage: "magnifyingglass", description: Text("试试其他标题或原文关键词。"))
            }
        }
        .navigationTitle("阅读历史")
        .searchable(text: $search, prompt: "搜索标题或原文")
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") {} } message: { Text(error ?? "") }
    }
}

struct WordbookView: View {
    @Query(sort: \SavedWord.created, order: .reverse) private var records: [SavedWord]
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var selected: WordToken?
    @State private var preferredGloss: String?
    private var distinct: [SavedWord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.lemma.lowercased() + "|" + $0.pos).inserted }
    }
    var matches: [SavedWord] { distinct.filter { search.isEmpty || $0.lemma.localizedCaseInsensitiveContains(search) || $0.gloss.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section {
                let searchLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                searchLayout {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Ink.green).accessibilityHidden(true)
                        TextField(typeSize.isAccessibilitySize ? "输入英文" : "输入英文，查询离线词典", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("输入英文，查询离线词典").accessibilityIdentifier("wordSearch")
                            .submitLabel(.search).onSubmit { lookup() }
                    }
                    if !search.isEmpty {
                        Button("查词", action: lookup).fixedSize().buttonStyle(.borderless).accessibilityIdentifier("dictionaryLookup")
                    }
                }
            }.listRowBackground(Ink.card)
            Section("已收藏 · \(distinct.count)") {
                if matches.isEmpty {
                    Text(search.isEmpty ? "阅读时轻点单词，再点书签即可收藏。" : "没有匹配的收藏，可用上方「查词」查询。")
                        .font(.subheadline).foregroundStyle(Ink.muted).padding(.vertical, 6).listRowBackground(Ink.card)
                }
                ForEach(matches) { saved in
                    Button { preferredGloss = saved.gloss; selected = saved.token } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(saved.lemma).font(.custom("Baskerville-SemiBold", size: 24)).foregroundStyle(Ink.text)
                            if !saved.gloss.isEmpty {
                                Text(saved.gloss).font(.subheadline).lineLimit(typeSize.isAccessibilitySize ? nil : 2).foregroundStyle(Ink.muted)
                            }
                        }
                    }.listRowBackground(Ink.card)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Ink.paper).navigationTitle("生词本")
        .sheet(item: $selected) { WordSheet(token: $0, preferredGloss: preferredGloss) }
    }
    private func lookup() {
        let word = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !word.isEmpty { preferredGloss = nil; selected = .standalone(word) }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account = "正在检查 iCloud 账户…"
    @State private var license = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Brand()
                    Text("英语精读 · 版本 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                        .font(.subheadline).foregroundStyle(Ink.muted)
                }
                Section("离线词典") {
                    Text("内置 30,798 个英文词头。英、中维基词典贡献者提供释义、音标和词源，Kaikki.org 使用 Wiktextract 提取。词条保留原文及来源链接。")
                    Link("Kaikki.org 词典数据", destination: URL(string: "https://kaikki.org/dictionary/rawdata.html")!)
                    Text("Lexora 对数据作了筛选、整理与索引。地区音标只采用明确标注的记录；词根词缀仅展示来源已有的分析。")
                    Button("查看 CC BY-SA 4.0 许可") { license = true }
                }
                Section("精读与翻译") {
                    Text("NaturalLanguage 分析词形和词性。系统缺少语言资源时，使用词典收录的词形。重点词按实词、长度和数量筛选。候选释义结合词性及原句与词典释义、例句的用词匹配排序。")
                    Text("全文翻译由设备上的 Apple 翻译完成。首次使用可能需要下载英语或简体中文语言包。音频使用设备已安装的系统语音。")
                }
                Section("资料库与隐私") {
                    if Library.cloudIdentifier != nil {
                        Label(account, systemImage: "icloud")
                        Text("阅读原文、译文、生词和例句通过你自己的 iCloud 私有数据库同步。")
                    } else {
                        Label("本机资料库", systemImage: "internaldrive")
                        Text("阅读原文、译文、生词和例句保存在当前设备上。")
                    }
                    Text("剪贴板仅在你点按粘贴时读取。应用不含广告、统计 SDK 或自建服务器。")
                }
                Section("经典选读") {
                    Link("达尔文《物种起源》1859 年初版，第 490 页", destination: Featured.source)
                    Text("封面植物图为专为 Lexora 生成的装饰插图。").font(.footnote)
                }
            }.navigationTitle("关于 Lexora").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $license) {
                NavigationStack {
                    ScrollView {
                        Text(licenseText).font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle("CC BY-SA 4.0").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { license = false } } }
                }
            }
        }.task {
            guard let name = Library.cloudIdentifier else { return }
            do {
                switch try await CKContainer(identifier: name).accountStatus() {
                case .available: account = "iCloud 账户可用"
                case .noAccount: account = "尚未登录 iCloud"
                case .restricted: account = "iCloud 访问受限"
                default: account = "iCloud 账户状态暂时不可用"
                }
            } catch { account = "暂时无法检查 iCloud 账户" }
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "CC-BY-SA-4.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "https://creativecommons.org/licenses/by-sa/4.0/" }
        return text
    }
}
