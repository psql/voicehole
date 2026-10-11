import Foundation
import AVFoundation
import SwiftUI
import os

/// Records new memos from a selectable input device.
/// macOS: AVCaptureSession + AVCaptureAudioFileOutput (per-device selection).
/// iOS: AVAudioRecorder + AVAudioSession preferred input.
@MainActor
final class RecorderService: NSObject, ObservableObject {
    struct InputDevice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    enum Mode {
        case microphone
        case meeting   // system audio + mic (macOS only)
    }

    @Published private(set) var isRecording = false
    @Published private(set) var mode: Mode = .microphone
    @Published private(set) var elapsed: TimeInterval = 0
    /// Recent input levels (0…1, oldest first) for the bar visualizer;
    /// one sample per meter tick, about the last few seconds.
    @Published private(set) var levelHistory: [CGFloat] = []
    static let levelHistoryLength = 120
    /// Seconds since the input last rose above the silence threshold.
    @Published private(set) var silenceDuration: TimeInterval = 0
    @Published private(set) var devices: [InputDevice] = []
    @Published var selectedDeviceID: String? {
        didSet { UserDefaults.standard.set(selectedDeviceID, forKey: "recordDevice") }
    }
    @Published var lastError: String?

    /// Called with the finished recording file; the receiver owns the file.
    var onFinish: ((URL) -> Void)?

    private static let silenceLog = Logger(subsystem: "com.altbizney.voicehole", category: "silence")
    private var timer: Timer?
    private var meterTimer: Timer?
    private var startedAt: Date?
    private var lastSoundAt: Date?
    /// ~130 ms smoothed input power (linear), so single noisy samples don't
    /// register as sound.
    private var smoothedPower: Float = 0
    /// Per-second average smoothed level (dB), newest last; the quietest
    /// second in the window is the current noise floor.
    private var floorBuckets: [Float] = []
    private var floorBucketSecond: Int = -1
    private var bucketSum: Float = 0
    private var bucketCount: Int = 0
    /// When set, the finished file is cut to this many seconds before hand-off.
    private var pendingTrimEnd: TimeInterval?

    #if os(macOS)
    private var session: AVCaptureSession?
    private var fileOutput: AVCaptureAudioFileOutput?
    private var systemCapture: SystemAudioCapture?
    private var meetingURL: URL?
    #else
    private var recorder: AVAudioRecorder?
    private var pendingURL: URL?
    #endif

    override init() {
        super.init()
        selectedDeviceID = UserDefaults.standard.string(forKey: "recordDevice")
        refreshDevices()
    }

    // MARK: - Devices

    func refreshDevices() {
        #if os(macOS)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        devices = discovery.devices.map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
        #else
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        devices = (audioSession.availableInputs ?? []).map { InputDevice(id: $0.uid, name: $0.portName) }
        #endif
        if let selected = selectedDeviceID, !devices.contains(where: { $0.id == selected }) {
            selectedDeviceID = nil
        }
    }

    // MARK: - Recording

    func toggle() {
        if isRecording { stop() } else { Task { await start() } }
    }

    #if os(macOS)
    /// Records system audio + the default microphone into Apple Lossless,
    /// saved to the user-configurable meeting recordings folder.
    func startMeeting() async {
        guard !isRecording else { return }
        let destination = MeetingSettings.shared.recordingsFolderURL
            .appendingPathComponent(Self.recordingName(prefix: "Meeting"))
        // System audio records either way; the mic is mixed in when permitted.
        let micAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        let capture = SystemAudioCapture()
        capture.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.mode == .meeting else { return }
                self.lastError = "System audio capture stopped: \(message)"
                self.stop()
            }
        }
        do {
            try await capture.start(writingTo: destination, mixMicrophone: micAllowed)
            systemCapture = capture
            meetingURL = destination
            mode = .meeting
            beginTiming()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            lastError = "Couldn't record system audio: \(error.localizedDescription)\n\nIf VoiceHole doesn't have permission yet, enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        }
    }
    #endif

    func start() async {
        guard !isRecording else { return }
        mode = .microphone
        refreshDevices()

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.recordingName())

        #if os(macOS)
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            lastError = "Microphone access was denied. Enable it in System Settings → Privacy & Security → Microphone."
            return
        }
        let device = selectedDeviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else {
            lastError = "No microphone found."
            return
        }
        do {
            let session = AVCaptureSession()
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw NSError(domain: "VoiceHole", code: 1) }
            session.addInput(input)
            let output = AVCaptureAudioFileOutput()
            guard session.canAddOutput(output) else { throw NSError(domain: "VoiceHole", code: 2) }
            session.addOutput(output)
            session.startRunning()
            output.startRecording(to: destination, outputFileType: .m4a, recordingDelegate: self)
            self.session = session
            self.fileOutput = output
            beginTiming()
        } catch {
            lastError = "Couldn't start recording: \(error.localizedDescription)"
        }
        #else
        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = "Microphone access was denied. Enable it in Settings → Privacy & Security → Microphone."
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            if let selected = selectedDeviceID,
               let port = audioSession.availableInputs?.first(where: { $0.uid == selected }) {
                try? audioSession.setPreferredInput(port)
            }
            try audioSession.setActive(true)
            let recorder = try AVAudioRecorder(url: destination, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
            self.pendingURL = destination
            beginTiming()
        } catch {
            lastError = "Couldn't start recording: \(error.localizedDescription)"
        }
        #endif
    }

    func stop() {
        guard isRecording else { return }
        #if os(macOS)
        switch mode {
        case .microphone:
            fileOutput?.stopRecording()
        case .meeting:
            guard let capture = systemCapture, let url = meetingURL else { return }
            systemCapture = nil
            meetingURL = nil
            Task { [weak self] in
                await capture.stop()
                guard let self else { return }
                self.endTiming()
                self.mode = .microphone
                self.finish(url)
            }
        }
        #else
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        endTiming()
        if let url = pendingURL {
            pendingURL = nil
            finish(url)
        }
        #endif
    }

    /// Stops because nothing has been heard for the configured timeout; the
    /// saved file is trimmed to end shortly after the last sound.
    private func stopForSilence() {
        guard isRecording, let startedAt, let lastSoundAt else { return }
        pendingTrimEnd = lastSoundAt.timeIntervalSince(startedAt) + RecordingSettings.trimTail
        stop()
    }

    /// Applies any pending silence trim, then hands the file to `onFinish`.
    private func finish(_ url: URL) {
        let trimEnd = pendingTrimEnd
        pendingTrimEnd = nil
        guard let trimEnd else {
            onFinish?(url)
            return
        }
        Task { [weak self] in
            await AudioTrimmer.trim(url, to: trimEnd)
            self?.onFinish?(url)
        }
    }

    private func beginTiming() {
        isRecording = true
        elapsed = 0
        startedAt = Date()
        lastSoundAt = startedAt
        silenceDuration = 0
        smoothedPower = 0
        floorBuckets = []
        floorBucketSecond = -1
        bucketSum = 0
        bucketCount = 0
        pendingTrimEnd = nil
        levelHistory = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickMeter() }
        }
    }

    private func endTiming() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        meterTimer?.invalidate()
        meterTimer = nil
        startedAt = nil
        lastSoundAt = nil
        silenceDuration = 0
        levelHistory = []
    }

    /// Reads the current input power, appends it to the visualizer history,
    /// and feeds the silence detector.
    private func tickMeter() {
        guard isRecording else { return }
        var db: Float = -160
        #if os(macOS)
        if mode == .meeting {
            db = systemCapture?.averagePowerDB ?? -160
        } else if let channel = fileOutput?.connections.first?.audioChannels.first {
            db = channel.averagePowerLevel
        }
        #else
        if let recorder {
            recorder.updateMeters()
            db = recorder.averagePower(forChannel: 0)
        }
        #endif
        // -55 dB (room tone) → 0, -8 dB (shouting) → 1; fast attack, gentle decay.
        let instant = max(0, min(1, (CGFloat(db) + 55) / 47))
        let previous = levelHistory.last ?? 0
        let level = max(instant, previous * 0.82)
        levelHistory.append(level)
        if levelHistory.count > Self.levelHistoryLength {
            levelHistory.removeFirst(levelHistory.count - Self.levelHistoryLength)
        }
        trackSilence(db: db)
    }

    /// Notes when sound was last heard and auto-stops once the configured
    /// stretch of silence has passed. "Sound" is anything well above the
    /// rolling noise floor, so room tone and mic hiss never reset the timer.
    private func trackSilence(db: Float) {
        let now = Date()
        guard let startedAt else { return }

        let power = pow(10, max(db, -160) / 10)
        smoothedPower += (power - smoothedPower) * 0.25
        let level = 10 * log10(max(smoothedPower, 1e-16))

        let second = Int(now.timeIntervalSince(startedAt))
        if second != floorBucketSecond {
            if bucketCount > 0 {
                floorBuckets.append(bucketSum / Float(bucketCount))
                if floorBuckets.count > RecordingSettings.noiseFloorWindow {
                    floorBuckets.removeFirst(floorBuckets.count - RecordingSettings.noiseFloorWindow)
                }
                Self.silenceLog.debug("t=\(second) level=\(level, format: .fixed(precision: 1)) secAvg=\(self.floorBuckets.last ?? 0, format: .fixed(precision: 1)) floor=\(self.floorBuckets.min() ?? 0, format: .fixed(precision: 1)) silence=\(self.silenceDuration, format: .fixed(precision: 0))")
            }
            floorBucketSecond = second
            bucketSum = 0
            bucketCount = 0
        }
        bucketSum += level
        bucketCount += 1
        // Until a full second has been averaged, treat the current level as the floor.
        let noiseFloor = floorBuckets.min() ?? level
        let threshold = max(noiseFloor + RecordingSettings.silenceMarginDB,
                            RecordingSettings.silenceAbsoluteFloorDB)
        if level > threshold {
            lastSoundAt = now
        }
        guard let lastSoundAt else { return }
        let silence = now.timeIntervalSince(lastSoundAt)
        // Whole-second granularity keeps the overlay countdown from re-rendering 30×/s.
        if silence.rounded(.down) != silenceDuration.rounded(.down) || silence < silenceDuration {
            silenceDuration = silence
        }
        let timeout = RecordingSettings.shared.silenceTimeout
        if timeout > 0, silence >= timeout {
            stopForSilence()
        }
    }

    private static func recordingName(prefix: String = "Recording") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h.mm.ss a"
        return "\(prefix) \(formatter.string(from: Date())).m4a"
    }
}

#if os(macOS)
extension RecorderService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.session?.stopRunning()
            self.session = nil
            self.fileOutput = nil
            self.endTiming()
            if let error {
                self.pendingTrimEnd = nil
                self.lastError = "Recording failed: \(error.localizedDescription)"
            } else {
                self.finish(outputFileURL)
            }
        }
    }
}
#endif
