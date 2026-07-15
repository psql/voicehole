# VoiceHole

A universal (macOS + iOS) SwiftUI app that transcribes voice memos entirely on-device with Whisper.

## Features

- **Record** — ⌘R or the toolbar record button, with a mic-device picker. While recording, a full-screen overlay shows a loudness-reactive Perlin-rippled orb visualizer (silence = gone, loud = large and warbly) with a pulsing REC indicator.
- **Import** — drag audio files into the window, press ⌘I, drop onto the Dock icon, or share from Voice Memos on iOS (share extension drops files into the App Group inbox; the app imports them on next foreground).
- **Local transcription** — [WhisperKit](https://github.com/argmaxinc/WhisperKit) running CoreML Whisper models. Audio never leaves the device.
- **Quick install** — the app ships tiny; Whisper models (Tiny / Base / Small / Large Turbo) download once from the Hugging Face CDN and are cached locally. Switch models in the gear menu at the bottom of the sidebar.
- **Summary** — generated on-device with Apple Intelligence (Foundation Models) when available, with a local extractive fallback.
- **Copy anything** — plain transcript, summary, or a formatted markdown doc with metadata and timestamped paragraphs.
- **Library** — memos are saved into the app's library with playback, rename (context menu or click the title), and delete. On iOS the library lives in the app's Documents folder, visible in the Files app.

## Building

Requires Xcode 26+. The project is generated with [xcodegen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
# macOS
xcodebuild -project VoiceHole.xcodeproj -scheme VoiceHole -configuration Release build
# iOS (set your signing team in Xcode first for device installs)
open VoiceHole.xcodeproj   # select the VoiceHole-iOS scheme and run
```

Both targets share all sources under `Sources/VoiceHole`. The app icon is rendered by `scripts/genicon.swift`.

## Storage

- macOS: `~/Library/Application Support/VoiceHole/` (audio in `Memos/`, index in `memos.json`, models in `Models/`)
- iOS: app Documents directory (file-sharing enabled)
