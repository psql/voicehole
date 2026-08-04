#if os(macOS)
import Foundation
import AVFoundation
import ScreenCaptureKit

/// Captures system audio (ScreenCaptureKit) mixed with the default microphone
/// (AVAudioEngine) into a single Apple Lossless (ALAC) mono .m4a — lossless,
/// but roughly half the size of raw PCM. System audio drives the timeline;
/// mic samples are mixed in as they arrive.
/// @unchecked Sendable: mutable state is confined to mixQueue or levelLock.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let sampleRate = 48_000.0

    /// Called if capture dies mid-recording (e.g. permission revoked).
    var onError: ((String) -> Void)?

    private var stream: SCStream?
    private let engine = AVAudioEngine()
    private var micConverter: AVAudioConverter?
    private var micActive = false

    /// FIFOs, file writes, and SCK callbacks are all confined to mixQueue.
    private let mixQueue = DispatchQueue(label: "com.altbizney.voicehole.meetingmix")
    private var systemFIFO: [Float] = []
    private var micFIFO: [Float] = []
    private var file: AVAudioFile?

    private let levelLock = NSLock()
    private var powerDB: Float = -160

    /// Average power of the mixed output in dB, matching AVFoundation metering.
    var averagePowerDB: Float {
        levelLock.lock()
        defer { levelLock.unlock() }
        return powerDB
    }

    func start(writingTo url: URL, mixMicrophone: Bool) async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitDepthHintKey: 16,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Throws when Screen Recording permission is missing; callers surface it.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "VoiceHole", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "No display available for system audio capture.",
            ])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(Self.sampleRate)
        config.channelCount = 1
        // Video is part of the stream but unused: minimum size and rate.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: mixQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: mixQueue)
        try await stream.startCapture()
        self.stream = stream

        if mixMicrophone {
            startMicrophone(outputFormat: format)
        }
    }

    func stop() async {
        if micActive {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micActive = false
        }
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        await withCheckedContinuation { continuation in
            mixQueue.async { [weak self] in
                self?.drain(flush: true)
                self?.file = nil   // releases (and closes) the file
                continuation.resume()
            }
        }
    }

    // MARK: - Microphone

    private func startMicrophone(outputFormat: AVAudioFormat) {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return }
        micConverter = converter
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.mixQueue.async { self?.appendMic(buffer) }
        }
        do {
            try engine.start()
            micActive = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func appendMic(_ buffer: AVAudioPCMBuffer) {
        guard let converter = micConverter else { return }
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData, out.frameLength > 0 else { return }
        micFIFO.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
        // Bound clock drift: never hold more than 2 s of unmixed mic audio.
        let cap = Int(Self.sampleRate * 2)
        if micFIFO.count > cap {
            micFIFO.removeFirst(micFIFO.count - cap)
        }
    }

    // MARK: - System audio (SCStreamOutput)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let samples = try? sampleBuffer.withAudioBufferList(body: { list, _ -> [Float] in
            // Configured mono, but average across channels defensively.
            let buffers = Array(list)
            guard let first = buffers.first, let base = first.mData else { return [] }
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            var mono = Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: Float.self), count: count))
            for extra in buffers.dropFirst() {
                guard let ptr = extra.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = min(count, Int(extra.mDataByteSize) / MemoryLayout<Float>.size)
                for i in 0..<n { mono[i] += ptr[i] }
            }
            if buffers.count > 1 {
                let scale = 1 / Float(buffers.count)
                for i in mono.indices { mono[i] *= scale }
            }
            return mono
        }), !samples.isEmpty else { return }

        systemFIFO.append(contentsOf: samples)
        drain()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error.localizedDescription)
    }

    // MARK: - Mixing

    /// Pops system audio in chunks, mixes in whatever mic audio has arrived
    /// (padding with silence when the mic FIFO runs dry), and writes ALAC.
    private func drain(flush: Bool = false) {
        guard let file else { return }
        let chunk = 4800
        while systemFIFO.count >= chunk || (flush && !systemFIFO.isEmpty) {
            let n = min(chunk, systemFIFO.count)
            var mixed = Array(systemFIFO.prefix(n))
            systemFIFO.removeFirst(n)
            let micN = min(n, micFIFO.count)
            if micN > 0 {
                for i in 0..<micN { mixed[i] += micFIFO[i] }
                micFIFO.removeFirst(micN)
            }

            var sumSquares: Float = 0
            for i in mixed.indices {
                mixed[i] = max(-1, min(1, mixed[i]))
                sumSquares += mixed[i] * mixed[i]
            }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(n)) else { continue }
            buffer.frameLength = AVAudioFrameCount(n)
            mixed.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: n)
            }
            try? file.write(from: buffer)

            let rms = (sumSquares / Float(n)).squareRoot()
            levelLock.lock()
            powerDB = 20 * log10(max(rms, 1e-8))
            levelLock.unlock()
        }
    }
}
#endif
