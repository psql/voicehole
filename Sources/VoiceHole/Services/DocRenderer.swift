import Foundation
import CoreText
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Renders a memo as a styled attributed document and paginated PDF.
enum DocRenderer {

    static func attributedDoc(for memo: Memo) -> NSAttributedString {
        let out = NSMutableAttributedString()

        func paragraphStyle(before: CGFloat = 0, after: CGFloat = 6) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.lineHeightMultiple = 1.15
            return p
        }

        func append(_ text: String, font: PlatformFont, color: PlatformColor = .black, before: CGFloat = 0, after: CGFloat = 6) {
            out.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle(before: before, after: after),
            ]))
        }

        append(memo.title, font: .boldSystemFont(ofSize: 22), after: 4)

        var meta = "\(memo.createdAt.formatted(date: .long, time: .shortened))   ·   \(Format.duration(memo.duration))"
        if let lang = memo.language { meta += "   ·   \(Format.languageName(lang))" }
        if let model = memo.modelUsed { meta += "   ·   Whisper \(WhisperModel.label(for: model)) (on-device)" }
        append(meta, font: .systemFont(ofSize: 10), color: .darkGray, after: 16)

        if let summary = memo.summary, !summary.isEmpty {
            append("Summary", font: .boldSystemFont(ofSize: 15), before: 6, after: 6)
            out.append(markdownBody(summary, size: 11))
        }

        if memo.isTranscribed {
            append("Transcript", font: .boldSystemFont(ofSize: 15), before: 16, after: 6)
            for para in DocFormatter.paragraphs(for: memo) {
                let m = NSMutableAttributedString()
                if let start = para.start {
                    m.append(NSAttributedString(string: "[\(Format.timestamp(start))]  ", attributes: [
                        .font: PlatformFont.boldSystemFont(ofSize: 9),
                        .foregroundColor: PlatformColor.gray,
                    ]))
                }
                m.append(NSAttributedString(string: para.text, attributes: [
                    .font: PlatformFont.systemFont(ofSize: 11),
                    .foregroundColor: PlatformColor.black,
                ]))
                m.append(NSAttributedString(string: "\n"))
                m.addAttribute(.paragraphStyle, value: paragraphStyle(after: 8), range: NSRange(location: 0, length: m.length))
                out.append(m)
            }
        }
        return out
    }

    /// Converts simple markdown (bold, bullets) to an attributed string for the PDF.
    private static func markdownBody(_ text: String, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 3
        style.lineHeightMultiple = 1.15

        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "•  " + line.dropFirst(2)
            }
            line = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)

            let parsed = (try? AttributedString(
                markdown: line,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(line)

            for run in parsed.runs {
                let sub = String(parsed[run.range].characters)
                let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
                out.append(NSAttributedString(string: sub, attributes: [
                    .font: isBold ? PlatformFont.boldSystemFont(ofSize: size) : PlatformFont.systemFont(ofSize: size),
                    .foregroundColor: PlatformColor.black,
                    .paragraphStyle: style,
                ]))
            }
            out.append(NSAttributedString(string: "\n", attributes: [
                .font: PlatformFont.systemFont(ofSize: size),
                .paragraphStyle: style,
            ]))
        }
        return out
    }

    /// Paginated US-Letter PDF of the formatted document.
    static func pdfData(for memo: Memo) -> Data {
        let attributed = attributedDoc(for: memo)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textRect = pageRect.insetBy(dx: 60, dy: 60)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var location = 0
        let length = attributed.length

        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            location += max(visible.length, 1)
            ctx.endPDFPage()
        } while location < length

        ctx.closePDF()
        return data as Data
    }
}

// MARK: - Export file documents

struct MarkdownFile: FileDocument {
    static let markdownType = UTType(filenameExtension: "md") ?? .plainText
    static var readableContentTypes: [UTType] { [markdownType, .plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
