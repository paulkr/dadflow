import AppKit
import Combine
import SwiftUI

/// The floating bar. It never takes keyboard focus, so clicking it leaves your cursor
/// exactly where it was in the app you're typing into.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 20),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var hovering = false
}

@MainActor
final class OverlayController {
    private let panel = OverlayPanel()
    private let model = OverlayModel()
    private let dictation: DictationController
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init(dictation: DictationController) {
        self.dictation = dictation
        let host = OverlayHostingView(rootView: PillView(dictation: dictation, overlay: model, settings: settings))
        host.onHover = { [weak self] inside in
            self?.model.hovering = inside
        }
        panel.contentView = host

        Publishers.MergeMany(
            dictation.$phase.map { _ in () }.eraseToAnyPublisher(),
            dictation.$message.map { _ in () }.eraseToAnyPublisher(),
            model.$hovering.map { _ in () }.eraseToAnyPublisher(),
            settings.$position.map { _ in () }.eraseToAnyPublisher(),
            settings.$showBarWhenIdle.map { _ in () }.eraseToAnyPublisher(),
            settings.$hotkey.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.layout() }
        .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
        layout()
    }

    private var targetScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }

    private func size() -> NSSize {
        if let message = dictation.message {
            let width = min(460, 44 + CGFloat(message.count) * 7.2)
            return NSSize(width: width, height: 36)
        }
        switch dictation.phase {
        case .recording, .finishing:
            return NSSize(width: 164, height: 40)
        case .idle:
            if model.hovering { return NSSize(width: 300, height: 36) }
            return settings.position.isVertical ? NSSize(width: 22, height: 64) : NSSize(width: 64, height: 22)
        }
    }

    /// `visibleFrame` always leaves room for the Dock, even in a full-screen app where the
    /// Dock is hidden. So when the Dock's window isn't actually on screen, use the whole
    /// screen (still staying below the menu bar).
    private func usableFrame(of screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        guard !Self.dockOnScreen else { return visible }
        var f = screen.frame
        f.size.height = visible.maxY - f.minY
        return f
    }

    /// The Dock draws in a window at the Dock level (20). It's only listed as on-screen
    /// when the Dock is showing in the current space.
    private static var dockOnScreen: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Dock"
                && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.dockWindow))
        }
    }

    func layout() {
        let visible = dictation.phase != .idle || dictation.message != nil || settings.showBarWhenIdle
        guard visible, let screen = targetScreen else {
            panel.orderOut(nil)
            return
        }
        let s = size()
        let f = usableFrame(of: screen)
        let margin: CGFloat = 10
        let origin: NSPoint
        switch settings.position {
        case .bottom: origin = NSPoint(x: f.midX - s.width / 2, y: f.minY + margin)
        case .top: origin = NSPoint(x: f.midX - s.width / 2, y: f.maxY - s.height - margin)
        case .left: origin = NSPoint(x: f.minX + margin, y: f.midY - s.height / 2)
        case .right: origin = NSPoint(x: f.maxX - s.width - margin, y: f.midY - s.height / 2)
        case .bottomLeft: origin = NSPoint(x: f.minX + margin + 8, y: f.minY + margin)
        case .bottomRight: origin = NSPoint(x: f.maxX - s.width - margin - 8, y: f.minY + margin)
        }
        panel.setFrame(NSRect(origin: origin, size: s), display: true, animate: false)
        panel.orderFrontRegardless()
    }
}

// MARK: - SwiftUI

struct PillView: View {
    @ObservedObject var dictation: DictationController
    @ObservedObject var overlay: OverlayModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        ZStack {
            if let message = dictation.message {
                capsule {
                    Text(message)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                }
            } else {
                switch dictation.phase {
                case .idle:
                    if overlay.hovering {
                        capsule {
                            Text("Click or hold \(settings.hotkey.shortLabel) to start dictating")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { dictation.barClicked() }
                    } else {
                        idlePill
                    }
                case .recording:
                    capsule { recordingContent }
                case .finishing:
                    capsule { FinishingDots() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: dictation.phase)
        .animation(.easeOut(duration: 0.15), value: overlay.hovering)
    }

    private var idlePill: some View {
        let vertical = settings.position.isVertical
        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: vertical ? 8 : 40, height: vertical ? 40 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { dictation.barClicked() }
    }

    private var recordingContent: some View {
        HStack(spacing: 10) {
            CircleButton(symbol: "xmark", filled: false) { dictation.cancel() }
                .help("Cancel and erase")
            Waveform(levels: dictation.levels)
                .frame(width: 58, height: 20)
            CircleButton(symbol: "checkmark", filled: true) { dictation.stop() }
                .help("Done")
        }
        .padding(.horizontal, 7)
    }

    private func capsule<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(Color(white: 0.06).opacity(0.94))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            )
            .padding(2)
    }
}

private struct CircleButton: View {
    let symbol: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(filled ? Color.black : Color.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(filled ? Color.white : Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }
}

private struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: max(3, 20 * min(1, level * 1.15)))
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

private struct FinishingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .onAppear { on = true }
    }
}
