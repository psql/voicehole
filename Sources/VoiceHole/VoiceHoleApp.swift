import SwiftUI
#if os(macOS)
import UserNotifications

/// Routes notification actions (the "Record" button on the meeting-detected
/// notification) back into the app.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == MeetingDetector.recordActionID {
            NotificationCenter.default.post(name: .voiceholeRecordMeeting, object: nil)
        }
    }
}
#endif

@main
struct VoiceHoleApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
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
