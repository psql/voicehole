import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

enum SummaryService {

    static func summarize(_ transcript: String, title: String) async -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if text.count < 280 { return text }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            if let smart = await appleIntelligenceSummary(text: text, title: title) {
                return smart
            }
        }
        #endif
        return extractiveSummary(text: text)
    }

    // MARK: - Apple Intelligence (fully on-device)

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private static func appleIntelligenceSummary(text: String, title: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        do {
            let chunks = chunk(text, maxChars: 9000)
            if chunks.count == 1 {
                return try await summarizeChunk(chunks[0], title: title)
            }
            var partials: [String] = []
            for (i, c) in chunks.enumerated() {
                let partial = try await summarizeChunk(c, title: title, partIndex: i + 1, partCount: chunks.count)
                partials.append(partial)
            }
            let session = LanguageModelSession(instructions:
                "You merge partial summaries of one voice memo into a single clean summary. Reply in markdown: a 2-4 sentence overview paragraph, then a bulleted list of key points. Include any action items. No preamble.")
            let response = try await session.respond(to:
                "Merge these partial summaries of the voice memo “\(title)” into one summary:\n\n\(partials.joined(separator: "\n\n---\n\n"))")
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private static func summarizeChunk(_ chunk: String, title: String, partIndex: Int? = nil, partCount: Int? = nil) async throws -> String {
        let session = LanguageModelSession(instructions:
            "You summarize voice memo transcripts. Reply in markdown: a 2-4 sentence overview paragraph, then a bulleted list of key points. Include any action items or decisions mentioned. No preamble, no headings.")
        var prompt = "Summarize this transcript of the voice memo “\(title)”"
        if let i = partIndex, let n = partCount { prompt += " (part \(i) of \(n))" }
        prompt += ":\n\n\(chunk)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    private static func chunk(_ text: String, maxChars: Int) -> [String] {
        guard text.count > maxChars else { return [text] }
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(in: text) {
            if current.count + sentence.count > maxChars, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += sentence
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Extractive fallback (no Apple Intelligence required)

    private static func extractiveSummary(text: String) -> String {
        let sents = sentences(in: text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard sents.count > 3 else { return text }

        func words(_ s: String) -> [String] {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopwords.contains($0) }
        }

        var freq: [String: Double] = [:]
        for s in sents { for w in words(s) { freq[w, default: 0] += 1 } }

        let scored: [(index: Int, sentence: String, score: Double)] = sents.enumerated().map { i, s in
            let ws = words(s)
            let total = ws.reduce(0.0) { $0 + (freq[$1] ?? 0) }
            return (i, s, total / Double(ws.count + 2).squareRoot())
        }

        let keepCount = min(6, max(3, sents.count / 5))
        let top = scored.sorted { $0.score > $1.score }.prefix(keepCount).sorted { $0.index < $1.index }

        var out = "**Key points**\n"
        for item in top { out += "- \(item.sentence)\n" }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            out.append(String(text[range]))
            return true
        }
        return out
    }

    private static let stopwords: Set<String> = [
        "the", "and", "that", "this", "with", "for", "you", "your", "was", "are", "but", "not", "have", "has",
        "had", "they", "them", "then", "than", "there", "their", "what", "when", "where", "which", "who", "how",
        "why", "can", "could", "would", "should", "will", "just", "like", "know", "yeah", "okay", "get", "got",
        "going", "gonna", "really", "think", "thing", "things", "about", "into", "out", "our", "were", "been",
        "being", "because", "so", "some", "more", "very", "also", "from", "one", "two", "all", "any", "its",
        "it's", "i'm", "don't", "doesn't", "didn't", "we're", "you're", "that's", "want", "wanted", "need",
        "kind", "sort", "mean", "well", "right", "now", "here", "say", "said", "see", "way", "make", "made",
        "let", "lot", "much", "even", "still", "too", "over", "after", "before", "off", "did", "does",
    ]
}
