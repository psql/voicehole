import Foundation

struct MemoSegment: Codable, Hashable {
    var text: String
    var start: Double
    var end: Double
}

struct Memo: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var duration: TimeInterval = 0
    var audioFileName: String
    var transcript: String?
    var segments: [MemoSegment] = []
    var summary: String?
    var language: String?
    var modelUsed: String?
    var transcribedAt: Date?

    var isTranscribed: Bool { !(transcript ?? "").isEmpty }
}
