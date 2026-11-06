import AppKit
import SwiftUI

// MARK: - Theme
//
// Retro soda-shop: cream canvas, deep teal ink, fruit-flavoured sticker cards,
// chunky pressable pill buttons. Light-only on purpose.

enum Theme {
    static let canvas = Color(hex: 0xFDF7E7)    // creamy canvas
    static let ink = Color(hex: 0x14433D)       // deep teal: headlines, primary actions, outlines
    static let inkDeep = Color(hex: 0x0B2B27)   // button lip
    static let body = Color(hex: 0x3A3A3A)      // body text
    static let muted = Color(hex: 0x6B6F6A)
    static let paper = Color.white

    static let lemon = Color(hex: 0xFDF4B5)
    static let cherry = Color(hex: 0xFEBAC4)
    static let lavender = Color(hex: 0xE3D2ED)
    static let mint = Color(hex: 0xD3E8E3)
    static let peach = Color(hex: 0xFFC3B3)
    static let lime = Color(hex: 0x95D95D)      // "done" chips
    static let aqua = Color(hex: 0x2AD2C9)      // selected / on states
    static let aquaSoft = Color(hex: 0xA6EDE8)  // selected tile fill (solid, so it never muddies on a coloured card)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .rounded) }

    static let outline: CGFloat = 1.5
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let tabs = SettingsTabs()

    func show(tab: SettingsTabs.Tab = .setup) {
        tabs.selected = tab
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Dad Flow"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(Theme.canvas)
            w.appearance = NSAppearance(named: .aqua)
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsRoot(tabs: tabs))
            w.setContentSize(NSSize(width: 620, height: 720))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

@MainActor
final class SettingsTabs: ObservableObject {
    enum Tab: Hashable { case setup, settings }
    @Published var selected: Tab = .setup
    var close: (() -> Void)?
}

struct SettingsRoot: View {
    @ObservedObject var tabs: SettingsTabs
    /// Renders everything at full height without scrolling (for screenshots).
    var snapshot = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if snapshot {
                content
            } else {
                ScrollView { content }
                    .scrollIndicators(.never)
            }
        }
        .frame(width: 620, height: snapshot ? nil : 720)
        .background(Theme.canvas)
        .environment(\.colorScheme, .light)
        .tint(Theme.ink)
    }

    private var content: some View {
        Group {
            switch tabs.selected {
            case .setup: SetupView(onDone: { NSApp.keyWindow?.close() })
            case .settings: PreferencesView()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .padding(.bottom, 32)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            LogoSticker()
            VStack(alignment: .leading, spacing: 0) {
                Text("Dad Flow")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.ink)
                Text("Talk. It types. Nothing leaves this Mac.")
                    .font(Theme.text(13, .semibold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            TabSwitch(selected: $tabs.selected)
        }
        .padding(.horizontal, 28)
        .padding(.top, 38) // clears the traffic lights
        .padding(.bottom, 16)
    }
}

private struct LogoSticker: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink)
            HStack(spacing: 3) {
                ForEach([10.0, 20, 28, 16, 24, 12], id: \.self) { h in
                    Capsule().fill(Theme.lemon).frame(width: 4, height: h)
                }
            }
        }
        .frame(width: 52, height: 52)
        .rotationEffect(.degrees(-6))
    }
}

private struct TabSwitch: View {
    @Binding var selected: SettingsTabs.Tab

    var body: some View {
        HStack(spacing: 4) {
            tab("Setup", .setup)
            tab("Settings", .settings)
        }
        .padding(4)
        .background(Capsule().fill(Theme.paper))
        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
    }

    private func tab(_ title: String, _ value: SettingsTabs.Tab) -> some View {
        let on = selected == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = value }
        } label: {
            Text(title)
                .font(Theme.text(13.5, .bold))
                .foregroundStyle(on ? Theme.canvas : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? Theme.ink : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Building blocks

/// A flat "sticker" card: solid fruit colour, teal outline, no shadow.
struct StickerCard<Content: View>: View {
    let color: Color
    var badge: String? = nil
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if let badge {
                    Text(badge)
                        .font(Theme.heading(15))
                        .foregroundStyle(Theme.canvas)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.ink))
                        .rotationEffect(.degrees(-8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.heading(18))
                        .foregroundStyle(Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.text(13))
                            .foregroundStyle(Theme.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline))
    }
}

extension StickerCard where Content == EmptyView {
    init(color: Color, badge: String? = nil, title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.init(color: color, badge: badge, title: title, subtitle: subtitle, trailing: trailing) { EmptyView() }
    }
}

/// Chunky pill button with a darker "lip" that squishes down when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let lip: CGFloat = large ? 4 : 3
        let fill = kind == .primary ? Theme.ink : Theme.paper
        let text = kind == .primary ? Theme.canvas : Theme.ink
        return configuration.label
            .font(Theme.text(large ? 16 : 13.5, .bold))
            .foregroundStyle(text)
            .padding(.horizontal, large ? 28 : 16)
            .padding(.vertical, large ? 12 : 8)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            .background(
                Capsule().fill(Theme.inkDeep).offset(y: pressed ? 0 : lip)
            )
            .offset(y: pressed ? lip : 0)
            .padding(.bottom, lip)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Capsule())
    }
}

struct DoneChip: View {
    var text = "Done"
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .black))
            Text(text).font(Theme.text(13, .bold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.lime))
        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
        .rotationEffect(.degrees(-3))
    }
}

/// Big pill switch (aqua when on).
struct ChunkyToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.text(14, detail == nil ? .semibold : .heavy))
                        .foregroundStyle(detail == nil ? Theme.body : Theme.ink)
                    if let detail {
                        Text(detail)
                            .font(Theme.text(12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Theme.aqua : Theme.paper)
                    Circle()
                        .fill(isOn ? Theme.ink : Theme.paper)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
                        .padding(3)
                }
                .frame(width: 50, height: 28)
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Selectable tile; teal outline, aqua fill + check when selected.
struct ChoiceTile<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.aquaSoft : Theme.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: selected ? 2.5 : Theme.outline)
                )
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Theme.canvas)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.ink))
                            .offset(x: 6, y: -6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A keyboard key drawn like a real keycap.
struct Keycap: View {
    let label: String
    var wide = false

    var body: some View {
        Text(label)
            .font(Theme.text(14, .bold))
            .foregroundStyle(Theme.ink)
            .frame(minWidth: wide ? 70 : 38, minHeight: 34)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink).offset(y: 3))
            .padding(.bottom, 3)
    }
}

// MARK: - Setup

struct SetupView: View {
    var onDone: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var models = ModelManager.shared
    @State private var mic = Permissions.microphoneStatus
    @State private var accessibility = Permissions.accessibilityGranted
    @State private var globeFree = Permissions.globeKeyFree
    @Environment(\.docsDemo) private var demo
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let's get you talking.")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            Text("A few one-time switches. Then just hold a key and speak, and the words type out live, right where your cursor is.")
                .font(Theme.text(14))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                step.view(String(index + 1))
            }

            howTo

            HStack {
                Spacer()
                Button(allDone ? "All done! Start talking" : "Finish the steps above first") {
                    settings.hasCompletedSetup = true
                    onDone()
                }
                .buttonStyle(ChunkyButtonStyle(large: true))
                .disabled(!allDone)
                .opacity(allDone ? 1 : 0.45)
                Spacer()
            }
            .padding(.top, 6)

            HoneycombVerse()
                .padding(.top, 18)
        }
        .onReceive(timer) { _ in if !demo { refreshPermissions() } }
        .onAppear { if !demo { refreshPermissions(); refreshModel() } }
        .onChange(of: settings.engine) { _, _ in refreshModel() }
        .onChange(of: settings.whisperModel) { _, _ in refreshModel() }
        .onChange(of: settings.languageID) { _, _ in refreshModel() }
    }

    // README screenshots show a fixed, tidy state instead of this Mac's permissions.
    private var micOK: Bool { demo || mic == .authorized }
    private var accessibilityOK: Bool { demo ? false : accessibility }
    private var globeOK: Bool { demo || globeFree }

    private var allDone: Bool {
        micOK && accessibilityOK
    }

    private struct Step {
        let view: (String) -> AnyView
    }

    private var steps: [Step] {
        var list: [Step] = []
        list.append(Step { badge in
            AnyView(StickerCard(
                color: Theme.lemon, badge: badge, title: "Let it hear you",
                subtitle: "Microphone access, so Dad Flow can listen while you dictate.",
                trailing: micOK ? AnyView(DoneChip()) : AnyView(
                    Button(mic == .notDetermined ? "Allow mic" : "Open Settings") {
                        if mic == .notDetermined {
                            Task { _ = await Permissions.requestMicrophone(); refreshPermissions() }
                        } else {
                            Permissions.openMicrophoneSettings()
                        }
                    }.buttonStyle(ChunkyButtonStyle())
                )
            ))
        })
        list.append(Step { badge in
            AnyView(StickerCard(
                color: Theme.cherry, badge: badge, title: "Let it type for you",
                subtitle: "Accessibility access, so the words can appear in any app. Flip the switch next to Dad Flow. Already on but not ticked here? Select Dad Flow, click −, then click Open Settings again.",
                trailing: accessibilityOK ? AnyView(DoneChip()) : AnyView(
                    Button("Open Settings") {
                        Permissions.promptAccessibility()
                        Permissions.openAccessibilitySettings()
                    }.buttonStyle(ChunkyButtonStyle())
                )
            ))
        })
        if settings.hotkey == .fn && globeOK {
            list.append(Step { badge in
                AnyView(StickerCard(
                    color: Theme.lavender, badge: badge, title: "Free up the 🌐 key",
                    subtitle: "The 🌐 / fn key is set to Do Nothing, so it's all yours.",
                    trailing: AnyView(DoneChip())
                ))
            })
        } else if settings.hotkey == .fn {
            list.append(Step { badge in
                AnyView(StickerCard(color: Theme.lavender, badge: badge, title: "Free up the 🌐 key") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Mac uses the 🌐 / fn key to pop open emoji. Tell it to do nothing, so it's free for Dad Flow:")
                            .font(Theme.text(13))
                            .foregroundStyle(Theme.body)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Text("Keyboard")
                            Image(systemName: "arrow.right")
                            Text("Press 🌐 key to")
                            Image(systemName: "arrow.right")
                            Text("Do Nothing").padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.lemon))
                                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
                        }
                        .font(Theme.text(13, .bold))
                        .foregroundStyle(Theme.ink)
                        HStack(spacing: 10) {
                            Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                                .buttonStyle(ChunkyButtonStyle(kind: .secondary))
                            Text("…or pick another key in Settings.")
                                .font(Theme.text(12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                })
            })
        }
        list.append(Step { badge in
            AnyView(StickerCard(
                color: Theme.mint, badge: badge,
                title: settings.engine == .apple ? "Speech model: Apple on-device" : "Speech model: Whisper",
                subtitle: modelStatus.isBusy ? nil : modelStatus.description,
                trailing: modelTrailing
            ) {
                if modelStatus.isBusy { ModelProgress(status: modelStatus) }
            })
        })
        return list
    }

    private var modelStatus: ModelManager.Status {
        settings.engine == .apple ? models.appleStatus : models.whisperStatus
    }

    private var modelTrailing: AnyView {
        if modelStatus == .ready { return AnyView(DoneChip(text: "Ready")) }
        if modelStatus.isBusy { return AnyView(EmptyView()) }
        return AnyView(Button("Download") {
            if settings.engine == .apple {
                Task { await models.prepareApple(localeID: settings.languageID) }
            } else {
                Task { _ = try? await models.whisper(settings.whisperModel) }
            }
        }.buttonStyle(ChunkyButtonStyle()))
    }

    private var howTo: some View {
        let key = settings.hotkey
        let keyLabel = key == .fn ? "fn 🌐" : key.shortLabel
        return VStack(alignment: .leading, spacing: 14) {
            Text("How it works")
                .font(Theme.heading(18))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .top, spacing: 12) {
                HowCard(color: Theme.lemon, title: "Hold & talk", detail: "Let go and you're done.") {
                    Keycap(label: keyLabel, wide: true)
                }
                HowCard(color: Theme.cherry, title: "Tap once", detail: "Hands-free. Tap again to stop.") {
                    HStack(spacing: 4) {
                        Keycap(label: keyLabel, wide: true)
                        Image(systemName: "hand.tap.fill").foregroundStyle(Theme.ink)
                    }
                }
                HowCard(color: Theme.lavender, title: "Or click the bar", detail: "✕ cancels and erases.") {
                    MiniPill()
                }
            }
        }
        .padding(.top, 6)
    }

    private func refreshPermissions() {
        mic = Permissions.microphoneStatus
        accessibility = Permissions.accessibilityGranted
        globeFree = Permissions.globeKeyFree
    }

    private func refreshModel() {
        if settings.engine == .apple {
            models.refreshAppleStatus(localeID: settings.languageID)
        } else {
            models.refreshWhisperStatus(model: settings.whisperModel)
        }
    }
}

private struct HowCard<Art: View>: View {
    let color: Color
    let title: String
    let detail: String
    @ViewBuilder let art: Art

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            art.frame(height: 40, alignment: .leading)
            Text(title).font(Theme.heading(15)).foregroundStyle(Theme.ink)
            Text(detail)
                .font(Theme.text(12.5))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline))
    }
}

/// A tiny drawing of the recording bar.
private struct MiniPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark").font(.system(size: 7, weight: .black)).foregroundStyle(.white)
                .frame(width: 14, height: 14).background(Circle().fill(Color.white.opacity(0.2)))
            HStack(spacing: 2) {
                ForEach([5.0, 9, 13, 8, 11, 6], id: \.self) { h in
                    Capsule().fill(Color.white).frame(width: 2, height: h)
                }
            }
            Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.black)
                .frame(width: 14, height: 14).background(Circle().fill(Color.white))
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(Capsule().fill(Color(white: 0.06)))
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var models = ModelManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StickerCard(color: Theme.lemon, title: "Your talk key", subtitle: "Hold it to dictate, or tap it once to go hands-free.") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Hotkey.allCases) { key in
                        ChoiceTile(selected: settings.hotkey == key, action: { settings.hotkey = key }) {
                            HStack(spacing: 10) {
                                Keycap(label: keycapLabel(key))
                                Text(keyName(key))
                                    .font(Theme.text(13, .semibold))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
            }

            StickerCard(color: Theme.lavender, title: "Where the bar sits", subtitle: "Click a spot on the little screen.") {
                HStack(alignment: .center, spacing: 18) {
                    PositionPicker(selection: $settings.position)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(settings.position.label)
                            .font(Theme.heading(16))
                            .foregroundStyle(Theme.ink)
                        ChunkyToggle(title: "Show it even when I'm not talking", isOn: $settings.showBarWhenIdle)
                    }
                }
            }

            StickerCard(color: Theme.cherry, title: "Speech engine", subtitle: "Both run 100% on this Mac. Nothing you say is ever uploaded.") {
                VStack(spacing: 10) {
                    ChoiceTile(selected: settings.engine == .apple, action: {
                        if EngineKind.appleAvailable { settings.engine = .apple }
                    }) {
                        engineLabel(
                            icon: "apple.logo",
                            title: "Apple On-Device",
                            detail: EngineKind.appleAvailable
                                ? "Words appear the instant you say them. Smoothest live typing. Recommended."
                                : "Needs macOS 26 or newer."
                        )
                    }
                    .opacity(EngineKind.appleAvailable ? 1 : 0.5)
                    ChoiceTile(selected: settings.engine == .whisper, action: { settings.engine = .whisper }) {
                        engineLabel(
                            icon: "waveform",
                            title: "OpenAI Whisper",
                            detail: "Downloaded once, then works offline. Types in short bursts and tidies up as you talk."
                        )
                    }
                    if settings.engine == .whisper {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(WhisperModel.allCases) { model in
                                RadioRow(selected: settings.whisperModel == model, title: model.label) {
                                    settings.whisperModel = model
                                }
                            }
                            ModelProgress(status: models.whisperStatus)
                                .padding(.leading, 30)
                                .padding(.top, 2)
                            ChunkyToggle(title: "Dad Mode 🧔", detail: "Steadier text. No \"...\" or stray commas when you stop to think.", isOn: $settings.dadMode)
                                .padding(.top, 8)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            StickerCard(color: Theme.mint, title: "Language & extras") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("I'll be speaking")
                            .font(Theme.text(14, .semibold))
                            .foregroundStyle(Theme.body)
                        Spacer()
                        Menu {
                            ForEach(DictationLanguage.all) { lang in
                                Button(lang.name) { settings.languageID = lang.id }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(DictationLanguage.all.first(where: { $0.id == settings.languageID })?.name ?? settings.languageID)
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
                            }
                            .font(Theme.text(13.5, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.paper))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                    ChunkyToggle(title: "Add a space when continuing a sentence", isOn: $settings.smartSpacing)
                    ChunkyToggle(title: "Little start & stop sounds", isOn: $settings.playSounds)
                    ChunkyToggle(title: "Open Dad Flow when my Mac starts", isOn: $settings.launchAtLogin)
                }
            }

            SettingsFooter()
        }
        .onChange(of: settings.engine) { _, _ in models.prepareSelected() }
        .onChange(of: settings.whisperModel) { _, _ in models.prepareSelected() }
        .onChange(of: settings.languageID) { _, _ in
            if settings.engine == .apple { models.prepareSelected() }
        }
    }

    private func keyName(_ key: Hotkey) -> String {
        switch key {
        case .fn: return "fn / Globe"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        }
    }

    private func keycapLabel(_ key: Hotkey) -> String {
        switch key {
        case .fn: return "🌐"
        case .rightOption: return "⌥"
        case .rightCommand: return "⌘"
        case .rightControl: return "⌃"
        }
    }

    private func engineLabel(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.canvas)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading(15)).foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.text(12.5))
                    .foregroundStyle(Theme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RadioRow: View {
    let selected: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.paper)
                    if selected { Circle().fill(Theme.ink).padding(5) }
                }
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
                Text(title)
                    .font(Theme.text(13, selected ? .bold : .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A little drawing of a Mac screen; click where the bar should live.
private struct PositionPicker: View {
    @Binding var selection: PillPosition

    private let size = CGSize(width: 230, height: 146)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Screen
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.paper)
            // Menu bar strip
            Rectangle()
                .fill(Theme.ink.opacity(0.12))
                .frame(height: 12)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))
            ForEach(PillPosition.allCases) { pos in
                spot(pos)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline))
    }

    private func center(_ pos: PillPosition) -> CGPoint {
        let w = size.width, h = size.height
        switch pos {
        case .bottom: return CGPoint(x: w / 2, y: h - 16)
        case .top: return CGPoint(x: w / 2, y: 26)
        case .left: return CGPoint(x: 16, y: h / 2 + 6)
        case .right: return CGPoint(x: w - 16, y: h / 2 + 6)
        case .bottomLeft: return CGPoint(x: 38, y: h - 16)
        case .bottomRight: return CGPoint(x: w - 38, y: h - 16)
        }
    }

    private func spot(_ pos: PillPosition) -> some View {
        let on = selection == pos
        let vertical = pos.isVertical
        let pill = CGSize(width: vertical ? 9 : 36, height: vertical ? 36 : 9)
        let c = center(pos)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = pos }
        } label: {
            Capsule()
                .fill(on ? Theme.ink : Theme.ink.opacity(0.08))
                .overlay(
                    Capsule().strokeBorder(Theme.ink.opacity(on ? 1 : 0.45), style: StrokeStyle(lineWidth: 1.2, dash: on ? [] : [3, 2]))
                )
                .frame(width: pill.width, height: pill.height)
                .scaleEffect(on ? 1.15 : 1)
                .frame(width: pill.width + 16, height: pill.height + 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pos.label)
        .position(c)
    }
}


/// Chunky progress bar + plain-English status for a model download / first-time setup.
struct ModelProgress: View {
    let status: ModelManager.Status
    @State private var started = Date()

    var body: some View {
        switch status {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                ChunkyBar(fraction: fraction)
                Text(fraction.map { "Downloading… \(Int($0 * 100))%" } ?? "Downloading…")
                    .font(Theme.text(12.5, .bold)).foregroundStyle(Theme.ink)
                Text("Step 1 of 2. You'll hear a ding and see a green Ready tick when it's done. You can close this window meanwhile.")
                    .font(Theme.text(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                ChunkyBar(fraction: nil)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Setting it up for your Mac's chip… \(Self.elapsed(from: started, to: context.date))")
                        .font(Theme.text(12.5, .bold)).foregroundStyle(Theme.ink)
                }
                Text("Step 2 of 2. This happens only once and usually takes 1 to 3 minutes (the big model can take longer). You'll hear a ding when it's Ready.")
                    .font(Theme.text(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear { started = Date() }
        case .ready:
            DoneChip(text: "Ready")
        default:
            Text(status.description)
                .font(Theme.text(12, .semibold)).foregroundStyle(Theme.muted)
        }
    }

    static func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }
}

/// Outlined capsule bar. With no fraction, a lemon block slides back and forth.
struct ChunkyBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.paper)
                if let fraction {
                    Capsule().fill(Theme.aqua)
                        .frame(width: max(14, w * min(1, max(0, fraction))))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phase = (sin(t * 2.2) + 1) / 2
                        Capsule().fill(Theme.aqua)
                            .frame(width: w * 0.3)
                            .offset(x: (w * 0.7) * phase)
                    }
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
        }
        .frame(height: 14)
    }
}

/// Bottom of the Settings tab: privacy line, credit, and a quiet verse.
struct SettingsFooter: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("Dad Flow \(version) · No accounts · No cloud · No AI rewriting")
            }
            .font(Theme.text(11.5, .semibold))
            .foregroundStyle(Theme.muted)

            HStack(spacing: 4) {
                Text("Built with ❤️ by")
                Button {
                    NSWorkspace.shared.open(URL(string: "https://paulkr.com")!)
                } label: {
                    Text("Paul").underline()
                }
                .buttonStyle(.plain)
                .help("paulkr.com")
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                Text("·").foregroundStyle(Theme.muted)
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/paulkr")!)
                } label: {
                    Text("Support Dad Flow 🍯").underline()
                }
                .buttonStyle(.plain)
                .help("Sponsor on GitHub")
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .font(Theme.text(12.5, .bold))
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)

        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Proverbs 16:24, tucked quietly under the Setup steps.
struct HoneycombVerse: View {
    var body: some View {
        VStack(spacing: 3) {
            Text("🍯").font(.system(size: 14))
            Text("Gracious words are a honeycomb,\nsweet to the soul and healing to the bones.")
                .font(.system(size: 11.5, weight: .medium, design: .serif).italic())
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Text("PROVERBS 16:24")
                .font(Theme.text(9, .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.muted.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }
}

/// True while rendering README screenshots (see DocsRenderer).
private struct DocsDemoKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var docsDemo: Bool {
        get { self[DocsDemoKey.self] }
        set { self[DocsDemoKey.self] = newValue }
    }
}
