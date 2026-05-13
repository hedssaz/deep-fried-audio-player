//
//  Deep_Fried_Audio_PlayerUITestsLaunchTests.swift
//  Deep-Fried Audio PlayerUITests
//
//  Created by hedssaz on 2026/5/13.
//

import XCTest

final class Deep_Fried_Audio_PlayerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["modeSection"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
