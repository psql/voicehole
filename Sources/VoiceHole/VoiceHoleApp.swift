import SwiftUI

@main
struct VoiceHoleApp: App {
    @StateObject private var store: MemoStore
    @StateObject private var transcriber: TranscriptionService
    @StateObject private var recorder = RecorderService()

    init() {
        let store = MemoStore()
        _store = StateObject(wrappedValue: store)
        _transcriber = StateObject(wrappedValue: TranscriptionService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(transcriber)
                .environmentObject(recorder)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 480)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 660)
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Import Audio…") {
                    NotificationCenter.default.post(name: .voiceholeImport, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        #endif
    }
}
