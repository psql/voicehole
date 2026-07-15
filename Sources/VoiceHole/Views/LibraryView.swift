import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var transcriber: TranscriptionService

    @Binding var selection: UUID?
    @Binding var showModelSettings: Bool

    @State private var renamingMemo: Memo?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.memos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No memos yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(store.memos) { memo in
                        MemoRow(memo: memo)
                            .tag(memo.id)
                            .contextMenu {
                                Button {
                                    beginRename(memo)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    Clipboard.copy(DocFormatter.plainTranscript(for: memo))
                                } label: {
                                    Label("Copy Transcript", systemImage: "doc.on.doc")
                                }
                                .disabled(!memo.isTranscribed)
                                Button {
                                    transcriber.enqueue(memo.id)
                                } label: {
                                    Label(memo.isTranscribed ? "Re-transcribe" : "Transcribe", systemImage: "waveform")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    delete(memo)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            #if os(iOS)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(memo)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    beginRename(memo)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }
                            #endif
                    }
                }
            }

            Divider()
            modelFooter
        }
        .alert("Rename Memo", isPresented: .init(
            get: { renamingMemo != nil },
            set: { if !$0 { renamingMemo = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let memo = renamingMemo {
                    store.rename(id: memo.id, to: renameText)
                }
                renamingMemo = nil
            }
            Button("Cancel", role: .cancel) { renamingMemo = nil }
        }
    }

    private var modelFooter: some View {
        Button {
            showModelSettings = true
        } label: {
            HStack(spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 1) {
                    Text("Whisper \(WhisperModel.label(for: transcriber.selectedModelID))")
                        .font(.caption.weight(.medium))
                    Text(transcriber.modelState.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch transcriber.modelState {
        case .ready:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .downloading, .loading:
            ProgressView().controlSize(.mini)
        case .failed:
            Circle().fill(.red).frame(width: 8, height: 8)
        case .notDownloaded:
            Circle().fill(.orange).frame(width: 8, height: 8)
        }
    }

    private func beginRename(_ memo: Memo) {
        renameText = memo.title
        renamingMemo = memo
    }

    private func delete(_ memo: Memo) {
        if selection == memo.id { selection = nil }
        store.delete(memo)
    }
}

struct MemoRow: View {
    @EnvironmentObject private var transcriber: TranscriptionService
    let memo: Memo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(memo.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(Format.duration(memo.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            statusIcon
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if transcriber.currentMemoID == memo.id {
            ProgressView().controlSize(.small)
        } else if transcriber.pending.contains(memo.id) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        } else if memo.isTranscribed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
