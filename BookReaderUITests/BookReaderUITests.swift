//
//  BookReaderUITests.swift
//  BookReaderUITests
//
//  Created by 清水篤 on 2026/09/04.
//

import XCTest

final class BookReaderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    /// 通知許可・ATTダイアログなどのシステムアラートを自動的に許可する
    private func addSystemAlertMonitor() {
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            let allowButton = alert.buttons["許可"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            let okButton = alert.buttons["OK"]
            if okButton.exists {
                okButton.tap()
                return true
            }
            return false
        }
    }

    @MainActor
    func test_launchesAndShowsThreeTabs() throws {
        let app = XCUIApplication()
        addSystemAlertMonitor()
        app.launch()
        app.tap() // ダイアログのinterruption monitorをトリガーするため一度タップする

        XCTAssertTrue(app.tabBars.buttons["買う前チェック"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["積読リスト"].exists)
        XCTAssertTrue(app.tabBars.buttons["気になる本棚"].exists)
    }

    @MainActor
    func test_navigatingToTsundokuList_showsNavigationTitle() throws {
        let app = XCUIApplication()
        addSystemAlertMonitor()
        app.launch()
        app.tap()

        app.tabBars.buttons["積読リスト"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["積読リスト（0冊）"].waitForExistence(timeout: 5))
    }

    @MainActor
    func test_navigatingToWishShelf_showsNavigationTitle() throws {
        let app = XCUIApplication()
        addSystemAlertMonitor()
        app.launch()
        app.tap()

        app.tabBars.buttons["気になる本棚"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["気になる本棚"].waitForExistence(timeout: 5))
    }

    @MainActor
    func test_scanRegisterSheet_opensAndCloses() throws {
        let app = XCUIApplication()
        addSystemAlertMonitor()
        app.launch()
        app.tap()

        app.tabBars.buttons["積読リスト"].tap()
        app.navigationBars.buttons["本棚に登録"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["本棚に登録"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["閉じる"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["積読リスト（0冊）"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
