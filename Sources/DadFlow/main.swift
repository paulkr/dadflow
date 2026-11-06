import AppKit

let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--selftest" {
    // Developer check: DadFlow --selftest <audio file> [apple|whisper]
    SelfTest.run(path: arguments[2], engine: arguments.count > 3 ? arguments[3] : "apple")
}

if arguments.count >= 3, arguments[1] == "--render-settings" {
    // Developer check: DadFlow --render-settings <output folder>
    MainActor.assumeIsolated { SnapshotRenderer.render(to: arguments[2]) }
    exit(0)
}

if arguments.count >= 3, arguments[1] == "--render-docs" {
    // Developer: DadFlow --render-docs docs/images  (README graphics)
    MainActor.assumeIsolated { DocsRenderer.render(to: arguments[2]) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
