import XCTest
@testable import BookReader

/// NDL Searchのdcndl:volume表記から巻数を抽出するロジックのテスト。
/// パターンは実データ（複数出版社・複数作品のNDLレスポンス）を幅広く調査して確定したもの
/// （詳細はNDLVolumeParser.swiftのコメント参照）。
final class NDLVolumeParserTests: XCTestCase {
    // MARK: - 安全と判断したパターン（採用する）

    func test_plainDigit_isAccepted() {
        XCTAssertEqual(NDLVolumeParser.parse("5")?.number, 5)
    }

    func test_kanPrefix_isAccepted() {
        // 実際に確認したONE PIECE 115巻のケース
        XCTAssertEqual(NDLVolumeParser.parse("巻115")?.number, 115)
    }

    func test_daiKanSuffix_isAccepted() {
        // 実際に確認した銀魂のケース
        XCTAssertEqual(NDLVolumeParser.parse("第1巻")?.number, 1)
    }

    func test_daiKanSuffixWithSubtitle_isAccepted() {
        XCTAssertEqual(NDLVolumeParser.parse("第24巻 (会ってもわからないこともある)")?.number, 24)
    }

    func test_volDot_isAccepted() {
        // 実際に確認した僕のヒーローアカデミアのケース
        XCTAssertEqual(NDLVolumeParser.parse("Vol.42")?.number, 42)
        XCTAssertEqual(NDLVolumeParser.parse("vol. 2")?.number, 2)
    }

    func test_volDotWithSubtitle_isAccepted() {
        XCTAssertEqual(NDLVolumeParser.parse("Vol.1 (緑谷出久:オリジン)")?.number, 1)
    }

    func test_numberWithSubtitle_isAccepted() {
        // 実際に確認したゴールデンカムイ・ワンパンマン・ワールドトリガーのケース
        XCTAssertEqual(NDLVolumeParser.parse("10 (樺太編4)")?.number, 10)
        XCTAssertEqual(NDLVolumeParser.parse("1 (一撃)")?.number, 1)
        XCTAssertEqual(NDLVolumeParser.parse("04 (巨大隕石)")?.number, 4)
    }

    func test_bracketOnly_isAccepted() {
        // 実際に確認した鬼滅の刃・呪術廻戦等のケース
        XCTAssertEqual(NDLVolumeParser.parse("[1]")?.number, 1)
    }

    func test_bandGerman_isAccepted() {
        // 実際に確認したSPY×FAMILYのケース（ドイツ語版カタログ）
        XCTAssertEqual(NDLVolumeParser.parse("Band 12")?.number, 12)
        XCTAssertEqual(NDLVolumeParser.parse("11 Band")?.number, 11)
    }

    // MARK: - 上下巻・前後編（マーカーを保持）

    func test_splitVolumeMarker_parenthesized_extractsNumberAndMarker() {
        let result = NDLVolumeParser.parse("1(上)")
        XCTAssertEqual(result?.number, 1)
        XCTAssertEqual(result?.marker, "上")
    }

    func test_splitVolumeMarker_bracketed_extractsNumberAndMarker() {
        // 実際に確認した転生したらスライムだった件のケース（"1[上]"、"1[下]"）
        let upper = NDLVolumeParser.parse("1[上]")
        XCTAssertEqual(upper?.number, 1)
        XCTAssertEqual(upper?.marker, "上")

        let lower = NDLVolumeParser.parse("1[下]")
        XCTAssertEqual(lower?.number, 1)
        XCTAssertEqual(lower?.marker, "下")
    }

    func test_splitVolumeMarker_allKnownMarkers_areRecognized() {
        for marker in NDLVolumeParser.splitMarkers {
            let result = NDLVolumeParser.parse("3(\(marker))")
            XCTAssertEqual(result?.number, 3, "marker=\(marker)")
            XCTAssertEqual(result?.marker, marker, "marker=\(marker)")
        }
    }

    // MARK: - 部単位の分割

    func test_partSplit_extractsPartAndVolumeWithinPart() {
        // 実際に確認した本好きの下剋上のケース（"第1部[1]"、"第1部[2]"、"第2部[1]"…）
        let result = NDLVolumeParser.parse("第1部[2]")
        XCTAssertEqual(result?.number, 2, "numberは部内の巻数（M）を表す")
        XCTAssertEqual(result?.part, 1)
        XCTAssertNil(result?.marker)
    }

    // MARK: - 除外すべきパターン

    func test_magazineIssueNumber_isRejected() {
        // 週刊誌の号数は単行本の巻数と対応しないため除外する
        XCTAssertNil(NDLVolumeParser.parse("No. 71"))
        XCTAssertNil(NDLVolumeParser.parse("no.29"))
    }

    func test_rangeOrList_isRejected() {
        XCTAssertNil(NDLVolumeParser.parse("v. 1-2-3"))
    }

    func test_decimalVolume_isRejected() {
        // 呪術廻戦0.5巻のような特別巻は整数の巻数として扱えない
        XCTAssertNil(NDLVolumeParser.parse("0.5"))
    }

    func test_kanjiNumeralOnly_isRejected() {
        XCTAssertNil(NDLVolumeParser.parse("巻一"))
    }

    func test_textWithoutNumber_isRejected() {
        XCTAssertNil(NDLVolumeParser.parse("刀鍛冶の里編"))
    }

    func test_emptyString_isRejected() {
        XCTAssertNil(NDLVolumeParser.parse(""))
    }

    func test_animeSeasonNumbering_isRejected() {
        // アニメ円盤特有の採番（銀魂「シーズン其ノ4-1」等）。category=図書フィルタで
        // 通常は事前に除外されるが、このパーサー単体としても数字を誤って拾わないこと。
        XCTAssertNil(NDLVolumeParser.parse("シーズン其ノ4-1"))
        XCTAssertNil(NDLVolumeParser.parse("2nd 1"))
    }
}
