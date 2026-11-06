import AppKit
import SwiftUI

/// Renders the README graphics in the app's own theme:
/// `DadFlow --render-docs docs/images`
@MainActor
enum DocsRenderer {
    static func render(to folder: String) {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        save(BannerGraphic(), "banner.png", in: dir)
        save(HowItWorksGraphic(), "how-it-works.png", in: dir)
        save(LiveTypingGraphic(), "live-typing.png", in: dir)
        save(BarStatesGraphic(), "floating-bar.png", in: dir)
        save(PrivacyGraphic(), "privacy.png", in: dir)

        // Screenshots use a fixed demo state (Whisper + Dad Mode, model ready) rather than
        // whatever this Mac happens to have, then put the real settings back.
        let settings = AppSettings.shared
        let saved = (settings.engine, settings.dadMode, settings.hotkey)
        settings.engine = .whisper
        settings.dadMode = true
        settings.hotkey = .fn
        ModelManager.shared.showcaseReady()
        for (name, tab) in [("screenshot-setup.png", SettingsTabs.Tab.setup), ("screenshot-settings.png", .settings)] {
            let tabs = SettingsTabs()
            tabs.selected = tab
            save(SettingsRoot(tabs: tabs, snapshot: true).environment(\.docsDemo, true), name, in: dir, opaque: true)
        }
        (settings.engine, settings.dadMode, settings.hotkey) = saved
    }

    private static func save<V: View>(_ view: V, _ name: String, in dir: URL, opaque: Bool = false) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("failed \(name)"); return }
        var output = cg
        if opaque, let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            // Lay it on the cream canvas so half-covered edge pixels don't show as dark lines.
            let rect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            ctx.setFillColor(NSColor(Theme.canvas).cgColor)
            ctx.fill(rect)
            ctx.draw(cg, in: rect)
            output = ctx.makeImage() ?? cg
        }
        guard let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
            print("failed \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent(name))
        print("wrote \(name)")
    }
}

// MARK: - Shared doc pieces

private struct Sticker: View {
    let color: Color
    let size: CGFloat
    var angle: Double = 0
    var symbol: String? = nil

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().strokeBorder(Theme.ink, lineWidth: 2)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .black))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}

private struct BigLogo: View {
    var size: CGFloat = 96
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Theme.inkDeep)
                .offset(y: size * 0.05)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Theme.ink)
            HStack(spacing: size * 0.06) {
                ForEach([0.2, 0.4, 0.56, 0.32, 0.48, 0.24], id: \.self) { h in
                    Capsule().fill(Theme.lemon).frame(width: size * 0.08, height: size * h)
                }
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-6))
    }
}

/// The real floating bar, drawn at any scale.
struct DocPill: View {
    enum State { case idle, hover, recording, finishing }
    let state: State
    var scale: CGFloat = 1
    var hotkey = "fn"

    var body: some View {
        Group {
            switch state {
            case .idle:
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .frame(width: 40, height: 8)
            case .hover:
                dark {
                    Text("Click or hold \(hotkey) to start dictating")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 16)
                }
                .frame(width: 270, height: 32)
            case .recording:
                dark {
                    HStack(spacing: 10) {
                        circle("xmark", filled: false)
                        HStack(spacing: 3) {
                            ForEach([0.2, 0.45, 0.8, 0.55, 1.0, 0.7, 0.4, 0.85, 0.5, 0.3, 0.6, 0.25], id: \.self) { l in
                                Capsule().fill(Color.white).frame(width: 2.5, height: max(3, 20 * l))
                            }
                        }
                        .frame(width: 58)
                        circle("checkmark", filled: true)
                    }
                    .padding(.horizontal, 7)
                }
                .frame(width: 160, height: 36)
            case .finishing:
                dark {
                    HStack(spacing: 6) {
                        ForEach([1.0, 0.6, 0.3], id: \.self) { o in
                            Circle().fill(Color.white.opacity(o)).frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(width: 160, height: 36)
            }
        }
        .scaleEffect(scale)
        .frame(width: width * scale, height: height * scale)
    }

    private var width: CGFloat {
        switch state { case .idle: 40; case .hover: 270; case .recording, .finishing: 160 }
    }

    private var height: CGFloat {
        switch state { case .idle: 8; case .hover: 32; case .recording, .finishing: 36 }
    }

    private func dark<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(Color(white: 0.06))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            )
    }

    private func circle(_ symbol: String, filled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(filled ? Color.black : Color.white.opacity(0.85))
            .frame(width: 24, height: 24)
            .background(Circle().fill(filled ? Color.white : Color.white.opacity(0.16)))
    }
}

private struct Chip: View {
    let text: String
    let color: Color
    var symbol: String? = nil
    var angle: Double = 0

    var body: some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .black)) }
            Text(text).font(Theme.text(17, .bold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(color))
        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
        .rotationEffect(.degrees(angle))
    }
}

/// A little Mac window with text in it.
private struct MacWindow<Content: View>: View {
    var title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) { c in
                    Circle().fill(c).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Theme.ink.opacity(0.25), lineWidth: 0.5))
                }
                Spacer()
                Text(title).font(Theme.text(13, .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Theme.ink.opacity(0.06))
            Rectangle().fill(Theme.ink).frame(height: 2)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(22)
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink).offset(x: 6, y: 6))
    }
}

private struct Caret: View {
    var height: CGFloat = 26
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5).fill(Theme.ink).frame(width: 3, height: height)
    }
}

// MARK: - Banner (1280x640, also works as the GitHub social preview)

private struct BannerGraphic: View {
    var body: some View {
        ZStack {
            Theme.canvas

            // Confetti stickers
            Sticker(color: Theme.cherry, size: 70, angle: 12).position(x: 1190, y: 74)
            Sticker(color: Theme.lemon, size: 44, angle: -10, symbol: "star.fill").position(x: 700, y: 70)
            Sticker(color: Theme.lavender, size: 56, angle: 8).position(x: 96, y: 580)
            Sticker(color: Theme.lime, size: 38).position(x: 640, y: 590)

            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 22) {
                        BigLogo(size: 104)
                        Text("Dad Flow")
                            .font(Theme.display(84))
                            .foregroundStyle(Theme.ink)
                    }
                    Text("Talk, and watch it type.\nLive. On your Mac. Nowhere else.")
                        .font(Theme.heading(30))
                        .foregroundStyle(Theme.body)
                        .lineSpacing(4)
                    HStack(spacing: 12) {
                        Chip(text: "100% on-device", color: Theme.mint, symbol: "lock.fill", angle: -2)
                        Chip(text: "Live typing", color: Theme.lemon, symbol: "bolt.fill", angle: 1.5)
                        Chip(text: "Free & open source", color: Theme.cherry, symbol: "heart.fill", angle: -1.5)
                    }
                    .padding(.top, 6)
                }

                VStack(spacing: 26) {
                    MacWindow(title: "Note to the kids") {
                        (Text("Hey kids, I'm dictating this with Dad Flow and the words show up ")
                            + Text("as I spe").foregroundColor(Theme.ink).bold()
                            + Text("|").foregroundColor(Theme.ink).font(.system(size: 25, weight: .black)))
                            .font(Theme.text(23, .medium))
                            .foregroundStyle(Theme.body)
                            .lineSpacing(6)
                    }
                    .frame(width: 470, height: 200)

                    DocPill(state: .recording, scale: 1.6)
                }
            }
            .padding(.horizontal, 64)
        }
        .frame(width: 1280, height: 640)
    }
}

// MARK: - How it works (1280x520)

private struct HowItWorksGraphic: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Three ways to talk")
                .font(Theme.display(46))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 24) {
                card(Theme.lemon, "1", "Hold & talk", "Hold fn, speak, let go.\nThat's it.") {
                    Keycap(label: "fn 🌐", wide: true).scaleEffect(1.5).frame(height: 70)
                }
                card(Theme.cherry, "2", "Tap once", "Hands-free mode.\nTap again when you're done.") {
                    HStack(spacing: 18) {
                        Keycap(label: "fn 🌐", wide: true).scaleEffect(1.5)
                        Image(systemName: "hand.tap.fill").font(.system(size: 36)).foregroundStyle(Theme.ink)
                    }
                    .frame(height: 70)
                }
                card(Theme.lavender, "3", "Click the bar", "✓ keeps the text.\n✕ cancels and erases it.") {
                    DocPill(state: .recording, scale: 1.35).frame(height: 70)
                }
            }
        }
        .padding(56)
        .frame(width: 1280, height: 470, alignment: .topLeading)
        .background(Theme.canvas)
    }

    private func card<Art: View>(_ color: Color, _ n: String, _ title: String, _ detail: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(n)
                .font(Theme.heading(20))
                .foregroundStyle(Theme.canvas)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.ink))
                .rotationEffect(.degrees(-8))
            art().frame(maxWidth: .infinity)
            Text(title).font(Theme.heading(28)).foregroundStyle(Theme.ink)
            Text(detail).font(Theme.text(18)).foregroundStyle(Theme.body).lineSpacing(3)
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(color))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
    }
}

// MARK: - Live typing (1280x600)

private struct LiveTypingGraphic: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                Text("Words appear while you talk")
                    .font(Theme.display(46))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Chip(text: "no waiting for ✓", color: Theme.lemon, symbol: "bolt.fill", angle: 2)
            }
            Text("Other dictation apps make you finish, then paste. Dad Flow types as you go, and if it mishears a word, it quietly fixes it on the spot.")
                .font(Theme.text(20))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                row("0.5s", Theme.paper) {
                    Text("Hey dad, this is a").foregroundStyle(Theme.body)
                }
                row("1.5s", Theme.paper) {
                    Text("Hey dad, this is a test. I am talking to my ").foregroundStyle(Theme.body)
                        + Text("mat").foregroundColor(Color(hex: 0xC2410C)).strikethrough(true, color: Color(hex: 0xC2410C))
                }
                row("2.0s", Theme.aquaSoft, fixed: true) {
                    Text("Hey dad, this is a test. I am talking to my ").foregroundStyle(Theme.body)
                        + Text("Mac").foregroundColor(Theme.ink).bold()
                        + Text(", and the words").foregroundStyle(Theme.body)
                }
                row("3.0s", Theme.paper) {
                    Text("Hey dad, this is a test. I am talking to my Mac, and the words appear as I speak.").foregroundStyle(Theme.body)
                }
            }
        }
        .padding(56)
        .frame(width: 1280, height: 530, alignment: .topLeading)
        .background(Theme.canvas)
    }

    private func row<T: View>(_ time: String, _ fill: Color, fixed: Bool = false, @ViewBuilder text: () -> T) -> some View {
        HStack(spacing: 16) {
            Text(time)
                .font(Theme.text(16, .bold))
                .foregroundStyle(Theme.canvas)
                .frame(width: 64, height: 34)
                .background(Capsule().fill(Theme.ink))
            HStack(spacing: 2) {
                text().font(Theme.text(20, .medium))
                Caret(height: 22)
                Spacer()
                if fixed {
                    Chip(text: "auto-fixed", color: Theme.lime, symbol: "checkmark", angle: -2).scaleEffect(0.85)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
        }
    }
}

// MARK: - Floating bar states (1280x380)

private struct BarStatesGraphic: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("The floating bar")
                .font(Theme.display(46))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 18) {
                state(Theme.lemon, "Resting", "Tiny & out of the way") { DocPill(state: .idle, scale: 1.4) }
                state(Theme.lavender, "Hover", "Says what to do") { DocPill(state: .hover, scale: 0.66) }
                state(Theme.cherry, "Listening", "Live waveform") { DocPill(state: .recording, scale: 1.2) }
                state(Theme.mint, "Finishing", "Last words land") { DocPill(state: .finishing, scale: 1.2) }
            }
        }
        .padding(56)
        .frame(width: 1280, height: 372, alignment: .topLeading)
        .background(Theme.canvas)
    }

    private func state<P: View>(_ color: Color, _ title: String, _ detail: String, @ViewBuilder pill: () -> P) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x6B8F89))
                pill()
            }
            .frame(height: 96)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
            VStack(spacing: 2) {
                Text(title).font(Theme.heading(22)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.text(15)).foregroundStyle(Theme.body)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(color))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
    }
}

// MARK: - Privacy (1280x360)

private struct PrivacyGraphic: View {
    var body: some View {
        HStack(spacing: 40) {
            ZStack {
                Circle().fill(Theme.lime)
                Circle().strokeBorder(Theme.ink, lineWidth: 3)
                Image(systemName: "lock.fill").font(.system(size: 80, weight: .black)).foregroundStyle(Theme.ink)
            }
            .frame(width: 190, height: 190)
            .rotationEffect(.degrees(-6))

            VStack(alignment: .leading, spacing: 18) {
                Text("Your voice never leaves your Mac")
                    .font(Theme.display(42))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 12) {
                    Chip(text: "No cloud", color: Theme.paper, symbol: "icloud.slash.fill")
                    Chip(text: "No account", color: Theme.paper, symbol: "person.crop.circle.badge.xmark")
                    Chip(text: "No AI rewriting", color: Theme.paper, symbol: "wand.and.stars.inverse")
                    Chip(text: "Works offline", color: Theme.paper, symbol: "wifi.slash")
                }
                Text("Speech is turned into text by Apple's on-device engine or OpenAI Whisper running locally on the Neural Engine. What you say is exactly what gets typed.")
                    .font(Theme.text(19))
                    .foregroundStyle(Theme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(48)
        .frame(width: 1200, height: 320)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.mint))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2.5))
        .padding(40)
        .frame(width: 1280, height: 400)
        .background(Theme.canvas)
    }
}
