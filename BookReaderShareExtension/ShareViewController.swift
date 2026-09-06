import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CoreData
import os.log

private let logger = Logger(subsystem: "simizuatusi.com.BookReader.ShareExtension", category: "ShareViewController")

/// 共有シートのエントリポイント（Info.plistのNSExtensionPrincipalClassから起動される）。
/// 共有されたURLを取り出し、SwiftUI側（ShareExtensionRootView）へ渡す橋渡しのみを担当する。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let bookRepository = CoreDataBookRepository(context: PersistenceController.shared.container.viewContext)

        loadSharedURL { [weak self] url in
            logger.notice("取得したURL: \(url?.absoluteString ?? "nil", privacy: .public)")
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

    /// アフィリエイトタグ付きの商品ページURLが渡された場合はSafariへハンドオフしてから
    /// 拡張を終了する。渡されなければそのまま閉じる。
    /// 実機で確認: 素のURLをそのまま渡すとUniversal LinkによりAmazonアプリへ直接遷移してしまい、
    /// Cookieベースのアフィリエイト計測（tag）が効かない。forcedToOpenInSafariでSafariでの
    /// オープンを強制する。
    private func finish(returningToAmazon url: URL?) {
        guard let url else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        let safariURL = url.forcedToOpenInSafari
        logger.notice("Amazonへ戻るURLを開く: \(safariURL.absoluteString, privacy: .public)")
        extensionContext?.open(safariURL) { [weak self] success in
            logger.notice("Amazonへ戻るopen()の結果: \(success, privacy: .public)")
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Safariの「Webページ」共有では、URLがpublic.url型で直接渡らず、プレーンテキスト型で
    /// 渡ってくる場合がある。想定していた型（public.url）だけを見ていたため
    /// 「認識できませんでした」になっていた不具合の修正（実機で確認、詳細はコメント参照）。
    /// 全アイテム・全添付・複数の型を順に試し、どれも失敗した場合のみ実際に提供された型を
    /// ログへ出す（Console.appで原因追跡できるようにするため）。
    private func loadSharedURL(completion: @escaping (URL?) -> Void) {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []

        guard !attachments.isEmpty else {
            logger.error("共有されたアイテムにattachmentsが存在しない")
            logger.notice("inputItems件数: \(self.extensionContext?.inputItems.count ?? -1, privacy: .public)")
            completion(nil)
            return
        }

        tryLoadURL(from: attachments, index: 0, completion: completion)
    }

    private func tryLoadURL(from attachments: [NSItemProvider], index: Int, completion: @escaping (URL?) -> Void) {
        guard index < attachments.count else {
            let allTypes = attachments.map(\.registeredTypeIdentifiers)
            logger.error("URLを取り出せる型が見つからなかった。提供された型一覧: \(String(describing: allTypes), privacy: .public)")
            completion(nil)
            return
        }

        let attachment = attachments[index]
        let next = { [weak self] in self?.tryLoadURL(from: attachments, index: index + 1, completion: completion) }

        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    completion(url)
                } else {
                    next()
                }
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String, let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
                    completion(url)
                } else {
                    next()
                }
            }
        } else {
            next()
        }
    }
}
