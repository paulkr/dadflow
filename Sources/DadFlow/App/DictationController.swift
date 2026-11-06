import AppKit
import AVFoundation
import Combine

@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable { case idle, recording, finishing }
    enum Mode { case holding, handsFree }

    @Published private(set) var phase: Phase = .idle
    /// A short message shown in the bar (model loading, errors, …).
    @Published private(set) var message: String?
    /// Recent loudness values for the waveform, newest last.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 12)

    var onNeedsSetup: (() -> Void)?

    private let settings = AppSettings.shared
    private let capture = AudioCapture()
    private let router = BufferRouter()
    private let typer = LiveTyper()
    private let hotkeys = HotkeyMonitor()

    private var mode: Mode = .handsFree
    private var pressTime = Date.distantPast
    private var engine: TranscriptionEngine?
    private var typerSession = 0
    private var prefix = ""
    private var stopRequested = false
    private var messageTask: Task<Void, Never>?
    private var preparingMessage: String?
    private var lastLevelUpdate = Date.distantPast
    private var lastWhisperStatus: ModelManager.Status?
    private var cancellables = Set<AnyCancellable>()

    init() {
        capture.onBuffer = { [router] buffer in router.push(buffer) }
        capture.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.pushLevel(level) }
        }
        hotkeys.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkeys.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkeys.onOtherKey = { [weak self] in self?.otherKeyWhileHolding() }

        // While waiting on Whisper, show its download / loading progress in the bar.
        ModelManager.shared.$whisperStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                defer { self.lastWhisperStatus = status }
                if status == .ready, self.lastWhisperStatus?.isBusy == true,
                   self.preparingMessage == nil, self.phase == .idle {
                    self.flash("Whisper is ready! Hold \(self.settings.hotkey.shortLabel) to talk")
                    return
                }
                guard self.preparingMessage != nil, self.settings.engine == .whisper else { return }
                let text = "Whisper: \(status.description)"
                self.preparingMessage = text
                self.message = text
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        hotkeys.start()
    }

    // MARK: Inputs

    /// Clicking the floating bar.
    func barClicked() {
        switch phase {
        case .idle: start(mode: .handsFree)
        case .recording: stop()
        case .finishing: break
        }
    }

    private func hotkeyPressed() {
        switch phase {
        case .idle:
            pressTime = Date()
            start(mode: .holding)
        case .recording where mode == .handsFree:
            stop()
        default:
            break
        }
    }

    private func hotkeyReleased() {
        guard phase == .recording, mode == .holding else { return }
        if Date().timeIntervalSince(pressTime) < 0.35 {
            // A quick tap: keep listening hands-free until tapped again.
            mode = .handsFree
        } else {
            stop()
        }
    }

    private func otherKeyWhileHolding() {
        // fn + another key is a keyboard shortcut, not dictation.
        if phase == .recording, mode == .holding, typer.typedCount == 0,
           Date().timeIntervalSince(pressTime) < 1.5 {
            cancel()
        }
    }

    // MARK: Session

    func start(mode: Mode) {
        guard phase == .idle else { return }

        guard Permissions.accessibilityGranted else {
            flash("Allow Accessibility so Dad Flow can type for you")
            Permissions.promptAccessibility()
            onNeedsSetup?()
            return
        }
        switch Permissions.microphoneStatus {
        case .authorized: break
        case .notDetermined:
            Task {
                if await Permissions.requestMicrophone() {
                    self.start(mode: mode)
                } else {
                    self.flash("Microphone access is off")
                    self.onNeedsSetup?()
                }
            }
            return
        default:
            flash("Turn on the microphone for Dad Flow in System Settings")
            onNeedsSetup?()
            return
        }

        self.mode = mode
        stopRequested = false
        prefix = settings.smartSpacing && FocusContext.needsLeadingSpace() ? " " : ""
        typerSession = typer.begin()
        router.reset()

        do {
            try capture.start()
        } catch {
            flash(error.localizedDescription)
            return
        }
        phase = .recording
        play("Tink")

        let session = typerSession
        Task { await self.bringUpEngine(session: session) }
    }

    private func bringUpEngine(session: Int) async {
        do {
            let engine = try await makeEngine()
            guard session == typerSession, phase != .idle else {
                engine.cancel()
                return
            }
            let prefix = self.prefix
            let typer = self.typer
            try await engine.start(onText: { text in
                guard !text.isEmpty else { return }
                typer.update(prefix + text, session: session)
            })
            guard session == typerSession, phase != .idle else {
                engine.cancel()
                return
            }
            self.engine = engine
            router.attach(engine)
            clearPreparingMessage()
            if stopRequested { await finishSession(session: session) }
        } catch {
            NSLog("DadFlow: engine failed: \(error)")
            capture.stop()
            phase = .idle
            clearPreparingMessage()
            flash("Couldn't start: \(error.localizedDescription)")
        }
    }

    private func makeEngine() async throws -> TranscriptionEngine {
        if settings.engine == .apple, #available(macOS 26.0, *) {
            if ModelManager.shared.appleStatus != .ready {
                showPreparing("Getting speech model ready…")
            }
            let engine = AppleSpeechEngine(localeID: settings.languageID)
            return engine
        }
        let model = settings.whisperModel
        if ModelManager.shared.whisperStatus != .ready {
            showPreparing("Loading Whisper…")
        }
        let kit = try await ModelManager.shared.whisper(model)
        let lang = DictationLanguage.all.first(where: { $0.id == settings.languageID })?.whisperCode ?? "en"
        return WhisperEngine(kit: kit, language: lang, steady: settings.dadMode)
    }

    /// Stop listening and keep the text.
    func stop() {
        guard phase == .recording else { return }
        phase = .finishing
        capture.stop()
        play("Pop")
        if engine != nil {
            let session = typerSession
            Task { await finishSession(session: session) }
        } else {
            stopRequested = true // finishes once the engine is up
        }
    }

    private func finishSession(session: Int) async {
        guard let engine, session == typerSession else { return }
        let final = await engine.finish()
        if !final.isEmpty { typer.update(prefix + final, session: session) }
        await typer.waitUntilIdle()
        guard session == typerSession else { return }
        self.engine = nil
        phase = .idle
        levels = Array(repeating: 0, count: levels.count)
    }

    /// Stop listening and erase whatever was typed this time.
    func cancel() {
        guard phase != .idle else { return }
        capture.stop()
        engine?.cancel()
        engine = nil
        typer.eraseAndEnd(session: typerSession) // also ignores any late results
        typerSession = -1
        phase = .idle
        clearPreparingMessage()
        levels = Array(repeating: 0, count: levels.count)
    }

    // MARK: UI helpers

    private func pushLevel(_ level: Float) {
        guard phase == .recording else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) > 0.045 else { return }
        lastLevelUpdate = now
        var next = levels
        next.removeFirst()
        next.append(CGFloat(level))
        levels = next
    }

    private func showPreparing(_ text: String) {
        preparingMessage = text
        message = text
    }

    private func clearPreparingMessage() {
        if message == preparingMessage { message = nil }
        preparingMessage = nil
    }

    func flash(_ text: String, seconds: Double = 3.5) {
        messageTask?.cancel()
        message = text
        messageTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled, self.message == text { self.message = nil }
        }
    }

    private func play(_ name: String) {
        guard settings.playSounds, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.25
        sound.play()
    }
}
