import Foundation
@testable import BookReader

final class MockOpenLibraryService: OpenLibraryFetching {
    var metadataByISBN: [String: OpenLibraryBookMetadata] = [:]
    var seriesVolumeCountByName: [String: Int] = [:]
    private(set) var fetchedISBNs: [String] = []

    func fetchMetadata(isbn: String) async throws -> OpenLibraryBookMetadata {
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
