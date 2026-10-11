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
        .init(id: "openai_whisper-large-v3_turbo", label: "Large Turbo", detail: "Best quality · ~3 GB"),
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
    private var prepareTask: Task<Void, Error>?
    private var preparingVariant: String?

    private var modelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceHole/Models", isDirectory: true)
    }

    init(store: MemoStore) {
        self.store = store
        self.selectedModelID = UserDefaults.standard.string(forKey: "selectedModel") ?? "openai_whisper-base"
    }

    // MARK: - Model management

    private func modelFolderURL(for variant: String) -> URL {
        modelsRoot
            .appendingPathComponent("models")
            .appendingPathComponent(Self.modelRepo)
            .appendingPathComponent(variant)
    }

    /// Every compiled Core ML bundle WhisperKit needs to run. A folder that is
    /// missing any of these (or whose bundle lacks its compiled payload) is an
    /// interrupted download, not a usable model.
    private static let requiredBundles = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    /// Returns the model folder only if the download finished. A folder that
    /// exists but is incomplete (interrupted download) returns nil so callers
    /// re-download instead of trying to load a broken model.
    func downloadedFolder(for variant: String) -> URL? {
        isCompleteModel(variant) ? modelFolderURL(for: variant) : nil
    }

    /// Hugging Face's downloader stages in-flight files here as `*.incomplete`.
    private func downloadCacheURL(for variant: String) -> URL {
        modelsRoot
            .appendingPathComponent("models")
            .appendingPathComponent(Self.modelRepo)
            .appendingPathComponent(".cache/huggingface/download")
            .appendingPathComponent(variant)
    }

    private func isCompleteModel(_ variant: String) -> Bool {
        let fm = FileManager.default
        let url = modelFolderURL(for: variant)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        guard fm.fileExists(atPath: url.appendingPathComponent("config.json").path) else { return false }
        for name in Self.requiredBundles {
            let bundle = url.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            guard fm.fileExists(atPath: bundle.appendingPathComponent("coremldata.bin").path),
                  fm.fileExists(atPath: bundle.appendingPathComponent("weights/weight.bin").path)
            else { return false }
        }
        // A bundle's small files can land before its multi-hundred-MB weights,
        // so an interrupted download can look structurally complete. Anything
        // still staged as `.incomplete` means the download never finished.
        if let e = fm.enumerator(at: downloadCacheURL(for: variant), includingPropertiesForKeys: nil) {
            for case let file as URL in e where file.pathExtension == "incomplete" {
                return false
            }
        }
        return true
    }

    /// Deletes a model folder and its download cache so the next attempt is a
    /// clean re-download. Used when files are present but unloadable (corrupt),
    /// since the downloader would otherwise trust its cache and skip them.
    private func discardModel(_ variant: String) {
        let fm = FileManager.default
        for url in [modelFolderURL(for: variant), downloadCacheURL(for: variant)]
        where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
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
        discardModel(variant)
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

    /// Downloads (if needed) and loads the selected model. Concurrent callers
    /// (the transcription queue, the Download button, model switching) share one
    /// in-flight task: two simultaneous downloads of the same variant race on
    /// the same staging files and corrupt each other.
    func prepare() async throws {
        if whisper != nil, loadedVariant == selectedModelID, modelState == .ready { return }

        if let inFlight = prepareTask {
            if preparingVariant == selectedModelID {
                return try await inFlight.value
            }
            // A different variant is mid-flight; let it finish before starting ours.
            _ = try? await inFlight.value
            if whisper != nil, loadedVariant == selectedModelID, modelState == .ready { return }
        }

        let variant = selectedModelID
        let task = Task { try await self.performPrepare(variant: variant) }
        prepareTask = task
        preparingVariant = variant
        defer {
            if prepareTask == task {
                prepareTask = nil
                preparingVariant = nil
            }
        }
        try await task.value
    }

    private func performPrepare(variant: String) async throws {
        let folder: URL
        if let existing = downloadedFolder(for: variant) {
            folder = existing
        } else {
            // An incomplete folder is left in place: the downloader skips files
            // it already finished and resumes the rest.
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
                downloadBase: modelsRoot,
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
            // If the on-disk model is broken, throw it away so "Try Again"
            // re-downloads instead of failing on the same missing file.
            discardModel(variant)
            modelState = .failed("Model files were damaged and have been removed. Try again to re-download.")
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
