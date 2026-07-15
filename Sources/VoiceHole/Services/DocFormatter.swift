import Foundation

enum DocFormatter {

    struct Paragraph {
        var start: Double?
        var text: String
    }

    static func markdown(for memo: Memo) -> String {
        var out = "# \(memo.title)\n\n"
        out += "- **Date:** \(memo.createdAt.formatted(date: .long, time: .shortened))\n"
        out += "- **Duration:** \(Format.duration(memo.duration))\n"
        if let lang = memo.language, !lang.isEmpty {
            out += "- **Language:** \(Format.languageName(lang))\n"
        }
        if let model = memo.modelUsed {
            out += "- **Transcribed with:** Whisper \(WhisperModel.label(for: model)) (on-device)\n"
        }
        out += "\n"

        if let summary = memo.summary, !summary.isEmpty {
            out += "## Summary\n\n\(summary)\n\n"
        }
        if memo.isTranscribed {
            out += "## Transcript\n\n"
            for p in paragraphs(for: memo) {
                if let start = p.start {
                    out += "**[\(Format.timestamp(start))]** \(p.text)\n\n"
                } else {
                    out += "\(p.text)\n\n"
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func paragraphs(for memo: Memo) -> [Paragraph] {
        let segments = memo.segments.filter { !$0.text.isEmpty }
        guard !segments.isEmpty else {
            guard let transcript = memo.transcript, !transcript.isEmpty else { return [] }
            return [Paragraph(start: nil, text: transcript)]
        }

        var paragraphs: [Paragraph] = []
        var currentText = ""
        var currentStart = segments[0].start
        var lastEnd = segments[0].start

        for segment in segments {
            let gap = segment.start - lastEnd
            if !currentText.isEmpty, gap > 1.4 || currentText.count > 600 {
                paragraphs.append(Paragraph(start: currentStart, text: currentText))
                currentText = ""
                currentStart = segment.start
            }
            currentText += currentText.isEmpty ? segment.text : " " + segment.text
            lastEnd = segment.end
        }
        if !currentText.isEmpty {
            paragraphs.append(Paragraph(start: currentStart, text: currentText))
        }
        return paragraphs
    }

    static func plainTranscript(for memo: Memo) -> String {
        paragraphs(for: memo).map(\.text).joined(separator: "\n\n")
    }
}
