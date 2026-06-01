//
//  SportsHubUITests.swift
//  SportsHubUITests
//
//  Created by Aarush Khanna  on 3/6/26.
//

import XCTest

final class SportsHubUITests: XCTestCase {

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
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testClipsPlaybackE2E() throws {
        // Drives auth -> Clips -> tap play, then asserts the AVPlayer load did
        // not fall into the "Video unavailable" error state. Requires the dev
        // backend running on http://localhost:8000 with at least one uploaded
        // basketball clip whose video_url returns HTTP 200.
        //
        // MainTabView uses a custom HStack/Button bar (not SwiftUI TabView), so
        // tab navigation uses app.buttons[<label>] rather than app.tabBars.

        let app = XCUIApplication()
        app.launch()

        // AuthenticationView: tap the "Sign In" NavigationLink (presents LoginView).
        let authSignIn = app.buttons["Sign In"]
        XCTAssertTrue(authSignIn.waitForExistence(timeout: 10), "AuthenticationView 'Sign In' button missing — onboarding may not have been completed previously")
        authSignIn.tap()

        // LoginView: fill credentials. The email TextField uses placeholder "your@email.com".
        let emailField = app.textFields["your@email.com"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Login email field missing")
        emailField.tap()
        emailField.typeText("sam.hooper@sportshub.dev")

        let pwdField = app.secureTextFields.firstMatch
        XCTAssertTrue(pwdField.waitForExistence(timeout: 5), "Login password field missing")
        pwdField.tap()
        pwdField.typeText("SportsHub123!")

        // Submit. Use the last "Sign In" button — the AuthenticationView one is
        // still in the nav stack behind LoginView; the LoginView's submit comes after.
        let signInButtons = app.buttons.matching(identifier: "Sign In")
        let submit = signInButtons.element(boundBy: signInButtons.count - 1)
        XCTAssertTrue(submit.exists, "LoginView submit 'Sign In' missing")
        submit.tap()

        // Wait for MainTabView (custom tab bar). "Home" is the default selected tab
        // and its label is rendered in the CustomTabBar HStack.
        let homeTab = app.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 20), "MainTabView didn't appear after login — auth flow or routing blocked")

        // Navigate to Clips tab.
        let clipsTab = app.buttons["Clips"]
        XCTAssertTrue(clipsTab.waitForExistence(timeout: 5), "Clips tab button missing in CustomTabBar")
        clipsTab.tap()

        // Wait for "Basketball Clips" header (default selectedSport in ClipsView).
        let header = app.staticTexts["Basketball Clips"]
        XCTAssertTrue(header.waitForExistence(timeout: 10), "ClipsView header didn't render")

        // The play overlay is an Image("play.circle.fill") wrapped in a Button.
        // Use the SF Symbol identifier "play.circle.fill" to disambiguate from
        // the custom tab bar's "Play" tab (which shares the "Play" accessibility label).
        let playOverlay = app.buttons["play.circle.fill"]
        XCTAssertTrue(playOverlay.waitForExistence(timeout: 15), "Play button overlay (play.circle.fill) not found on any clip card — uploaded clip with non-null video_url may not be in the feed")

        playOverlay.tap()

        // After tap, the "Video unavailable" text should NOT appear within the
        // AVPlayer readiness window (~6s polling + buffer).
        let errorText = app.staticTexts["Video unavailable"]
        let failedAppeared = errorText.waitForExistence(timeout: 10)
        XCTAssertFalse(failedAppeared, "AVPlayer reported 'Video unavailable' — playback failed for uploaded clip")
    }
}
