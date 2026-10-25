import XCTest

@MainActor
final class RoadsterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLandscapeMenuAndGameplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        let start = app.buttons["Start flight"]
        XCTAssertTrue(start.waitForExistence(timeout: 25), "The menu never appeared")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        attachScreenshot(named: "menu-landscape")

        start.tap()
        sleep(4)
        attachScreenshot(named: "gameplay-landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        attachScreenshot(named: "gameplay-portrait")
    }

    func testCrashResults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-autostart", "-demo", "-crashdemo"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["DAMAGE REPORT"].waitForExistence(timeout: 30),
            "The crash results card never appeared"
        )
        sleep(1)
        attachScreenshot(named: "crash-results")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
