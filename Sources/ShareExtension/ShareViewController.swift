import UIKit
import UniformTypeIdentifiers

/// Receives audio files from the share sheet and drops them into the App Group
/// inbox. The main app imports and transcribes them on next launch/foreground.
final class ShareViewController: UIViewController {
    static let appGroupID = "group.com.altbizney.voicehole"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleAttachments()
    }

    private func handleAttachments() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) }

        guard !providers.isEmpty,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            complete()
            return
        }

        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                // Unique subfolder so the original filename (used as the memo
                // title) is preserved without collisions.
                let dir = inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                // Must copy synchronously: the temp file dies when this callback returns.
                try? FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(url.lastPathComponent))
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.complete()
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
