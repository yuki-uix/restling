import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Pure state reducer: notification evidence takes precedence over lagging polls.
/// Display sleep deliberately stays separate from lock/session unavailability.
struct PresenceState: Equatable, Sendable {
    private(set) var systemLocked: Bool?
    private(set) var lockNotificationLatched = false
    private(set) var sessionNotificationInactive = false
    private(set) var sessionOffConsole = false
    private(set) var displaySleeping = false

    var lockedOrSessionUnavailable: Bool {
        lockNotificationLatched || systemLocked != false ||
            sessionNotificationInactive || sessionOffConsole
    }

    mutating func observeSystem(locked: Bool?, onConsole: Bool?) {
        // Missing evidence never clears a known lock or an explicit unlock.
        // In particular, a stale false poll cannot undo a lock notification.
        if let locked, !lockNotificationLatched || locked { systemLocked = locked }
        if let onConsole { sessionOffConsole = !onConsole }
    }

    mutating func receiveLockNotification(locked: Bool) {
        lockNotificationLatched = locked
        systemLocked = locked
    }

    mutating func setSessionInactive(_ inactive: Bool) {
        sessionNotificationInactive = inactive
    }

    mutating func setDisplaySleeping(_ sleeping: Bool) {
        displaySleeping = sleeping
    }

    mutating func confirmUserInteraction() {
        guard systemLocked == nil, !lockNotificationLatched,
              !sessionNotificationInactive, !sessionOffConsole,
              !displaySleeping else { return }
        systemLocked = false
    }
}

/// Samples presence without observing or storing individual keyboard or mouse
/// events. Unknown initial lock state suppresses reminders until reliable system
/// evidence or an actual user interaction with this app confirms availability.
@MainActor
final class PresenceMonitor {
    private let onChange: (_ lockedOrUnavailable: Bool, _ idleSeconds: TimeInterval, _ displaySleeping: Bool) -> Void
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var isMonitoring = false
    private var state = PresenceState()

    init(onChange: @escaping (_ locked: Bool, _ idleSeconds: TimeInterval, _ displaySleeping: Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        state = PresenceState()
        refreshSessionState()

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, name: Notification.Name("com.apple.screenIsLocked")) { monitor in
            monitor.state.receiveLockNotification(locked: true)
        }
        observe(distributed, name: Notification.Name("com.apple.screenIsUnlocked")) { monitor in
            monitor.state.receiveLockNotification(locked: false)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, name: NSWorkspace.sessionDidResignActiveNotification) { monitor in
            monitor.state.setSessionInactive(true)
        }
        observe(workspace, name: NSWorkspace.sessionDidBecomeActiveNotification) { monitor in
            monitor.state.setSessionInactive(false)
        }
        observe(workspace, name: NSWorkspace.screensDidSleepNotification) { monitor in
            monitor.state.setDisplaySleeping(true)
        }
        observe(workspace, name: NSWorkspace.screensDidWakeNotification) { monitor in
            monitor.state.setDisplaySleeping(false)
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        for (center, token) in observations { center.removeObserver(token) }
        observations.removeAll()
    }

    /// Invoke only from a real user action, never from timer ticks or lifecycle
    /// callbacks. It cannot override known lock, inactive-session or sleep state.
    func confirmUserInteraction() {
        guard isMonitoring else { return }
        state.confirmUserInteraction()
        emitSample()
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observations { center.removeObserver(token) }
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name,
                         update: @escaping @MainActor (PresenceMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoring else { return }
                update(self)
                self.emitSample()
            }
        }
        observations.append((center, token))
    }

    private func sample() {
        guard isMonitoring else { return }
        refreshSessionState()
        emitSample()
    }

    private func emitSample() {
        guard isMonitoring else { return }
        // Apple's any-input token is UInt32.max; .null measures only null events.
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let elapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let idleSeconds = elapsed.isFinite ? max(0, elapsed) : 0
        onChange(state.lockedOrSessionUnavailable, idleSeconds, state.displaySleeping)
    }

    private func refreshSessionState() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool
        let locked = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? Self.consoleLocked()
        state.observeSystem(locked: locked, onConsole: onConsole)
    }

    private static func consoleLocked() -> Bool? {
        // IOConsoleLocked is a property on the registry root, not IOService:/.
        // Read only that boolean; no console-user information is inspected.
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "IOConsoleLocked" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
            return nil
        }
        return value.boolValue
    }
}
