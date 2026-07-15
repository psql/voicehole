import Foundation
import SwiftUI
import WhisperKit

struct WhisperModel: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String

    static let all: [WhisperModel] = [
        .init(id: "openai_whisper-tiny", label: "Tiny", detail: "Fastest · ~150 MB"),
        .init(id: "openai_whisper-base", label: "Base", detail: "Balanced · ~300 MB"),
        .init(id: "openai_whisper-small", label: "Small", detail: "More accurate · ~900 MB"),
        .init(id: "openai_whisper-large-v3_turbo", label: "Large Turbo", detail: "Best quality · ~1.6 GB"),
    ]

    static func label(for id: String) -> String {
        all.first { $0.id == id }?.label ?? id
    }
}

@MainActor
final class TranscriptionService: ObservableObject {
    static let modelRepo = "argmaxinc/whisperkit-coreml"

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .notDownloaded: return "Not downloaded"
            case .downloading(let f): return "Downloading… \(Int(f * 100))%"
            case .loading: return "Loading model…"
            case .ready: return "Ready"
            case .failed(let e): return "Error: \(e)"
            }
        }
    }

    @Published var modelState: ModelState = .notDownloaded
    @Published private(set) var selectedModelID: String
    @Published private(set) var currentMemoID: UUID?
    @Published private(set) var pending: [UUID] = []
    @Published var liveText: String = ""
    @Published var progressFraction: Double = 0
    @Published var lastError: String?

    private let store: MemoStore
    private var whisper: WhisperKit?
    private var loadedVariant: String?
    private var runTask: Task<Void, Never>?

    private var modelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceHole/Models", isDirectory: true)
    }

    init(store: MemoStore) {
        self.store = store
        self.selectedModelID = UserDefaults.standard.string(forKey: "selectedModel") ?? "openai_whisper-base"
    }

    // MARK: - Model management

    func downloadedFolder(for variant: String) -> URL? {
        let url = modelsRoot
            .appendingPathComponent("models")
            .appendingPathComponent(Self.modelRepo)
            .appendingPathComponent(variant)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return (exists && isDir.boolValue) ? url : nil
    }

    func isDownloaded(_ variant: String) -> Bool {
        downloadedFolder(for: variant) != nil
    }

    func selectModel(_ variant: String) {
        guard variant != selectedModelID else { return }
        selectedModelID = variant
        UserDefaults.standard.set(variant, forKey: "selectedModel")
        whisper = nil
        loadedVariant = nil
        if isDownloaded(variant) {
            Task { try? await prepare() }
        } else {
            modelState = .notDownloaded
        }
    }

    func removeDownloadedModel(_ variant: String) {
        if let folder = downloadedFolder(for: variant) {
            try? FileManager.default.removeItem(at: folder)
        }
        if variant == loadedVariant || variant == selectedModelID {
            whisper = nil
            loadedVariant = nil
            modelState = .notDownloaded
        }
        objectWillChange.send()
    }

    func warmIfDownloaded() async {
        guard isDownloaded(selectedModelID) else { return }
        try? await prepare()
    }

    func downloadSelectedModel() {
        Task {
            do { try await prepare() }
            catch { modelState = .failed(error.localizedDescription) }
        }
    }

    func prepare() async throws {
        if whisper != nil, loadedVariant == selectedModelID, modelState == .ready { return }
        let variant = selectedModelID

        let folder: URL
        if let existing = downloadedFolder(for: variant) {
            folder = existing
        } else {
            modelState = .downloading(0)
            do {
                folder = try await WhisperKit.download(
                    variant: variant,
                    downloadBase: modelsRoot,
                    useBackgroundSession: false,
                    from: Self.modelRepo,
                    token: nil
                ) { progress in
                    Task { @MainActor [weak self] in
                        self?.modelState = .downloading(progress.fractionCompleted)
                    }
                }
            } catch {
                modelState = .failed("Download failed: \(error.localizedDescription)")
                throw error
            }
        }

        modelState = .loading
        do {
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let pipe = try await WhisperKit(config)
            whisper = pipe
            loadedVariant = variant
            modelState = .ready
        } catch {
            modelState = .failed("Couldn't load model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Transcription queue

    func enqueue(_ id: UUID) {
        guard !pending.contains(id), currentMemoID != id else { return }
        pending.append(id)
        processQueue()
    }

    private func processQueue() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            while !self.pending.isEmpty {
                let id = self.pending.removeFirst()
                await self.transcribeNow(id: id)
            }
            self.runTask = nil
        }
    }

    private func transcribeNow(id: UUID) async {
        guard let memo = store.memo(id: id) else { return }
        let url = store.audioURL(for: memo)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "Audio file is missing for “\(memo.title)”."
            return
        }

        do { try await prepare() }
        catch {
            lastError = "Model isn't ready: \(error.localizedDescription)"
            return
        }
        guard let whisper else { return }

        currentMemoID = id
        liveText = ""
        progressFraction = 0
        defer {
            currentMemoID = nil
            liveText = ""
        }

        let poll = Task { [weak whisper, weak self] in
            while !Task.isCancelled {
                if let f = whisper?.progress.fractionCompleted {
                    await MainActor.run { [weak self] in self?.progressFraction = f }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer { poll.cancel() }

        do {
            var options = DecodingOptions()
            options.chunkingStrategy = .vad
            let results = try await whisper.transcribe(audioPath: url.path, decodeOptions: options) { progress in
                Task { @MainActor [weak self] in
                    self?.liveText = Self.cleaned(progress.text)
                }
                return nil
            }

            let segments = results.flatMap(\.segments).map {
                MemoSegment(text: Self.cleaned($0.text), start: Double($0.start), end: Double($0.end))
            }.filter { !$0.text.isEmpty }

            var transcript = segments.map(\.text).joined(separator: " ")
            if transcript.isEmpty {
                transcript = Self.cleaned(results.map(\.text).joined(separator: " "))
            }
            let language = results.first?.language

            store.setTranscription(id: id, transcript: transcript, segments: segments, language: language, model: selectedModelID)
            progressFraction = 1

            if !transcript.isEmpty, let updated = store.memo(id: id) {
                let summary = await SummaryService.summarize(transcript, title: updated.title)
                store.setSummary(id: id, summary: summary)
            }
        } catch {
            lastError = "Transcription failed: \(error.localizedDescription)"
        }
    }

    nonisolated static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
