import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
private final class MainAppLoginItemService: LoginItemServicing {
    private let service = SMAppService.mainApp

    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Reads the system's actual registration state; registration occurs only after
/// the user changes the login-item control in Restling.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusMessage = ""

    private let service: any LoginItemServicing

    init(service: (any LoginItemServicing)? = nil) {
        self.service = service ?? MainAppLoginItemService()
        refresh()
    }

    func refresh() {
        let status = service.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        switch status {
        case .enabled:
            statusMessage = "已开启，登录 Mac 后会启动 Restling。"
        case .notRegistered:
            statusMessage = "未开启，可按需手动启动 Restling。"
        case .requiresApproval:
            statusMessage = "需要在系统设置的登录项中允许 Restling。"
        case .notFound:
            statusMessage = "macOS 尚未找到此登录项。可尝试开启，并按系统提示完成设置。"
        @unknown default:
            statusMessage = "暂时无法读取登录项状态，请到系统设置中检查。"
        }
    }

    func setEnabled(_ enabled: Bool) {
        let status = service.status
        do {
            if enabled {
                // Re-registering an already registered or user-disabled service
                // cannot grant consent. Surface the system approval route instead.
                if status != .enabled && status != .requiresApproval {
                    try service.register()
                }
            } else if status == .enabled || status == .requiresApproval {
                try service.unregister()
            }
            refresh()
        } catch {
            refresh()
            let action = enabled ? "开启" : "关闭"
            statusMessage = "未能\(action)开机启动：\(error.localizedDescription) 请在系统设置的登录项中检查。"
        }
    }

    func openSettings() {
        service.openSettings()
    }
}
