import XCTest

@MainActor
final class TomaTrustLoopUITests: XCTestCase {
    func testCustomizeHatchPetIdentityPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        let profileButton = app.buttons["pet.profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()

        let sparkPreset = element("pet.preset.spark", in: app)
        XCTAssertTrue(sparkPreset.waitForExistence(timeout: 5))
        sparkPreset.tap()

        let nameField = app.textFields["pet.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        nameField.typeText("Tobi")
        app.buttons["pet.save"].tap()

        XCTAssertTrue(app.navigationBars["Tobi"].waitForExistence(timeout: 5))
        XCTAssertEqual(element("pet.preset.current", in: app).label, "火花 · 主動・行動型")

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Tobi"].waitForExistence(timeout: 5))
        XCTAssertEqual(element("pet.preset.current", in: app).label, "火花 · 主動・行動型")
    }

    func testPreviewApproveReceiptAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        let xp = element("pet.xp", in: app)
        let stage = element("pet.stage", in: app)
        XCTAssertTrue(xp.waitForExistence(timeout: 5))
        XCTAssertEqual(xp.label, "0 XP")
        XCTAssertEqual(stage.label, "初生夥伴")
        attach("01-home", app: app)

        app.buttons["plan.prepare"].tap()

        let preview = element("plan.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(xp.label, "0 XP")
        attach("02-preview", app: app)

        let composer = app.textFields["composer.input"]
        let reminder = app.switches["plan.reminder"]
        makeVisible(reminder, above: composer, in: app)
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertEqual(element("plan.version", in: app).label, "v1")

        let approve = app.buttons["plan.approve"]
        makeVisible(approve, above: composer, in: app)
        approve.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard wait(for: NSPredicate(format: "exists == false"), on: approve) else { return }

        let status = element("receipt.status", in: app)
        makeVisible(status, above: composer, in: app)
        XCTAssertEqual(status.label, "已驗證")
        XCTAssertEqual(
            element("receipt.summary", in: app).label,
            "計畫已保存，執行結果已讀回確認。"
        )
        attach("03-receipt", app: app)

        makeVisibleAtTop(xp, in: app)
        XCTAssertEqual(xp.label, "20 XP")
        XCTAssertEqual(stage.label, "默契夥伴")

        let undo = app.buttons["receipt.undo"]
        makeVisible(undo, above: composer, in: app)
        undo.tap()

        guard wait(for: NSPredicate(format: "label == %@", "已復原"), on: status) else { return }
        XCTAssertEqual(
            element("receipt.summary", in: app).label,
            "計畫、提醒與本次成長值都已復原。"
        )
        attach("04-reverted", app: app)

        makeVisibleAtTop(xp, in: app)
        XCTAssertEqual(xp.label, "0 XP")
        XCTAssertEqual(stage.label, "初生夥伴")
    }

    func testCustomHatchWishCanBeSavedLocally() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        let profileButton = app.buttons["pet.profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()
        XCTAssertTrue(app.navigationBars["我的 Hatch Pet"].waitForExistence(timeout: 5))

        let create = element("hatch.create", in: app)
        makeVisibleInForm(create, in: app)
        create.tap()

        let appearance = element("hatch.appearance", in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap()
        appearance.typeText("mint green pet with two leaf ears")
        app.buttons["hatch.save"].tap()

        let status = element("hatch.status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "已儲存在本機・等待 Gateway")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func makeVisible(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            scrollView.swipeUp()
        }
        XCTFail("Element never became visible: \(element)")
    }

    private func makeVisible(
        _ element: XCUIElement,
        above composer: XCUIElement,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.exists,
               element.frame.minY > 122,
               element.frame.maxY < composer.frame.minY - 12 {
                return
            }
            scrollView.swipeUp()
        }
        XCTFail("Element remained behind the composer: \(element)")
    }

    private func makeVisibleAtTop(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            scrollView.swipeDown()
        }
        XCTFail("Top element never became visible: \(element)")
    }

    private func makeVisibleInForm(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Form element never became visible: \(element)")
    }

    private func attach(_ name: String, app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.75)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func wait(for predicate: NSPredicate, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed)
        return result == .completed
    }
}
