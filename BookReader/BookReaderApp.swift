//
//  BookReaderApp.swift
//  BookReader
//
//  Created by 清水篤 on 2026/09/04.
//

import SwiftUI
import UserNotifications

@main
struct BookReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let persistence = PersistenceController.shared
    private let bookRepository: BookRepository
    private let adService = AdService()

    init() {
        bookRepository = CoreDataBookRepository(context: PersistenceController.shared.container.viewContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView(bookRepository: bookRepository)
                .task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    _ = await adService.requestATTIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                let backfill = MetadataBackfillService(
                    bookRepository: bookRepository,
                    metadataService: CompositeBookMetadataService()
                )
                await backfill.backfillPendingMetadata()
            }
        }
    }
}
