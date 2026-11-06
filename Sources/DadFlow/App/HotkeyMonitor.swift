import AppKit

/// Watches the chosen modifier key system-wide (needs Accessibility permission).
@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Another (real, non-synthetic) key was pressed while the hotkey is held,
    /// e.g. fn+Delete. Used to cancel accidental dictations.
    var onOtherKey: (() -> Void)?

    private var monitors: [Any] = []
    private var isDown = false
    private var installedWhileTrusted = false
    private var trustTimer: Timer?

    func start() {
        install()
        // Global monitors only work once Accessibility is granted; reinstall when it is.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if Permissions.accessibilityGranted && !self.installedWhileTrusted { self.install() }
            }
        }
    }

    private func install() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        installedWhileTrusted = Permissions.accessibilityGranted

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.handleFlags(e)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.handleFlags(e)
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            self?.handleKeyDown(e)
        }) { monitors.append(m) }
    }

    private func handleFlags(_ event: NSEvent) {
        let hotkey = AppSettings.shared.hotkey
        guard hotkey.keyCodes.contains(event.keyCode) else { return }
        let down = hotkey.isDown(event.modifierFlags)
        guard down != isDown else { return }
        isDown = down
        if down { onPress?() } else { onRelease?() }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isDown else { return }
        if let cg = event.cgEvent, cg.getIntegerValueField(.eventSourceUserData) == LiveTyper.syntheticMarker { return }
        onOtherKey?()
    }
}
