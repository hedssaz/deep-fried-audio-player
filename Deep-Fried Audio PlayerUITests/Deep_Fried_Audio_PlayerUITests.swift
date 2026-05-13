//
//  Deep_Fried_Audio_PlayerUITests.swift
//  Deep-Fried Audio PlayerUITests
//
//  Created by hedssaz on 2026/5/13.
//

import XCTest

final class Deep_Fried_Audio_PlayerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimarySections() throws {
        let app = launchApp()

        XCTAssertTrue(app.descendants(matching: .any)["modeSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["audioSourceSection"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["playbackSection"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["processingSection"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["waveformSection"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["singleModuleEditorSection"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["playbackStatus"].exists)
    }

    @MainActor
    func testSampleAudioWorkflowAndParameterEditingDoNotTriggerPlayback() throws {
        let app = launchApp()

        tap(element("audioSampleButton", in: app), in: app)
        XCTAssertTrue(app.descendants(matching: .any)["waveformView"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["playbackStatus"].exists)

        let modePicker = app.segmentedControls["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        modePicker.buttons.element(boundBy: 1).tap()

        let addModuleButton = element("addWorkflowModuleButton", in: app)
        tap(addModuleButton, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["workflowBlockList"].waitForExistence(timeout: 5))

        let parameterPicker = element("parameterControl.targetSampleRate.choice", in: app)
        tap(parameterPicker, in: app)

        let sampleRateChoice = app.descendants(matching: .any)["parameterChoice.targetSampleRate.8000"]
        if sampleRateChoice.waitForExistence(timeout: 3) {
            sampleRateChoice.tap()
        } else {
            let fallbackChoice = app.descendants(matching: .any)["8,000 Hz"]
            XCTAssertTrue(fallbackChoice.waitForExistence(timeout: 5))
            fallbackChoice.tap()
        }

        XCTAssertTrue(app.descendants(matching: .any)["processingSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["waveformView"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["playbackStatus"].exists)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func tap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !element.waitForExistence(timeout: 2) {
            for _ in 0..<6 where !element.exists {
                app.swipeUp()
                _ = element.waitForExistence(timeout: 1)
            }
        }

        XCTAssertTrue(element.exists, "Expected UI element to exist.", file: file, line: line)

        if !element.isHittable {
            for _ in 0..<6 where !element.isHittable {
                app.swipeUp()
            }
        }

        XCTAssertTrue(element.isHittable, "Expected UI element to be hittable.", file: file, line: line)
        element.tap()
    }
}
