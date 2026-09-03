import CoreData

/// CoreDataスタックの管理。基本設計書5.7の通り、実機ではApp Group共有コンテナに
/// ストアを配置しWidget Extensionと共有する想定（Widget Extension自体は別途Xcodeで追加）。
struct PersistenceController {
    static let shared = PersistenceController()

    /// テスト用のin-memoryストア（詳細設計書8.1の単体テストで使用）
    static var preview: PersistenceController = PersistenceController(inMemory: true)

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "BookReader")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.simizuatusi.com.BookReader"
        ) {
            // App Group未設定の環境（このプロジェクトの現状）ではnilになるため、
            // その場合は標準のアプリケーションサポートディレクトリにフォールバックする。
            let storeURL = appGroupURL.appendingPathComponent("BookReader.sqlite")
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error {
                assertionFailure("CoreData store failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
