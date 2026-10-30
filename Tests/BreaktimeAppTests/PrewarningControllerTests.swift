import AppKit
import Foundation
import PomodoroCore
import XCTest
@testable import BreaktimeApp

final class PrewarningControllerTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let model: AppModel
        let controller: PrewarningController
        private(set) var presentedPanels: [NSPanel] = []

        init() throws {
            _ = NSApplication.shared
            guard !NSScreen.screens.isEmpty else {
                throw XCTSkip("Native panel inspection requires a WindowServer display.")
            }
            suite = "PrewarningControllerTests." + UUID().uuidString
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(try JSONEncoder().encode(EyeRestSettings(intervalMinutes: 1, restSeconds: 5)),
                         forKey: "eyeRestSettings.v1")
            defaults.set(try JSONEncoder().encode(ReminderPreferences(
                idlePauseEnabled: false, returnGraceSeconds: 0, startSoundEnabled: false, endSoundEnabled: false)),
                         forKey: "reminderPreferences.v1")
            let model = AppModel(defaults: defaults, startsTicker: false)
            self.model = model
            // Record presentation without actually displaying a window. This
            // fixture never creates RestOverlayController or activates NSApp.
            var capture: ((NSPanel) -> Void)?
            controller = PrewarningController(model: model, presentPanel: { panel in capture?(panel) })
            capture = { [weak self] panel in self?.presentedPanels.append(panel) }
        }

        func enterPrewarning() {
            model.toggleRunning()
            model.advanceTimer(by: 50)
            controller.synchronize()
        }

        func cleanup() {
            controller.close()
            presentedPanels.removeAll()
            model.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @MainActor
    func testThresholdCreatesOneNativeNonactivatingPanelWithoutChangingFocus() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let application = NSApplication.shared
        let wasActive = application.isActive
        let previousKeyWindow = application.keyWindow
        f.model.toggleRunning()
        f.model.advanceTimer(by: 49)
        f.controller.synchronize()
        XCTAssertEqual(f.controller.windowCount, 0)
        f.model.advanceTimer(by: 1)
        f.controller.synchronize()
        for _ in 0..<10 { f.controller.synchronize() }

        let panel = try XCTUnwrap(f.controller.panelForInspection)
        XCTAssertEqual(f.controller.windowCount, 1)
        XCTAssertEqual(f.presentedPanels.count, 1)
        XCTAssertTrue(f.presentedPanels.first === panel)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.isVisible, "The test presenter must never display the native panel.")
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(application.isActive, wasActive)
        XCTAssertTrue(application.keyWindow === previousKeyWindow)
    }

    @MainActor
    func testSnoozeClosesThePanelAndDoesNotCreateAnOverlappingReminder() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.enterPrewarning()
        let panel = try XCTUnwrap(f.controller.panelForInspection)
        f.model.snooze(minutes: 3)
        f.controller.synchronize()
        for _ in 0..<10 { f.controller.synchronize() }
        XCTAssertTrue(f.model.isSnoozing)
        XCTAssertFalse(f.controller.isVisible)
        XCTAssertNil(f.controller.panelForInspection)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(f.presentedPanels.count, 1)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testDismissalClosesThePanelForTheCurrentInterval() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.enterPrewarning()
        f.model.dismissPrewarning()
        f.controller.synchronize()
        f.model.advanceTimer(by: 5)
        f.controller.synchronize()
        XCTAssertFalse(f.controller.isVisible)
        XCTAssertNil(f.controller.panelForInspection)
        XCTAssertEqual(f.presentedPanels.count, 1)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testLockClosesThePanelWithoutShowingOrCreditingARest() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.enterPrewarning()
        let panel = try XCTUnwrap(f.controller.panelForInspection)
        f.model.updatePresence(locked: true, idleSeconds: 0)
        f.controller.synchronize()
        XCTAssertFalse(f.controller.isVisible)
        XCTAssertNil(f.controller.panelForInspection)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(f.model.showingRest)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }

    @MainActor
    func testDeadlineClosesThePrewarningBeforeRestPresentation() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        f.enterPrewarning()
        f.model.advanceTimer(by: 10)
        f.controller.synchronize()
        XCTAssertTrue(f.model.showingRest)
        XCTAssertEqual(f.controller.windowCount, 0)
        XCTAssertNil(f.controller.panelForInspection)
        XCTAssertEqual(f.presentedPanels.count, 1)
        XCTAssertEqual(f.model.forest.current.completedRests, 0)
    }
}
