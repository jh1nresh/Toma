import SwiftUI

@main
struct TomaApp: App {
    @StateObject private var store: AppStore
    @StateObject private var intentHandoff = IntentHandoffStore.shared

    init() {
        let appStore: AppStore
        #if DEBUG
        let arguments = CommandLine.arguments
        if arguments.contains("-ui-testing") || arguments.contains("-ui-testing-reset") {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("TomaUITests", isDirectory: true)
                .appendingPathComponent("snapshot.json")
            if arguments.contains("-ui-testing-reset") {
                try? FileManager.default.removeItem(at: fileURL)
            }
            appStore = AppStore(snapshotStore: JSONSnapshotStore(fileURL: fileURL))
        } else {
            appStore = AppStore()
        }
        #else
        appStore = AppStore()
        #endif
        _store = StateObject(wrappedValue: appStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(intentHandoff)
        }
    }
}
