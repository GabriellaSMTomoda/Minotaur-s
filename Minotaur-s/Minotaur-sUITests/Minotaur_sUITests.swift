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
    func testVerifierPrivacyFirstRunAndPermanentAccess() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-verifier-privacy-notice"]
        app.launch()

        app.buttons["Verificador"].tap()

        XCTAssertTrue(
            app.staticTexts["verificationPrivacyNoticeTitle"].waitForExistence(timeout: 5)
        )
        let noticeCopy = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "primeira frase")
        ).firstMatch
        XCTAssertTrue(noticeCopy.exists)

        app.buttons["verificationPrivacyNoticePolicyLink"].tap()
        XCTAssertTrue(
            app.staticTexts["verificationPrivacyPolicyTitle"].waitForExistence(timeout: 5)
        )
        app.buttons["verificationPrivacyPolicyBackButton"].tap()

        app.buttons["verificationPrivacyAcknowledgeButton"].tap()
        XCTAssertTrue(
            app.buttons["verificationPrivacyPolicyButton"].waitForExistence(timeout: 5)
        )

        app.buttons["verificationPrivacyPolicyButton"].tap()
        XCTAssertTrue(
            app.staticTexts["verificationPrivacyPolicyTitle"].waitForExistence(timeout: 5)
        )
        app.buttons["Concluído"].tap()

        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["Verificador"].tap()

        XCTAssertFalse(
            app.staticTexts["verificationPrivacyNoticeTitle"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["verificationPrivacyPolicyButton"].exists)
        XCTAssertTrue(app.buttons["Política de privacidade"].exists)
    }

    @MainActor
    func testPrivacySupportsAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-reset-verifier-privacy-notice",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        app.buttons["Verificador"].tap()
        XCTAssertTrue(
            app.staticTexts["verificationPrivacyNoticeTitle"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["verificationPrivacyAcknowledgeButton"].isHittable)

        let policyLink = app.buttons["verificationPrivacyNoticePolicyLink"]
        if !policyLink.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        policyLink.tap()

        XCTAssertTrue(
            app.staticTexts["verificationPrivacyPolicyTitle"].waitForExistence(timeout: 5)
        )
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Política — texto de acessibilidade XXXL"
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
