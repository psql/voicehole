import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject private var transcriber: TranscriptionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Whisper Model")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            List {
                ForEach(WhisperModel.all) { model in
                    row(for: model)
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if case .downloading(let fraction) = transcriber.modelState {
                    ProgressView(value: fraction) {
                        Text("Downloading… \(Int(fraction * 100))%")
                            .font(.caption)
                    }
                }
                Text("Models download once from the Hugging Face CDN and are stored on this device. All transcription runs locally — audio never leaves your machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 480, height: 440)
        #endif
    }

    private func row(for model: WhisperModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: transcriber.selectedModelID == model.id ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.label)
                    .font(.body.weight(.medium))
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if transcriber.isDownloaded(model.id) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.green)
                    .help("Downloaded")
                Button {
                    transcriber.removeDownloadedModel(model.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove downloaded model")
            } else if transcriber.selectedModelID == model.id, case .downloading = transcriber.modelState {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    transcriber.selectModel(model.id)
                    transcriber.downloadSelectedModel()
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Download")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            transcriber.selectModel(model.id)
        }
        .padding(.vertical, 4)
    }
}
