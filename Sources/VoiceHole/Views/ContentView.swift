import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var transcriber: TranscriptionService
    @EnvironmentObject private var recorder: RecorderService
    #if os(macOS)
    @ObservedObject private var meetingDetector = MeetingDetector.shared
    #endif

    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: UUID?
    @State private var showImporter = false
    @State private var showModelSettings = false
    @State private var dropTargeted = false
    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection, showModelSettings: $showModelSettings)
                .navigationTitle("VoiceHole")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        recordElapsedLabel
                        recordButton
                        #if os(macOS)
                        recordMeetingButton
                        #endif
                        deviceMenu
                        importButton
                    }
                }
                .onAppear { recorder.refreshDevices() }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290)
                #endif
        } detail: {
            if let id = selection, store.memo(id: id) != nil {
                MemoDetailView(memoID: id)
            } else {
                EmptyStateView(showImporter: $showImporter)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                DropOverlay()
            }
        }
        .overlay {
            if recorder.isRecording {
                RecordingOverlay()
                    .transition(.opacity)
            }
        }
        #if os(macOS)
        .overlay(alignment: .bottom) {
            if let appName = meetingDetector.meetingApp,
               !meetingDetector.bannerDismissed,
               !recorder.isRecording {
                MeetingBanner(
                    appName: appName,
                    onRecord: startMeetingRecording,
                    onDismiss: { meetingDetector.bannerDismissed = true }
                )
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: meetingDetector.meetingApp)
        .onReceive(NotificationCenter.default.publisher(for: .voiceholeRecordMeeting)) { _ in
            startMeetingRecording()
        }
        #endif
        .animation(.easeInOut(duration: 0.25), value: recorder.isRecording)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .onOpenURL { url in
            importFiles([url])
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceholeImport)) { _ in
            showImporter = true
        }
        .sheet(isPresented: $showModelSettings) {
            ModelSettingsView()
                .environmentObject(transcriber)
        }
        .alert("Import Failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Transcription Error", isPresented: .init(
            get: { transcriber.lastError != nil },
            set: { if !$0 { transcriber.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriber.lastError ?? "")
        }
        .alert("Recording Error", isPresented: .init(
            get: { recorder.lastError != nil },
            set: { if !$0 { recorder.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.lastError ?? "")
        }
        .task {
            recorder.onFinish = { url in
                importFiles([url])
                // Mic memos land in a temp file that's spent after import;
                // meeting recordings stay in the user's configured folder.
                if url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            #if os(macOS)
            meetingDetector.isSelfRecording = { [weak recorder] in
                recorder?.isRecording ?? false
            }
            #endif
            importFromShareInbox()
            await transcriber.warmIfDownloaded()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { importFromShareInbox() }
        }
    }

    @ViewBuilder
    private var recordElapsedLabel: some View {
        if recorder.isRecording {
            Text(Format.timestamp(recorder.elapsed))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.red)
        }
    }

    private var recordButton: some View {
        Button {
            recorder.toggle()
        } label: {
            Label(
                recorder.isRecording ? "Stop Recording" : "Record",
                systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle"
            )
            .foregroundStyle(.red)
        }
        .help(recorder.isRecording ? "Stop recording" : "Record a new memo (⌘R)")
        .keyboardShortcut("r", modifiers: .command)
    }

    #if os(macOS)
    private var recordMeetingButton: some View {
        Button {
            startMeetingRecording()
        } label: {
            Label("Record Meeting", systemImage: "rectangle.inset.filled.badge.record")
        }
        .disabled(recorder.isRecording)
        .help("Record system audio + mic for meeting notes (⇧⌘R)")
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    private func startMeetingRecording() {
        guard !recorder.isRecording else { return }
        meetingDetector.bannerDismissed = true
        Task { await recorder.startMeeting() }
    }
    #endif

    private var deviceMenu: some View {
        Menu {
            Picker("Input Device", selection: $recorder.selectedDeviceID) {
                Text("System Default").tag(String?.none)
                ForEach(recorder.devices) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
            }
            #if os(macOS)
            Divider()
            Button {
                startMeetingRecording()
            } label: {
                Label("Record System Audio + Mic", systemImage: "speaker.wave.2.fill")
            }
            #endif
        } label: {
            Label("Input Device", systemImage: "mic")
        }
        .disabled(recorder.isRecording)
        .help("Choose recording device")
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            Label("Import Audio", systemImage: "plus")
        }
        .help("Import an audio file (⌘I)")
    }

    private func importFromShareInbox() {
        let imported = store.processShareInbox()
        for memo in imported { transcriber.enqueue(memo.id) }
        if let first = imported.first { selection = first.id }
    }

    private func importFiles(_ urls: [URL]) {
        var firstImported: UUID?
        for url in urls where url.isFileURL {
            do {
                let memo = try store.importAudio(from: url)
                transcriber.enqueue(memo.id)
                if firstImported == nil { firstImported = memo.id }
            } catch {
                importError = "Couldn't import “\(url.lastPathComponent)”: \(error.localizedDescription)"
            }
        }
        if let id = firstImported { selection = id }
    }
}

#if os(macOS)
/// Bottom-of-window suggestion shown while a meeting looks active.
struct MeetingBanner: View {
    let appName: String
    let onRecord: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.wave.2.fill")
                .foregroundStyle(.tint)
            Text(appName == "your browser"
                 ? "Looks like you're in a call."
                 : "Looks like you're in a \(appName) call.")
                .font(.callout)

            Button(action: onRecord) {
                Label("Record Meeting", systemImage: "record.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss for this meeting")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(radius: 8, y: 2)
    }
}
#endif

struct DropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(0.12))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [10, 6]))
            Label("Drop to import", systemImage: "waveform.badge.plus")
                .font(.title2.weight(.semibold))
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(10)
        .allowsHitTesting(false)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var transcriber: TranscriptionService
    @EnvironmentObject private var recorder: RecorderService
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Record or drop a voice memo")
                .font(.title2.weight(.semibold))
            Text("Hit record, drag audio files in (⌘I), or share from Voice Memos.\nEverything is transcribed on this device — nothing leaves it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    recorder.toggle()
                } label: {
                    Label("Record", systemImage: "record.circle.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)

                Button {
                    showImporter = true
                } label: {
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if transcriber.modelState != .ready {
                ModelStatusCard()
                    .frame(maxWidth: 420)
                    .padding(.top, 8)
            }
        }
        .padding(40)
    }
}

struct ModelStatusCard: View {
    @EnvironmentObject private var transcriber: TranscriptionService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Whisper Model", systemImage: "cpu")
                .font(.headline)

            switch transcriber.modelState {
            case .notDownloaded:
                Text("Download the \(WhisperModel.label(for: transcriber.selectedModelID)) model once to start transcribing. It's fetched from the Hugging Face CDN and then runs fully offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    transcriber.downloadSelectedModel()
                } label: {
                    Label("Download Model", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading \(WhisperModel.label(for: transcriber.selectedModelID)) model… \(Int(fraction * 100))%")
                        .font(.callout)
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading model…").font(.callout)
                }
            case .ready:
                Label("Ready — transcription runs on-device", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                Button("Try Again") {
                    transcriber.downloadSelectedModel()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
