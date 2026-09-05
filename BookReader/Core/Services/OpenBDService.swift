import Foundation

enum OpenBDError: Error, Equatable {
    case notFound
    case timeout
    case decodingFailed
    case network(String)
}

/// openBD（https://openbd.jp/）連携。版元ドットコムのデータを無料・APIキー不要で提供する、
/// 日本の書籍に強い書誌データAPI。Open Libraryは日本の書籍の網羅性が低いため
/// （要件定義書14章のリスク）、実際のスキャン対象（和書）に対してこちらを優先データソースとする。
final class OpenBDService: BookMetadataFetching {
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

    func fetchMetadata(isbn: String) async throws -> BookMetadata {
        guard var components = URLComponents(string: "https://api.openbd.jp/v1/get") else {
            throw OpenBDError.decodingFailed
        }
        components.queryItems = [URLQueryItem(name: "isbn", value: isbn)]
        guard let url = components.url else { throw OpenBDError.decodingFailed }

        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw OpenBDError.timeout
            }
            throw OpenBDError.network(error.localizedDescription)
        }

        guard
            let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let first = array.first,
            let entry = first as? [String: Any],
            let summary = entry["summary"] as? [String: Any],
            let title = summary["title"] as? String,
            !title.isEmpty
        else {
            throw OpenBDError.notFound
        }

        let cover = (summary["cover"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let seriesName = (summary["series"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let volumeNumber = (summary["volume"] as? String).flatMap { $0.isEmpty ? nil : Int($0) }
        return BookMetadata(title: title, coverImageURL: cover, seriesName: seriesName, volumeNumber: volumeNumber)
    }

    /// openBDには既刊総数の推定に使えるシリーズ横断検索APIがないため未対応。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        nil
    }
}
