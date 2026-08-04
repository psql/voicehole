import Foundation
import SwiftUI

/// User settings for meeting detection and where meeting recordings are saved.
@MainActor
final class MeetingSettings: ObservableObject {
    static let shared = MeetingSettings()

    /// Watch for likely meetings and suggest recording them.
    @Published var detectMeetings: Bool {
        didSet { UserDefaults.standard.set(detectMeetings, forKey: "detectMeetings") }
    }

    /// Folder where meeting recordings are written. Empty = default folder.
    @Published var recordingsPath: String {
        didSet { UserDefaults.standard.set(recordingsPath, forKey: "meetingRecordingsPath") }
    }

    private init() {
        detectMeetings = UserDefaults.standard.object(forKey: "detectMeetings") as? Bool ?? true
        recordingsPath = UserDefaults.standard.string(forKey: "meetingRecordingsPath") ?? ""
    }

    static var defaultFolderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceHole Meetings", isDirectory: true)
    }

    /// Resolved destination folder, created on demand.
    var recordingsFolderURL: URL {
        let url = recordingsPath.isEmpty
            ? Self.defaultFolderURL
            : URL(fileURLWithPath: (recordingsPath as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
