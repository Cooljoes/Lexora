import SwiftUI
import SwiftData

@main struct LexoraApp: App {
    @State private var storage: Result<ModelContainer, Error> = Result { try Library.container() }
    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                DeskShell().modelContainer(container).tint(Ink.green)
                    .environment(\.locale, Locale(identifier: "zh-Hans"))
            case .failure(let error):
                ContentUnavailableView {
                    Label("资料库暂时无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("重试") { storage = Result { try Library.container() } }
                }
            }
        }
    }
}
