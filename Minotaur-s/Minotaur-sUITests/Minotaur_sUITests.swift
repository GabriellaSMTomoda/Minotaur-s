//
//  Minotaur_sUITests.swift
//  Minotaur-sUITests
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.
//

import XCTest

final class Minotaur_sUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testVerifierWithBundledModelsAndLiveSearch() throws {
        guard ProcessInfo.processInfo.environment["VERIFIER_LIVE_UI_SMOKE"] == "1" else {
            throw XCTSkip("Opt-in verification with real network and local models")
        }
        let app = XCUIApplication()
        app.launch()
        let entry = app.buttons["Verificador"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()

        let privacy = app.buttons["Entendi e continuar"]
        if privacy.waitForExistence(timeout: 3) { privacy.tap() }
        let editor = app.textFields.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("A Terra tem formato plano.")

        let verify = app.buttons["Verificar notícia"]
        let ready = NSPredicate(format: "exists == true AND enabled == true")
        expectation(for: ready, evaluatedWith: verify)
        waitForExpectations(timeout: 15)
        verify.tap()

        // Exercise the actual ViewModel/runner, HTTP search, extraction and models.
        // This checks availability and navigation, not general verdict accuracy.
        XCTAssertTrue(app.staticTexts["Afirmação verificada"].waitForExistence(timeout: 22))
        XCTAssertFalse(app.staticTexts["Análise indisponível"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Verificador — resultado com modelos locais"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
