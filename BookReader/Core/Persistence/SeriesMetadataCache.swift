import CoreData

struct CachedSeriesMetadata {
    let knownTotalVolumes: Int?
    let lastFetchedAt: Date
}

protocol SeriesMetadataCaching {
    func cached(seriesKey: String) throws -> CachedSeriesMetadata?
    func upsert(seriesKey: String, totalVolumes: Int?) throws
}

/// SeriesMetadataCacheEntityへの読み書き。詳細設計書3.2・4.2参照。
final class CoreDataSeriesMetadataCache: SeriesMetadataCaching {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func cached(seriesKey: String) throws -> CachedSeriesMetadata? {
        try context.performAndWait {
            let request = SeriesMetadataCacheEntity.fetchRequest()
            request.predicate = NSPredicate(format: "seriesKey == %@", seriesKey)
            request.fetchLimit = 1
            guard let entity = try context.fetch(request).first else { return nil }
            return CachedSeriesMetadata(
                knownTotalVolumes: entity.knownTotalVolumes?.intValue,
                lastFetchedAt: entity.lastFetchedAt ?? .distantPast
            )
        }
    }

    func upsert(seriesKey: String, totalVolumes: Int?) throws {
        try context.performAndWait {
            let request = SeriesMetadataCacheEntity.fetchRequest()
            request.predicate = NSPredicate(format: "seriesKey == %@", seriesKey)
            request.fetchLimit = 1

            let entity = try context.fetch(request).first ?? SeriesMetadataCacheEntity(context: context)
            entity.seriesKey = seriesKey
            entity.knownTotalVolumes = totalVolumes.map { NSNumber(value: $0) }
            entity.lastFetchedAt = Date()

            if context.hasChanges {
                try context.save()
            }
        }
    }
}
