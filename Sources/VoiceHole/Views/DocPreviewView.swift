import SwiftUI

/// A rendered "page" preview of the formatted document.
struct DocPreviewView: View {
    let memo: Memo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(memo.title)
                .font(.title.weight(.bold))

            Text(metaLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            if let summary = memo.summary, !summary.isEmpty {
                sectionHeader("Summary")
                Text(inlineMarkdown(summary))
                    .textSelection(.enabled)
            }

            if memo.isTranscribed {
                sectionHeader("Transcript")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(DocFormatter.paragraphs(for: memo).enumerated()), id: \.offset) { _, para in
                        VStack(alignment: .leading, spacing: 2) {
                            if let start = para.start {
                                Text(Format.timestamp(start))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(para.text)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 700, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var metaLine: String {
        var meta = "\(memo.createdAt.formatted(date: .long, time: .shortened))  ·  \(Format.duration(memo.duration))"
        if let lang = memo.language { meta += "  ·  \(Format.languageName(lang))" }
        if let model = memo.modelUsed { meta += "  ·  Whisper \(WhisperModel.label(for: model))" }
        return meta
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Divider()
        }
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
