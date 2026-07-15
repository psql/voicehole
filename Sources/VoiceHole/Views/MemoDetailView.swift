import SwiftUI

struct MemoDetailView: View {
    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var transcriber: TranscriptionService
    @StateObject private var player = AudioPlayer()

    let memoID: UUID

    @State private var tab: DocTab = .transcript
    @State private var titleDraft = ""
    @State private var exportingMarkdown = false
    @State private var exportingPDF = false
    @State private var exportError: String?

    enum DocTab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case summary = "Summary"
        case doc = "Doc"
        var id: String { rawValue }
    }

    private var memo: Memo? { store.memo(id: memoID) }
    private var isTranscribingThis: Bool { transcriber.currentMemoID == memoID }
    private var isQueued: Bool { transcriber.pending.contains(memoID) }

    var body: some View {
        if let memo {
            VStack(spacing: 0) {
                header(memo)
                Divider()
                controls(memo)
                Divider()
                content(memo)
            }
            .onAppear { loadMemo(memo) }
            .onChange(of: memoID) {
                if let m = self.memo { loadMemo(m) }
            }
            .fileExporter(
                isPresented: $exportingMarkdown,
                document: MarkdownFile(text: DocFormatter.markdown(for: memo)),
                contentType: MarkdownFile.markdownType,
                defaultFilename: memo.title
            ) { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .fileExporter(
                isPresented: $exportingPDF,
                document: PDFFile(data: DocRenderer.pdfData(for: memo)),
                contentType: .pdf,
                defaultFilename: memo.title
            ) { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        } else {
            Text("Memo not found")
                .foregroundStyle(.secondary)
        }
    }

    private func loadMemo(_ memo: Memo) {
        titleDraft = memo.title
        player.load(url: store.audioURL(for: memo))
        tab = .transcript
    }

    // MARK: - Header

    private func header(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .onSubmit { store.rename(id: memo.id, to: titleDraft) }

            HStack(spacing: 12) {
                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(Format.duration(memo.duration))
                if let lang = memo.language {
                    Text("·")
                    Text(Format.languageName(lang))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                Text(Format.timestamp(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Slider(
                    value: .init(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )

                Text(Format.timestamp(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Controls

    private func controls(_ memo: Memo) -> some View {
        HStack {
            Picker("View", selection: $tab) {
                ForEach(DocTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)

            Spacer()

            Menu {
                Button("Copy Transcript") { Clipboard.copy(DocFormatter.plainTranscript(for: memo)) }
                    .disabled(!memo.isTranscribed)
                Button("Copy Summary") { Clipboard.copy(memo.summary ?? "") }
                    .disabled((memo.summary ?? "").isEmpty)
                Button("Copy Doc as Markdown") { Clipboard.copy(DocFormatter.markdown(for: memo)) }
                    .disabled(!memo.isTranscribed)
                Divider()
                Button("Export Markdown File…") { exportingMarkdown = true }
                    .disabled(!memo.isTranscribed)
                Button("Export PDF…") { exportingPDF = true }
                    .disabled(!memo.isTranscribed)
            } label: {
                Label("Copy / Export", systemImage: "square.and.arrow.up.on.square")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            CopyButton(label: "Copy \(tab.rawValue)") { currentTabText(memo) }

            if memo.isTranscribed {
                ShareLink(item: DocFormatter.markdown(for: memo)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func currentTabText(_ memo: Memo) -> String? {
        switch tab {
        case .transcript: return memo.isTranscribed ? DocFormatter.plainTranscript(for: memo) : nil
        case .summary: return memo.summary
        case .doc: return memo.isTranscribed ? DocFormatter.markdown(for: memo) : nil
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ memo: Memo) -> some View {
        if isTranscribingThis {
            transcribingView
        } else if !memo.isTranscribed {
            notTranscribedView(memo)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .transcript:
                        ForEach(Array(DocFormatter.paragraphs(for: memo).enumerated()), id: \.offset) { _, p in
                            VStack(alignment: .leading, spacing: 3) {
                                if let start = p.start {
                                    Text(Format.timestamp(start))
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                                Text(p.text)
                                    .textSelection(.enabled)
                            }
                        }
                    case .summary:
                        if let summary = memo.summary, !summary.isEmpty {
                            Text(markdownAttributed(summary))
                                .textSelection(.enabled)
                        } else {
                            VStack(spacing: 12) {
                                Text("No summary yet.")
                                    .foregroundStyle(.secondary)
                                Button("Generate Summary") { regenerateSummary(memo) }
                                    .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    case .doc:
                        DocPreviewView(memo: memo)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: 14) {
            if transcriber.progressFraction <= 0.001 {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing audio…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView(value: min(max(transcriber.progressFraction, 0), 1)) {
                    Text("Transcribing on-device… \(percentLabel)")
                        .font(.callout)
                }
                .frame(maxWidth: 420)
            }

            if !transcriber.liveText.isEmpty {
                ScrollView {
                    Text(transcriber.liveText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var percentLabel: String {
        let percent = transcriber.progressFraction * 100
        return percent < 1 ? "<1%" : "\(Int(percent))%"
    }

    private func notTranscribedView(_ memo: Memo) -> some View {
        VStack(spacing: 14) {
            if isQueued {
                ProgressView()
                Text("Waiting to transcribe…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "text.quote")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Not transcribed yet")
                    .font(.headline)
                Button {
                    transcriber.enqueue(memo.id)
                } label: {
                    Label("Transcribe", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
            }

            if transcriber.modelState != .ready {
                ModelStatusCard()
                    .frame(maxWidth: 420)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func regenerateSummary(_ memo: Memo) {
        guard let transcript = memo.transcript, !transcript.isEmpty else { return }
        Task {
            let summary = await SummaryService.summarize(transcript, title: memo.title)
            store.setSummary(id: memo.id, summary: summary)
        }
    }

    private func markdownAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

struct CopyButton: View {
    let label: String
    let text: () -> String?
    @State private var copied = false

    var body: some View {
        Button {
            guard let value = text(), !value.isEmpty else { return }
            Clipboard.copy(value)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? "Copied!" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .disabled((text() ?? "").isEmpty)
    }
}
