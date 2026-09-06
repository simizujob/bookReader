import Foundation

enum NDLSearchError: Error, Equatable {
    case notFound
    case timeout
    case decodingFailed
    case network(String)
}

/// Kindle版等、ISBNを持たないAmazon商品ページから紙の本を再検索するための最小限の窓口。
/// 共有シート機能（買う前チェック）専用。
protocol PaperEditionSearching {
    func searchPaperEditionISBN(titleHint: String) async -> String?
}

/// タイトルの手掛かりを1件のISBNへ自動確定せず、候補を複数返してユーザーに選ばせる窓口。
/// 買う前チェック画面のタイトル検索（Amazonを開かずに本のタイトルだけで判定したい場合）で使用する。
///
/// Google Books APIへの切り替えを試したが、日本の漫画データの大半がISBNを持たず
/// （Google Playブックス独自の商品コードのみ）判定に使えないことが実データで判明したため、
/// NDL Search（ISBNデータの網羅性・正確性が本質的に高い）に戻した。
struct TitleSearchCandidate: Equatable, Identifiable {
    let isbn: String
    let title: String
    let creator: String?
    /// シリーズものの場合の巻数表示（例: "5巻"）。単行本等、巻数が無い/読み取れない場合はnil。
    let volumeLabel: String?
    var id: String { isbn }
}

protocol TitleSearching {
    func searchCandidates(title: String) async throws -> [TitleSearchCandidate]
}

/// 国立国会図書館サーチ（https://ndlsearch.ndl.go.jp/）連携。
/// 国内で出版される書籍は国立国会図書館法により納本が義務付けられているため、
/// openBD・Open Libraryよりもさらに網羅性が高い（無料・APIキー不要）。
/// 巻数（dcndl:volume）を構造化フィールドとして提供するため、TitleParserによる
/// タイトル文字列からの推定よりも信頼できる。ただし表紙画像は提供されない。
///
/// 巻数の表記はNDL内でも統一されておらず多数のバリエーションが存在する（NDLVolumeParser参照）。
/// 安全と判断できるパターンのみを許可リスト化し、それ以外は「不明」として扱う
/// ベストエフォート方針を採る（要件定義書14章・詳細設計書9章参照）。
final class NDLSearchService: BookMetadataFetching, PaperEditionSearching, TitleSearching {
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
        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            throw NDLSearchError.decodingFailed
        }
        components.queryItems = [URLQueryItem(name: "isbn", value: isbn)]
        guard let url = components.url else { throw NDLSearchError.decodingFailed }

        let data = try await fetchData(from: url)
        let items = NDLResponseParser().parseAll(data).filter(\.isBook)
        guard let title = Self.preferredTitle(among: items), !title.isEmpty else {
            throw NDLSearchError.notFound
        }

        // 同一ISBNに対しNDLが新旧複数のレコードを重複して持つことがある（例: 1998年刊行の
        // HUNTER×HUNTER 1巻は、巻数が数字で入った並列タイトル表記のレコードと、シリーズ内の
        // 他の巻と同じ体裁のタイトルを持つレコードが別々に存在する）。片方だけを見ると、
        // タイトル表記のズレでシリーズが分裂したり、巻数が取得できなかったりするため、
        // 全レコードを横断してタイトル・巻数それぞれ最も使えるものを選ぶ。
        guard let parsed = items.lazy.compactMap({ $0.volume.flatMap(NDLVolumeParser.parse) }).first else {
            return BookMetadata(title: title)
        }

        // 「第1部[2]」のように部単位で巻数が振り直されるシリーズは、部ごとに別シリーズとして扱う
        // （そうしないと部をまたいで同じ巻数が重複し、既刊数判定が意味を成さなくなるため）。
        let seriesName = parsed.part.map { "\(title) 第\($0)部" } ?? title
        // 上巻/中巻/下巻のように同じ巻数を複数の本が共有する場合は、タイトル末尾にマーカーを
        // 残しておく（SeriesProgressCalculatorが本棚の巻一覧で見分けられるようにするため）。
        let volumeLabel = parsed.marker.map { "\(parsed.number)(\($0))" } ?? "\(parsed.number)"
        return BookMetadata(
            title: "\(seriesName) \(volumeLabel)",
            seriesName: seriesName,
            volumeNumber: parsed.number
        )
    }

    /// NDLの並列タイトル表記（例: "Hunter×hunter = ハンター ハンター"）はISBD形式の代替タイトル
    /// 併記であり、シリーズ内の他の巻とは異なる正規化キーになってしまう。並列表記でないタイトルを
    /// 持つレコードが他にあればそちらを優先し、なければ先頭のレコードにフォールバックする。
    private static func preferredTitle(among items: [NDLResponseParser.Item]) -> String? {
        let titles = items.compactMap(\.title).filter { !$0.isEmpty }
        return titles.first { !$0.contains(" = ") } ?? titles.first
    }

    /// 既刊総数のベストエフォート推定。タイトルで検索し、タイトルが完全一致かつ巻数が
    /// NDLVolumeParserで安全と判断できる表記の項目を集める。
    ///
    /// 著者名によるクエリ絞り込みは検証の結果採用しないことにした（生データの読点・生年付記・
    /// 異体字などの表記ゆれが原因で、プログラム的に正しいクエリを組み立てられないことを確認済み）。
    /// 絞り込みなしでは1ページに無関係な関連商品が混ざり、本来の巻が歯抜けで取得されることがある
    /// （例: 1,10〜17巻しか取れず本来23巻あるようなケース）。特にタイトルが一般的な単語と
    /// 被る作品（"ONE PIECE"＝洋服の意でもある等）では、無関係な文献で埋まり単行本が
    /// 1件もヒットしないことを実データで確認した。このアプリはF-05を漫画のみ対象としている
    /// （要件定義書参照）ため、NDLの分類コード（NDC）で漫画区分「726.1」に絞り込むことで、
    /// 無関係な文献・関連グッズ・アニメ円盤等を大幅に除外できる（実データで検証済み）。
    ///
    /// それでも長期連載作品（ONE PIECE等）は既刊数がcnt=200件の枠を超えてしまい、
    /// 実際は115巻まで連番で存在するのに91巻以降が取得できず既刊数「不明」になる不具合を
    /// 実データで確認したため、cnt=500まで引き上げている（NDLは500件までは応答することを確認済み。
    /// 1000件では応答が空になった）。
    ///
    /// 既刊総数は**1巻から連続して確認できた最大巻**を採用する（例: 1〜16巻が確認でき17巻だけ
    /// 欠けている場合は16を返す）。18巻のように欠番の先に単発でヒットする巻は、そのISBNだけ
    /// 別レコードでたまたま見つかっただけの可能性があり信頼できないため切り捨てる。
    /// 1巻自体が見つからない場合は連続区間の起点が無く判断できないため不明（nil）とする。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> SeriesVolumeCountResult? {
        // 「本好きの下剋上 第1部」のような部分割シリーズ名は、NDL側のdc:titleには「部」を
        // 含まないため、検索クエリには部を除いた元のシリーズ名を使い、結果は対象の部の
        // レコードのみに絞り込む。
        let (queryTitle, targetPart) = Self.splitPartSuffix(seriesName)

        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: queryTitle),
            URLQueryItem(name: "ndc", value: "726.1"),
            URLQueryItem(name: "cnt", value: "500")
        ]
        guard let url = components.url, let data = try? await fetchData(from: url) else { return nil }

        // タイトルの完全一致（==）は大文字小文字・全角半角等の些細な表記差でも不一致になり、
        // 同じシリーズなのに既刊数が「不明」になる不具合の原因だった。SeriesKeyNormalizerによる
        // 正規化後の比較にすることで、表記ゆれを吸収する。
        let normalizedTarget = SeriesKeyNormalizer.normalize(queryTitle)
        var matches: [(parsed: NDLVolumeParser.Result, isbn: String?)] = []
        for item in NDLResponseParser().parseAll(data) where item.isBook { // アニメ円盤・CD等、無関係なメディアを除外する
            guard item.title.map(SeriesKeyNormalizer.normalize) == normalizedTarget else { continue }
            guard let parsed = item.volume.flatMap(NDLVolumeParser.parse), parsed.part == targetPart else { continue }
            matches.append((parsed, item.isbn))
        }

        // 同じタイトルのまま独自の巻数体系を持つ別編集（総集編・アニメコミックス等）が
        // 混在することがある（実データでONE PIECEの「SJR」総集編を確認済み。本来の115巻とは
        // 無関係な1〜23巻の独自ナンバリングを持ち、副題付きの裸数字表記「1 (東の海編)」等で
        // 登録されている）。本来の単行本は「巻」付き表記（isExplicitCounter）が例外なく
        // 使われている一方、別編集側は「巻」なし表記しか使わないため、「巻」付き表記が
        // 1件でも見つかったタイトルでは、「巻」なし表記の項目を別編集とみなして除外する。
        // 「巻」付き表記が1件も無いタイトル（ゴールデンカムイ等、裸数字表記のみを使う作品）では
        // 従来通り全件を信頼する。
        let hasExplicitCounter = matches.contains { $0.parsed.isExplicitCounter }
        let trustedMatches = matches.filter { !hasExplicitCounter || $0.parsed.isExplicitCounter }

        var volumes: Set<Int> = []
        var isbnsByVolume: [Int: String] = [:]
        for (parsed, isbn) in trustedMatches {
            volumes.insert(parsed.number)
            if let isbn, isbnsByVolume[parsed.number] == nil {
                isbnsByVolume[parsed.number] = isbn
            }
        }
        guard let total = Self.longestConsecutiveRun(from: volumes) else { return nil }
        // 「1巻から連続して確認できた最大巻」より先の巻（信頼していない範囲）のISBNは持ち出さない。
        let trustedISBNs = isbnsByVolume.filter { $0.key <= total }
        return SeriesVolumeCountResult(total: total, isbnsByVolume: trustedISBNs)
    }

    /// Kindle版ASINなどISBN変換に失敗した場合、Amazon商品ページURLから推測したタイトルで
    /// NDLを再検索し、紙の本の候補を探す（ベストエフォート）。タイトルの手掛かりはURLの
    /// スラグから機械的に切り出したものに過ぎず精度が低いため、実際の書誌タイトルとの類似度が
    /// 十分に高い候補が1件見つかった場合のみそのISBNを返す。曖昧な場合はnilを返し、
    /// 呼び出し側が「紙の商品ページを共有してください」等のフォールバック表示を行う。
    func searchPaperEditionISBN(titleHint: String) async -> String? {
        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: titleHint),
            URLQueryItem(name: "cnt", value: "20")
        ]
        guard let url = components.url, let data = try? await fetchData(from: url) else { return nil }

        let best = NDLResponseParser().parseAll(data)
            .filter(\.isBook)
            .compactMap { item -> (isbn: String, similarity: Double)? in
                guard let title = item.title, let isbn = item.isbn else { return nil }
                return (isbn, TitleMatcher.similarity(titleHint, title))
            }
            .max { $0.similarity < $1.similarity }

        guard let best, best.similarity >= 0.85 else { return nil }
        return best.isbn
    }

    /// 明らかに無関係と判断して除外する関連度スコアの下限。
    private static let minimumTitleSearchRelevance = 0.3

    /// タイトルで検索し、ISBNが分かる候補を返す（重複ISBNは除外）。
    /// Amazonを開かず、思い出したタイトルだけで買う前チェックしたい場合に使用する。
    /// 表紙画像は提供されないため、著者名・巻数を添えてユーザーが候補を見分けられるようにする。
    ///
    /// 実機で確認: NDLのタイトル検索は関連度順ではなく、別の基準（タイトル文字列順と思われる）
    /// で返ってくる。「ワンピース」のように一般的な単語と被る作品名（洋服の意味でもある）では、
    /// 漫画区分（NDC 726.1）で絞り込まないと無関係な文献に埋め尽くされ、cnt=500まで見ても
    /// 本来の作品が1件も出てこないことを実データで確認した。一方でNDCを絞り込み条件にして
    /// 除外してしまうと、漫画以外の本（小説等）がタイトル検索で見つからなくなってしまう。
    /// そこで「漫画区分の検索結果を優先して上位に、それ以外はその後ろに」という2回検索・
    /// マージ方式にした（除外ではなく並べ替えの優先度として扱う）。同点の場合は巻数が
    /// 判明している候補（実際にシリーズの1冊として管理できるもの）を、画集・ガイドブック等
    /// 巻数の無い関連本より優先する。
    ///
    /// 2回の問い合わせのうち一方が失敗しても、成功した方の結果は返す（ベストエフォート）。
    /// 両方失敗した場合のみエラーを投げ、呼び出し側が「本当に0件」と「通信エラー」を
    /// 区別できるようにする。
    func searchCandidates(title: String) async throws -> [TitleSearchCandidate] {
        async let mangaScored = try? fetchScoredCandidates(title: title, ndc: "726.1")
        async let generalScored = try? fetchScoredCandidates(title: title, ndc: nil)
        let manga = await mangaScored
        let general = await generalScored

        guard manga != nil || general != nil else {
            throw NDLSearchError.network("タイトル検索に失敗しました")
        }

        let mangaCandidates = (manga ?? []).sorted(by: Self.isHigherPriority).map(\.candidate)
        let mangaISBNs = Set(mangaCandidates.map(\.isbn))
        let otherCandidates = (general ?? [])
            .filter { !mangaISBNs.contains($0.candidate.isbn) }
            .sorted(by: Self.isHigherPriority)
            .map(\.candidate)

        return mangaCandidates + otherCandidates
    }

    /// スコア降順。同点の場合は巻数が判明している候補を優先する。
    private static func isHigherPriority(
        _ lhs: (candidate: TitleSearchCandidate, score: Double),
        _ rhs: (candidate: TitleSearchCandidate, score: Double)
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.candidate.volumeLabel != nil && rhs.candidate.volumeLabel == nil
    }

    /// クエリと候補タイトルの関連度でスコア付けした候補一覧を1回分取得する。ndcを指定すると
    /// その分類区分に絞り込んだ検索になる（漫画区分726.1で優先候補を、nilで全体を取得する用途）。
    /// 完全一致・前方一致を優先し、"ONE PIECE"のようにタイトルがローマ字表記の作品をカタカナ読み
    /// （「ワンピース」）で検索した場合にも対応できるよう、dcndl:titleTranscription（読み仮名）も
    /// 照合対象に含める。
    private func fetchScoredCandidates(
        title: String,
        ndc: String?
    ) async throws -> [(candidate: TitleSearchCandidate, score: Double)] {
        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            return []
        }
        var queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "cnt", value: "500")]
        if let ndc {
            queryItems.append(URLQueryItem(name: "ndc", value: ndc))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return [] }
        let data = try await fetchData(from: url)

        var seenISBNs: Set<String> = []
        var scored: [(candidate: TitleSearchCandidate, score: Double)] = []
        for item in NDLResponseParser().parseAll(data) where item.isBook {
            guard let isbn = item.isbn, let itemTitle = item.title, !seenISBNs.contains(isbn) else { continue }
            seenISBNs.insert(isbn)
            let score = Self.relevanceScore(query: title, title: itemTitle, titleTranscription: item.titleTranscription)
            guard score >= Self.minimumTitleSearchRelevance else { continue }
            let volumeLabel = item.volume.flatMap(NDLVolumeParser.parse).map(Self.volumeLabel)
            scored.append((TitleSearchCandidate(isbn: isbn, title: itemTitle, creator: item.creator, volumeLabel: volumeLabel), score))
        }
        return scored
    }

    private static func volumeLabel(for parsed: NDLVolumeParser.Result) -> String {
        var label = "\(parsed.number)巻"
        if let marker = parsed.marker {
            label += "(\(marker))"
        }
        return label
    }

    /// クエリと候補タイトルの関連度（0〜1、1が完全一致）。タイトル・読み仮名のうち
    /// より良い一致を採用する。完全一致＞前方一致＞部分一致＞あいまい一致の順に評価を下げる
    /// ことで、たまたま検索語を含むだけの無関係な商品がクエリに近い作品より上位に来ないようにする。
    private static func relevanceScore(query: String, title: String, titleTranscription: String?) -> Double {
        [title, titleTranscription].compactMap { $0 }.map { matchScore(query: query, against: $0) }.max() ?? 0
    }

    private static func matchScore(query: String, against text: String) -> Double {
        let normalizedQuery = TitleMatcher.normalize(query)
        let normalizedText = TitleMatcher.normalize(text)
        guard !normalizedQuery.isEmpty, !normalizedText.isEmpty else { return 0 }
        if normalizedText == normalizedQuery { return 1.0 }
        if normalizedText.hasPrefix(normalizedQuery) { return 0.9 }
        if normalizedText.contains(normalizedQuery) { return 0.6 }
        return TitleMatcher.similarity(query, text) * 0.5
    }

    /// 1から連番で途切れずに存在する最大値を返す（例: {1,2,3,5,6} → 3）。1が無ければnil。
    private static func longestConsecutiveRun(from volumes: Set<Int>) -> Int? {
        guard volumes.contains(1) else { return nil }
        var latest = 1
        while volumes.contains(latest + 1) {
            latest += 1
        }
        return latest
    }

    private static let partSuffixPattern = try! NSRegularExpression(pattern: #"^(.+) 第(\d+)部$"#)

    /// 「タイトル 第N部」から元のタイトルと部番号を取り出す。部分割でなければ(seriesName, nil)を返す。
    private static func splitPartSuffix(_ seriesName: String) -> (queryTitle: String, part: Int?) {
        let range = NSRange(seriesName.startIndex..<seriesName.endIndex, in: seriesName)
        guard let match = partSuffixPattern.firstMatch(in: seriesName, range: range),
              let titleRange = Range(match.range(at: 1), in: seriesName),
              let partRange = Range(match.range(at: 2), in: seriesName),
              let part = Int(seriesName[partRange])
        else {
            return (seriesName, nil)
        }
        return (String(seriesName[titleRange]), part)
    }

    private func fetchData(from url: URL) async throws -> Data {
        do {
            let (data, _) = try await session.data(from: url)
            return data
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw NDLSearchError.timeout
            }
            throw NDLSearchError.network(error.localizedDescription)
        }
    }
}

/// NDL SearchのOpenSearch（RSS + Dublin Core）レスポンスから<item>のタイトル・巻数を抽出する。
final class NDLResponseParser: NSObject, XMLParserDelegate {
    struct Item: Equatable {
        var title: String?
        var volume: String?
        var isbn: String?
        var creator: String?
        /// タイトルの読み仮名。"ONE PIECE"のようにローマ字表記のタイトルをカタカナ読み
        /// （"ワンピース"）で検索した場合の一致判定に使う（タイトル検索の関連度スコアリング参照）。
        var titleTranscription: String?
        var categories: [String] = []

        /// 紙・電子の「本」であることを示す。アニメ円盤（映像資料）やCD（録音資料）等、
        /// タイトルは一致するが巻数の意味が全く異なる無関係なメディアを除外するために使う
        /// （実データで、タイトルが一致する漫画のアニメBlu-rayが独自の巻数体系で
        /// 混在することを確認済み）。
        var isBook: Bool { categories.contains("図書") }
    }

    private var insideItem = false
    private var currentElement = ""
    private var currentText = ""
    private var currentElementIsISBNIdentifier = false
    private var currentItem = Item()
    private var items: [Item] = []

    func parseFirst(_ data: Data) -> Item? {
        parseAll(data).first
    }

    func parseAll(_ data: Data) -> [Item] {
        items = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
        // NDLはISBNを<dc:identifier xsi:type="dcndl:ISBN">タグ（属性で種別を区別）として提供する。
        // 同じ<dc:identifier>要素がNDLBibID・JPNO等にも使われるため、属性で絞り込む必要がある。
        currentElementIsISBNIdentifier = elementName == "dc:identifier" && attributeDict["xsi:type"] == "dcndl:ISBN"
        if elementName == "item" {
            insideItem = true
            currentItem = Item()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard insideItem else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "dc:title":
            if currentItem.title == nil { currentItem.title = text }
        case "dc:creator":
            if currentItem.creator == nil { currentItem.creator = text }
        case "dcndl:titleTranscription":
            if currentItem.titleTranscription == nil { currentItem.titleTranscription = text }
        case "dcndl:volume":
            currentItem.volume = text
        case "dc:identifier":
            if currentElementIsISBNIdentifier, currentItem.isbn == nil {
                currentItem.isbn = text.replacingOccurrences(of: "-", with: "")
            }
        case "category":
            currentItem.categories.append(text)
        case "item":
            items.append(currentItem)
            insideItem = false
        default:
            break
        }
        currentText = ""
    }
}
