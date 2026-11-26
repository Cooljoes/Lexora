import SwiftUI
import SwiftData

enum SectionID: String, CaseIterable, Identifiable {
    case desk = "书桌", words = "生词本", history = "历史"
    var id: Self { self }
    var icon: String {
        switch self { case .desk: "book.pages"; case .words: "bookmark"; case .history: "clock.arrow.circlepath" }
    }
}

struct DeskShell: View {
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.scenePhase) private var scene
    @Environment(\.modelContext) private var context
    @State private var section: SectionID = .desk
    @State private var deskPath: [Reading] = []
    @State private var historyPath: [Reading] = []
    @State private var composer = false
    @State private var about = false
    @State private var failure: String?
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if width == .regular {
                NavigationSplitView(columnVisibility: $columns) {
                    List(SectionID.allCases) { item in
                        Button { section = item } label: {
                            Label(item.rawValue, systemImage: item.icon).frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityAddTraits(section == item ? .isSelected : [])
                            .listRowBackground(section == item ? Ink.pale : Color.clear)
                    }
                    .navigationTitle("Lexora")
                    .safeAreaInset(edge: .bottom) {
                        Button { about = true } label: { Label("关于与数据来源", systemImage: "info.circle") }
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                    }
                } detail: { page(section) }
                .navigationSplitViewStyle(.balanced)
            } else {
                TabView(selection: $section) {
                    ForEach(SectionID.allCases) { item in
                        Tab(item.rawValue, systemImage: item.icon, value: item) { page(item) }
                    }
                }
            }
        }
        .sheet(isPresented: $composer) {
            Composer { raw in try open(raw, origin: "手动输入") }
        }
        .sheet(isPresented: $about) { AboutView() }
        .alert("操作未完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好") { failure = nil }
        } message: { Text(failure ?? "") }
        .onChange(of: scene, initial: true) { _, current in
            guard current == .active else { return }
            do { try Library.importInbox(ShareInbox.live(), into: context) }
            catch { failure = error.localizedDescription }
        }
    }
    @ViewBuilder private func page(_ sectionID: SectionID) -> some View {
        switch sectionID {
        case .desk:
            NavigationStack(path: $deskPath) {
                HomeView(
                    onSample: { run { try open(Featured.text, origin: "经典选读") } },
                    onPaste: { run { try open(UIPasteboard.general.string ?? "", origin: "剪贴板") } },
                    onCompose: { composer = true }, onSelect: { resume($0, history: false) },
                    onHistory: {
                        historyPath.removeAll()
                        section = .history
                    }, onAbout: { about = true }
                ).navigationDestination(for: Reading.self) { ReaderView(item: $0) }
            }
        case .words: NavigationStack { WordbookView() }
        case .history:
            NavigationStack(path: $historyPath) {
                HistoryView { resume($0, history: true) }
                    .navigationDestination(for: Reading.self) { ReaderView(item: $0) }
            }
        }
    }
    private func run(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }
    private func open(_ input: String, origin: String) throws {
        let item = try Library.store(input, origin: origin, in: context)
        section = .desk
        deskPath = [item]
    }
    private func resume(_ item: Reading, history: Bool) {
        run {
            item.lastRead = .now
            try Library.commit(context)
            if history { historyPath = [item] } else { deskPath = [item] }
        }
    }
}

struct Composer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var error: String?
    let submit: (String) throws -> Void
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("英文原文").font(.headline)
                    Spacer()
                    PasteButton(payloadType: String.self) { values in input = values.joined(separator: "\n\n") }
                        .labelStyle(.iconOnly).accessibilityLabel("粘贴原文")
                }
                TextEditor(text: $input)
                    .font(.system(.title3, design: .serif)).scrollContentBackground(.hidden)
                    .accessibilityLabel("英文输入框").accessibilityIdentifier("sourceInput")
                    .padding(10).paperCard()
                if let error {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(error).foregroundStyle(.red).fixedSize()
                            Spacer(minLength: 8)
                            characterCount.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error).foregroundStyle(.red)
                            characterCount.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }.font(.caption)
                } else {
                    characterCount.font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding().background(Ink.paper).navigationTitle("输入原文").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始精读") {
                        do { try submit(input); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    private var characterCount: some View {
        Text("\(input.count) / 12,000").foregroundStyle(Ink.muted).monospacedDigit()
    }
}
