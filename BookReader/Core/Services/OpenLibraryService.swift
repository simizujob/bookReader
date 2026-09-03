import Foundation

struct OpenLibraryBookMetadata: Equatable {
    let title: String
    let coverImageURL: String?
}

enum OpenLibraryError: Error, Equatable {
    case notFound
    case timeout
    case decodingFailed
    case network(String)
}

protocol OpenLibraryFetching {
    func fetchMetadata(isbn: String) async throws -> OpenLibraryBookMetadata
    /// 既刊総数の暫定推定値。Open Libraryは構造化フィールドを提供しないため、
    /// 検索結果件数を暫定的な既刊総数とみなす（詳細設計書4.7参照、要件定義書14章のリスクを踏まえた暫定ロジック）。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int?
}

/// 詳細設計書4.7参照。無料・APIキー不要。
final class OpenLibraryService: OpenLibraryFetching {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchMetadata(isbn: String) async throws -> OpenLibraryBookMetadata {
        guard var components = URLComponents(string: "https://openlibrary.org/api/books") else {
            throw OpenLibraryError.decodingFailed
        }
        components.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data")
        ]
        guard let url = components.url else { throw OpenLibraryError.decodingFailed }

        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw OpenLibraryError.timeout
            }
            throw OpenLibraryError.network(error.localizedDescription)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entry = json["ISBN:\(isbn)"] as? [String: Any],
            let title = entry["title"] as? String
        else {
            throw OpenLibraryError.notFound
        }

        let coverURL = (entry["cover"] as? [String: Any])?["medium"] as? String
        return OpenLibraryBookMetadata(title: title, coverImageURL: coverURL)
    }

    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        guard var components = URLComponents(string: "https://openlibrary.org/search.json") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "q", value: seriesName)]
        guard let url = components.url else { return nil }

        guard let (data, _) = try? await session.data(from: url) else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let numFound = json["numFound"] as? Int,
            numFound > 0
        else {
            return nil
        }
        return numFound
    }
}
