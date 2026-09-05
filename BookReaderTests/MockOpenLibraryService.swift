import Foundation
@testable import BookReader

final class MockOpenLibraryService: BookMetadataFetching {
    var metadataByISBN: [String: BookMetadata] = [:]
    var seriesVolumeCountByName: [String: Int] = [:]
    private(set) var fetchedISBNs: [String] = []

    func fetchMetadata(isbn: String) async throws -> BookMetadata {
        fetchedISBNs.append(isbn)
        guard let metadata = metadataByISBN[isbn] else {
            throw OpenLibraryError.notFound
        }
        return metadata
    }

    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        seriesVolumeCountByName[seriesName]
    }
}
