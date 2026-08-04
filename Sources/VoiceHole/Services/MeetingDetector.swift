#if os(macOS)
import AppKit
import Combine
import CoreAudio
import Foundation
import UserNotifications

/// Watches for a likely meeting: a call-capable app is running while the
/// default microphone is live. Suggests recording via a local notification
/// (with a Record action) and publishes state for the in-app banner.
@MainActor
final class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()

    static let recordActionID = "VOICEHOLE_RECORD_MEETING"
    static let categoryID = "VOICEHOLE_MEETING_DETECTED"

    /// Display name of the app that looks like it's in a call; nil = no meeting.
    @Published private(set) var meetingApp: String?
    /// The user waved off the in-app banner for the current meeting.
    @Published var bannerDismissed = false

    /// Set by the UI so detection ignores VoiceHole's own recordings.
    var isSelfRecording: () -> Bool = { false }

    private struct CandidateApp {
        let bundleID: String
        let name: String
        let isBrowser: Bool
    }

    private static let candidates: [CandidateApp] = [
        .init(bundleID: "us.zoom.xos", name: "Zoom", isBrowser: false),
        .init(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", isBrowser: false),
        .init(bundleID: "com.microsoft.teams", name: "Microsoft Teams", isBrowser: false),
        .init(bundleID: "com.apple.FaceTime", name: "FaceTime", isBrowser: false),
        .init(bundleID: "Cisco-Systems.Spark", name: "Webex", isBrowser: false),
        .init(bundleID: "com.cisco.webexmeetingsapp", name: "Webex", isBrowser: false),
        .init(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", isBrowser: false),
        .init(bundleID: "com.hnc.Discord", name: "Discord", isBrowser: false),
        .init(bundleID: "com.amazon.Amazon-Chime", name: "Chime", isBrowser: false),
        .init(bundleID: "com.google.Chrome", name: "your browser", isBrowser: true),
        .init(bundleID: "com.apple.Safari", name: "your browser", isBrowser: true),
        .init(bundleID: "company.thebrowser.Browser", name: "your browser", isBrowser: true),
        .init(bundleID: "com.microsoft.edgemac", name: "your browser", isBrowser: true),
        .init(bundleID: "org.mozilla.firefox", name: "your browser", isBrowser: true),
    ]

    private let settings = MeetingSettings.shared
    private var enabledSink: AnyCancellable?
    private var timer: Timer?
    private var consecutiveHits = 0
    private var consecutiveMisses = 0
    private var notifiedThisMeeting = false

    private init() {
        enabledSink = settings.$detectMeetings.sink { [weak self] enabled in
            Task { @MainActor [weak self] in
                enabled ? self?.start() : self?.stop()
            }
        }
    }

    // MARK: - Polling

    private func start() {
        guard timer == nil else { return }
        let center = UNUserNotificationCenter.current()
        let record = UNNotificationAction(identifier: Self.recordActionID, title: "Record", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [record], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        poll()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        meetingApp = nil
        consecutiveHits = 0
        consecutiveMisses = 0
        notifiedThisMeeting = false
    }

    private func poll() {
        // Our own capture keeps the mic busy; skip while recording.
        guard !isSelfRecording() else { return }

        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidate = Self.candidates.first { !$0.isBrowser && running.contains($0.bundleID) }
            ?? Self.candidates.first { running.contains($0.bundleID) }
        let inMeeting = candidate != nil && Self.microphoneInUse()

        if inMeeting {
            consecutiveHits += 1
            consecutiveMisses = 0
            // Two consecutive hits (~6 s) before calling it a meeting.
            if consecutiveHits >= 2, meetingApp == nil {
                meetingApp = candidate?.name
                bannerDismissed = false
                if !notifiedThisMeeting {
                    notifiedThisMeeting = true
                    postNotification(appName: candidate?.name ?? "a call")
                }
            }
        } else {
            consecutiveHits = 0
            consecutiveMisses += 1
            // ~15 s of quiet before the meeting counts as over, so a brief
            // mute doesn't reset state and re-notify.
            if consecutiveMisses >= 5 {
                meetingApp = nil
                notifiedThisMeeting = false
            }
        }
    }

    private func postNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting detected"
        content.body = appName == "your browser"
            ? "Looks like you're in a call. Record it for meeting notes?"
            : "Looks like you're in a \(appName) call. Record it for meeting notes?"
        content.categoryIdentifier = Self.categoryID
        let request = UNNotificationRequest(
            identifier: "voicehole.meeting.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// True when the default input device is capturing for any process.
    private static func microphoneInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }
}
#endif
