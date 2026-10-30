import Foundation
import ServiceManagement
import XCTest
@testable import BreaktimeApp

final class LoginItemControllerTests: XCTestCase {
    @MainActor
    func testInitializationOnlyReadsSystemState() async {
        for state in [SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound] {
            let service = FakeLoginItemService(status: state)
            let controller = LoginItemController(service: service)
            XCTAssertGreaterThan(service.statusReads, 0)
            XCTAssertEqual(service.registerCalls, 0)
            XCTAssertEqual(service.unregisterCalls, 0)
            XCTAssertEqual(service.settingsCalls, 0)
            XCTAssertEqual(controller.isEnabled, state == .enabled)
            XCTAssertEqual(controller.requiresApproval, state == .requiresApproval)
            XCTAssertFalse(controller.statusMessage.isEmpty)
        }
    }

    @MainActor
    func testExplicitEnableAndDisableUseTheServiceAndRemainIdempotent() async {
        let service = FakeLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)

        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1, "An enabled login item must not be registered again.")
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    @MainActor
    func testPendingApprovalDoesNotReregisterOrPretendItIsEnabled() async {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.settingsCalls, 0, "A toggle does not silently open another application.")
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertTrue(controller.statusMessage.contains("系统设置"))
    }

    @MainActor
    func testNewRegistrationAwaitingApprovalIsNotReportedAsEnabled() async {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegistration = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
    }

    @MainActor
    func testUserCanCancelAPendingRegistration() async {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
    }

    @MainActor
    func testRefreshReflectsApprovalRevokedOutsideTheAppWithoutReregistering() async {
        let service = FakeLoginItemService(status: .enabled)
        let controller = LoginItemController(service: service)
        service.currentStatus = .requiresApproval
        controller.refresh()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    @MainActor
    func testRegistrationFailureDoesNotPretendSuccess() async {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registrationError = LoginItemTestError.refused
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertTrue(controller.statusMessage.contains("未能开启"))
        XCTAssertTrue(controller.statusMessage.contains("测试拒绝"))
    }

    @MainActor
    func testUnregistrationFailurePreservesActualEnabledState() async {
        let service = FakeLoginItemService(status: .enabled)
        service.unregistrationError = LoginItemTestError.refused
        let controller = LoginItemController(service: service)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.statusMessage.contains("未能关闭"))
    }

    @MainActor
    func testOpenSettingsIsAnExplicitForwardedAction() async {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service)
        controller.openSettings()
        XCTAssertEqual(service.settingsCalls, 1)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var currentStatus: SMAppService.Status
    var statusAfterRegistration: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    private(set) var statusReads = 0
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var settingsCalls = 0

    init(status: SMAppService.Status) { currentStatus = status }

    var status: SMAppService.Status {
        statusReads += 1
        return currentStatus
    }

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        currentStatus = statusAfterRegistration
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregistrationError { throw unregistrationError }
        currentStatus = .notRegistered
    }

    func openSettings() { settingsCalls += 1 }
}

private enum LoginItemTestError: LocalizedError {
    case refused
    var errorDescription: String? { "测试拒绝" }
}
