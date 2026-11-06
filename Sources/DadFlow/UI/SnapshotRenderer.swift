import AppKit
import SwiftUI

/// Renders the settings screens to PNGs so the design can be reviewed without clicking around.
@MainActor
enum SnapshotRenderer {
    static func render(to folder: String) {
        _ = NSApplication.shared
        for (name, tab) in [("setup", SettingsTabs.Tab.setup), ("settings", .settings)] {
            let tabs = SettingsTabs()
            tabs.selected = tab
            let renderer = ImageRenderer(content: SettingsRoot(tabs: tabs, snapshot: true))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }
}
