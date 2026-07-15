import Foundation
import AVFoundation

@MainActor
final class MemoStore: ObservableObject {
    @Published private(set) var memos: [Memo] = []

    let rootURL: URL
    let audioDirURL: URL
    private let indexURL: URL

    init() {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceHole", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        rootURL = base
        audioDirURL = base.appendingPathComponent("Memos", isDirectory: true)
        indexURL = base.appendingPathComponent("memos.json")
        try? FileManager.default.createDirectory(at: audioDirURL, withIntermediateDirectories: true)
        load()
    }

    func memo(id: UUID) -> Memo? {
        memos.first { $0.id == id }
    }

    func audioURL(for memo: Memo) -> URL {
        audioDirURL.appendingPathComponent(memo.audioFileName)
    }

    @discardableResult
    func importAudio(from sourceURL: URL) throws -> Memo {
        let didScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if didScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let dest = audioDirURL.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        var memo = Memo(id: id, title: sourceURL.deletingPathExtension().lastPathComponent, audioFileName: fileName)
        memo.duration = Self.duration(of: dest)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let created = attrs[.creationDate] as? Date {
            memo.createdAt = created
        }
        memos.insert(memo, at: 0)
        save()
        return memo
    }

    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].title = trimmed
        save()
    }

    func delete(_ memo: Memo) {
        try? FileManager.default.removeItem(at: audioURL(for: memo))
        memos.removeAll { $0.id == memo.id }
        save()
    }

    func delete(ids: Set<UUID>) {
        for memo in memos.filter({ ids.contains($0.id) }) {
            try? FileManager.default.removeItem(at: audioURL(for: memo))
        }
        memos.removeAll { ids.contains($0.id) }
        save()
    }

    func setTranscription(id: UUID, transcript: String, segments: [MemoSegment], language: String?, model: String) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].transcript = transcript
        memos[i].segments = segments
        memos[i].language = language
        memos[i].modelUsed = model
        memos[i].transcribedAt = Date()
        save()
    }

    func setSummary(id: UUID, summary: String) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].summary = summary
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        memos = (try? decoder.decode([Memo].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(memos) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    static func duration(of url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }
}
