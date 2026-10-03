import UIKit
import UniformTypeIdentifiers
import StitchCore

/// 分享扩展：接收外部图片，存入 App Group 共享收件箱，并尝试唤起主 App。
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleIncomingItems()
    }

    private func handleIncomingItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            complete()
            return
        }

        let group = DispatchGroup()
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    defer { group.leave() }
                    guard let data else { return }
                    _ = try? SharedInbox.saveImage(data: data, source: "share")
                }
            }
        }

        group.notify(queue: .main) {
            self.openHostApp()
            self.complete()
        }
    }

    private func openHostApp() {
        guard let url = URL(string: "\(AppConstants.urlScheme)://inbox") else { return }
        extensionContext?.open(url, completionHandler: nil)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
