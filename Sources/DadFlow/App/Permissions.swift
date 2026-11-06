import AppKit
import AVFoundation
import ApplicationServices

enum Permissions {
    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var microphoneGranted: Bool { microphoneStatus == .authorized }

    static func requestMicrophone() async -> Bool {
        switch microphoneStatus {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Accessibility lets Dad Flow type into other apps and see the hotkey.
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// True when System Settings → Keyboard → "Press 🌐 key to" is set to "Do Nothing".
    static var globeKeyFree: Bool {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? NSNumber)?.intValue == 0
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// If System Settings is already open on another page (e.g. Accessibility from the
    /// previous step), macOS often just brings it forward and ignores the new link. So we
    /// quit it first, wait for it to close, then open the page we actually want.
    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        guard !running.isEmpty else { NSWorkspace.shared.open(url); return }
        running.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0..<40 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            NSWorkspace.shared.open(url)
        }
    }
}
