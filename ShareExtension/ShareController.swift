import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let content = SharePanel(context: extensionContext)
        let host = UIHostingController(rootView: content)
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
    }
}

private struct SharePanel: View {
    let context: NSExtensionContext?
    @State private var text = ""
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            Form {
                Section("英文原文") {
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("分享原文").accessibilityIdentifier("sharedTextInput")
                }
                Text("存入后，打开 Lexora 即可在阅读历史中精读。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("存入 Lexora")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { context?.cancelRequest(withError: CocoaError(.userCancelled)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存入") {
                        do {
                            try ShareInbox.live().enqueue(text)
                            context?.completeRequest(returningItems: nil)
                        } catch { self.error = error.localizedDescription }
                    }.disabled(loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                defer { loading = false }
                var pieces: [String] = []
                for item in context?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
                    var itemPieces: [String] = []
                    for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        do {
                            let data = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                            if let string = data as? String { itemPieces.append(string) }
                            else if let bytes = data as? Data, let string = String(data: bytes, encoding: .utf8) { itemPieces.append(string) }
                        } catch { self.error = error.localizedDescription }
                    }
                    if itemPieces.isEmpty, let content = item.attributedContentText { itemPieces.append(content.string) }
                    pieces += itemPieces
                }
                text = pieces.joined(separator: "\n\n")
                if text.isEmpty { error = "没有读取到英文，可以在上方输入或粘贴。" }
            }
        }
    }
}
