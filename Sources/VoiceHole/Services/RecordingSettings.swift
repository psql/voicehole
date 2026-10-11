import Foundation
import SwiftUI

/// User settings that apply to every recording (mic memos and meetings).
@MainActor
final class RecordingSettings: ObservableObject {
    static let shared = RecordingSettings()

    /// Sound must rise this far (dB) above the rolling noise floor to count.
    /// Speech sits 15–30 dB above room tone on typical Mac and iPhone mics.
    static let silenceMarginDB: Float = 12
    /// …and never counts below this absolute level, so a dead-quiet input
    /// (e.g. meeting capture with nothing playing) doesn't trigger on hiss.
    static let silenceAbsoluteFloorDB: Float = -50
    /// Window over which the noise floor is tracked, in seconds.
    static let noiseFloorWindow = 20

    /// Audio kept after the last detected sound when a silent tail is trimmed.
    static let trimTail: TimeInterval = 1.5

    /// Choices offered in Settings, in seconds. 0 = never stop automatically.
    static let silenceTimeoutOptions: [(label: String, seconds: TimeInterval)] = [
        ("Never", 0),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("10 minutes", 600),
    ]

    /// Stop the recording after this many seconds of continuous silence and
    /// trim the silent tail off the saved memo. 0 disables auto-stop.
    @Published var silenceTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(silenceTimeout, forKey: "silenceTimeout") }
    }

    private init() {
        let stored = UserDefaults.standard.object(forKey: "silenceTimeout") as? TimeInterval ?? 120
        // Snap to a preset so the Settings picker always has a matching row.
        silenceTimeout = Self.silenceTimeoutOptions
            .min { abs($0.seconds - stored) < abs($1.seconds - stored) }?.seconds ?? 120
    }
}
