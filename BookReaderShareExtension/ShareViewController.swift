import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CoreData

/// 共有シートのエントリポイント（Info.plistのNSExtensionPrincipalClassから起動される）。
/// 共有されたURLを取り出し、SwiftUI側（ShareExtensionRootView）へ渡す橋渡しのみを担当する。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let bookRepository = CoreDataBookRepository(context: PersistenceController.shared.container.viewContext)

        loadSharedURL { [weak self] url in
            DispatchQueue.main.async {
                self?.presentRootView(sharedURL: url, bookRepository: bookRepository)
            }
        }
    }

    private func presentRootView(sharedURL: URL?, bookRepository: BookRepository) {
        let rootView = ShareExtensionRootView(
            bookRepository: bookRepository,
            sharedURL: sharedURL
        ) { [weak self] returnURL in
            self?.finish(returningToAmazon: returnURL)
        }
        let hosting = UIHostingController(rootView: rootView)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    /// アフィリエイトタグ付きの商品ページURLが渡された場合はAmazon（アプリ or Safari）へ
    /// ハンドオフしてから拡張を終了する。渡されなければそのまま閉じる。
    private func finish(returningToAmazon url: URL?) {
        guard let url else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func loadSharedURL(completion: @escaping (URL?) -> Void) {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachment = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else {
            completion(nil)
            return
        }
        attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
            completion(item as? URL)
        }
    }
}
