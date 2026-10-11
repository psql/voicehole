import Foundation
import AVFoundation

/// Cuts the tail off a finished recording without re-encoding.
enum AudioTrimmer {
    /// Shortens the file at `url` in place so it ends at `end` seconds.
    /// Uses a passthrough export, so AAC and Apple Lossless samples are
    /// copied verbatim. Returns `false` (leaving the file untouched) when
    /// the cut point isn't meaningfully inside the recording or the export fails.
    @discardableResult
    static func trim(_ url: URL, to end: TimeInterval) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return false }
        let total = CMTimeGetSeconds(duration)
        guard end >= 0.5, end < total - 0.25 else { return false }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return false
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-\(UUID().uuidString).m4a")
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: end, preferredTimescale: 48_000)
        )

        if #available(macOS 15.0, iOS 18.0, *) {
            do { try await session.export(to: temp, as: .m4a) } catch {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
        } else {
            session.outputURL = temp
            session.outputFileType = .m4a
            await session.export()
            guard session.status == .completed else {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } catch {
            // replaceItemAt can refuse across volumes; fall back to a plain swap.
            do {
                try FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: temp, to: url)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
        }
        return true
    }
}
