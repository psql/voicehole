import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ModelSettingsView: View {
    @EnvironmentObject private var transcriber: TranscriptionService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recordingSettings = RecordingSettings.shared
    #if os(macOS)
    @ObservedObject private var meetingSettings = MeetingSettings.shared
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            List {
                Section("Whisper Model") {
                    ForEach(WhisperModel.all) { model in
                        row(for: model)
                    }
                }
                recordingSection
                #if os(macOS)
                meetingsSection
                #endif
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
        .frame(width: 480, height: 580)
        #endif
    }

    private var recordingSection: some View {
        Section("Recording") {
            Picker("Stop after silence", selection: $recordingSettings.silenceTimeout) {
                ForEach(RecordingSettings.silenceTimeoutOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            Text("If nothing is heard for this long, the recording ends on its own and the silent tail is trimmed off the memo. Applies to mic memos and meeting recordings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    #if os(macOS)
    private var meetingsSection: some View {
        Section("Meetings") {
            Toggle("Detect meetings and suggest recording", isOn: $meetingSettings.detectMeetings)
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save meeting recordings to")
                HStack(spacing: 8) {
                    Text(recordingsFolderDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !meetingSettings.recordingsPath.isEmpty {
                        Button("Reset") { meetingSettings.recordingsPath = "" }
                            .controlSize(.small)
                    }
                    Button("Choose…") { chooseRecordingsFolder() }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 2)

            Text("Meeting recordings capture system audio plus your mic as Apple Lossless (.m4a) and are also added to the library for transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingsFolderDisplay: String {
        let path = meetingSettings.recordingsPath.isEmpty
            ? MeetingSettings.defaultFolderURL.path
            : meetingSettings.recordingsPath
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseRecordingsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = meetingSettings.recordingsFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            meetingSettings.recordingsPath = url.path
        }
    }
    #endif

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
