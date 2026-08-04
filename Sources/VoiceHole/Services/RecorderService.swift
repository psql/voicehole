import Foundation
import AVFoundation
import SwiftUI

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
    /// Spring-smoothed 0…~1.4 input level for the recording visualizer
    /// (fast attack, bouncy overshoot — davinciAudio orb style).
    @Published private(set) var displayLevel: CGFloat = 0
    /// Reshuffles the orb palette; randomized at the start of each recording.
    @Published private(set) var paletteSeed: UInt64 = 0x5EED
    @Published private(set) var devices: [InputDevice] = []
    @Published var selectedDeviceID: String? {
        didSet { UserDefaults.standard.set(selectedDeviceID, forKey: "recordDevice") }
    }
    @Published var lastError: String?

    /// Called with the finished recording file; the receiver owns the file.
    var onFinish: ((URL) -> Void)?

    private var timer: Timer?
    private var meterTimer: Timer?
    private var springVelocity: CGFloat = 0
    private var startedAt: Date?

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
                self.onFinish?(url)
            }
        }
        #else
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        endTiming()
        if let url = pendingURL {
            pendingURL = nil
            onFinish?(url)
        }
        #endif
    }

    private func beginTiming() {
        isRecording = true
        elapsed = 0
        startedAt = Date()
        springVelocity = 0
        displayLevel = 0
        paletteSeed = UInt64.random(in: UInt64.min...UInt64.max)
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
        displayLevel = 0
        springVelocity = 0
    }

    /// Reads the current input power and integrates a bouncy spring toward it,
    /// mirroring the fast-attack "Springy" behavior of the davinciAudio orb.
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
        let settings = OrbSettings.shared
        let target = max(0, min(1.2, (CGFloat(db) + 55) / 47 * settings.gain))
        springVelocity += (target - displayLevel) * settings.stiffness
        springVelocity *= settings.damping
        displayLevel = max(0, min(1.4, displayLevel + springVelocity))
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
                self.lastError = "Recording failed: \(error.localizedDescription)"
            } else {
                self.onFinish?(outputFileURL)
            }
        }
    }
}
#endif
