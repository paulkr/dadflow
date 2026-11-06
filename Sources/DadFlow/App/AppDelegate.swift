import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dictation = DictationController()
    private var overlay: OverlayController?
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(dictation: dictation)
        dictation.onNeedsSetup = { [weak self] in self?.settingsWindow.show(tab: .setup) }
        dictation.startMonitoring()
        setUpStatusItem()

        ModelManager.shared.prepareSelected()

        let settings = AppSettings.shared
        if !settings.hasCompletedSetup || !Permissions.accessibilityGranted || !Permissions.microphoneGranted {
            settingsWindow.show(tab: .setup)
        }
    }

    /// Opening the app again (e.g. from Launchpad) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show(tab: AppSettings.shared.hasCompletedSetup ? .settings : .setup)
        return true
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon(recording: false)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        dictation.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.statusItem?.button?.image = Self.icon(recording: phase != .idle)
            }
            .store(in: &cancellables)
    }

    private static func icon(recording: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: recording ? "waveform.circle.fill" : "waveform", accessibilityDescription: "Dad Flow")
        image?.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hotkey = AppSettings.shared.hotkey.shortLabel
        switch dictation.phase {
        case .idle:
            menu.addItem(withTitle: "Start Dictating   (hold \(hotkey))", action: #selector(startDictating), keyEquivalent: "").target = self
        case .recording:
            menu.addItem(withTitle: "Stop Dictating", action: #selector(stopDictating), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Cancel", action: #selector(cancelDictating), keyEquivalent: "").target = self
        case .finishing:
            menu.addItem(withTitle: "Finishing…", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Setup & Permissions…", action: #selector(openSetup), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Support Dad Flow 🍯", action: #selector(openSponsor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Dad Flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func startDictating() {
        // Give focus back to the previous app before typing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [dictation] in
            dictation.start(mode: .handsFree)
        }
    }

    @objc private func stopDictating() { dictation.stop() }
    @objc private func cancelDictating() { dictation.cancel() }
    @objc private func openSettings() { settingsWindow.show(tab: .settings) }
    @objc private func openSetup() { settingsWindow.show(tab: .setup) }
    @objc private func openSponsor() { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/paulkr")!) }
}
