import AppKit
import Combine
import ServiceManagement

/// Where the floating dictation bar lives on screen.
enum PillPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right, bottomLeft, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bottom: return "Bottom center"
        case .top: return "Top center"
        case .left: return "Left edge"
        case .right: return "Right edge"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    /// Idle pill is drawn vertically when docked to a side edge.
    var isVertical: Bool { self == .left || self == .right }
}

/// The key you hold (or tap) to dictate.
enum Hotkey: String, CaseIterable, Identifiable {
    case fn, rightOption, rightCommand, rightControl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "fn / 🌐 (Globe)"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightControl: return "Right Control ⌃"
        }
    }

    var shortLabel: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        case .rightControl: return "right ⌃"
        }
    }

    var keyCodes: Set<UInt16> {
        switch self {
        case .fn: return [63, 179]
        case .rightOption: return [61]
        case .rightCommand: return [54]
        case .rightControl: return [62]
        }
    }

    /// Whether this specific key is currently held, using device-dependent
    /// modifier bits so e.g. the *left* Option key doesn't count.
    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        let raw = flags.rawValue
        switch self {
        case .fn: return flags.contains(.function)
        case .rightOption: return raw & 0x40 != 0     // NX_DEVICERALTKEYMASK
        case .rightCommand: return raw & 0x10 != 0    // NX_DEVICERCMDKEYMASK
        case .rightControl: return raw & 0x2000 != 0  // NX_DEVICERCTLKEYMASK
        }
    }
}

enum EngineKind: String, CaseIterable, Identifiable {
    case apple, whisper

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "Apple On-Device (fastest live typing)"
        case .whisper: return "OpenAI Whisper (runs locally)"
        }
    }

    static var appleAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
    case smallEn = "openai_whisper-small.en"
    case baseEn = "openai_whisper-base.en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .largeV3Turbo: return "Whisper Large v3 Turbo (best, 632 MB)"
        case .smallEn: return "Whisper Small, English only (≈ 220 MB)"
        case .baseEn: return "Whisper Base, English only (fastest, ≈ 75 MB)"
        }
    }
}

struct DictationLanguage: Identifiable, Hashable {
    let id: String
    let name: String

    /// Two-letter code Whisper understands ("en", "fr", …).
    var whisperCode: String { String(id.prefix(while: { $0 != "-" })) }

    static let all: [DictationLanguage] = [
        .init(id: "en-US", name: "English (US)"),
        .init(id: "en-CA", name: "English (Canada)"),
        .init(id: "en-GB", name: "English (UK)"),
        .init(id: "en-AU", name: "English (Australia)"),
        .init(id: "fr-CA", name: "French (Canada)"),
        .init(id: "fr-FR", name: "French (France)"),
        .init(id: "es-ES", name: "Spanish (Spain)"),
        .init(id: "es-MX", name: "Spanish (Mexico)"),
        .init(id: "de-DE", name: "German"),
        .init(id: "it-IT", name: "Italian"),
        .init(id: "pt-BR", name: "Portuguese (Brazil)"),
        .init(id: "zh-CN", name: "Chinese (Mandarin)"),
        .init(id: "ja-JP", name: "Japanese"),
        .init(id: "ko-KR", name: "Korean"),
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var position: PillPosition { didSet { defaults.set(position.rawValue, forKey: "position") } }
    @Published var hotkey: Hotkey { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var engine: EngineKind { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    @Published var whisperModel: WhisperModel { didSet { defaults.set(whisperModel.rawValue, forKey: "whisperModel") } }
    @Published var languageID: String { didSet { defaults.set(languageID, forKey: "language") } }
    @Published var showBarWhenIdle: Bool { didSet { defaults.set(showBarWhenIdle, forKey: "showBarWhenIdle") } }
    @Published var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    @Published var smartSpacing: Bool { didSet { defaults.set(smartSpacing, forKey: "smartSpacing") } }
    /// Dad Mode: steadier Whisper text. Locks words in at each pause and never types "...".
    @Published var dadMode: Bool { didSet { defaults.set(dadMode, forKey: "dadMode") } }
    @Published var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") } }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("DadFlow: launch-at-login change failed: \(error)")
            }
        }
    }

    private init() {
        let d = UserDefaults.standard
        position = PillPosition(rawValue: d.string(forKey: "position") ?? "") ?? .bottom
        hotkey = Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        let storedEngine = EngineKind(rawValue: d.string(forKey: "engine") ?? "")
        var chosenEngine = storedEngine ?? (EngineKind.appleAvailable ? .apple : .whisper)
        if chosenEngine == .apple && !EngineKind.appleAvailable { chosenEngine = .whisper }
        engine = chosenEngine
        whisperModel = WhisperModel(rawValue: d.string(forKey: "whisperModel") ?? "") ?? .largeV3Turbo
        let defaultLanguage: String = {
            let current = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            return DictationLanguage.all.contains(where: { $0.id == current }) ? current : "en-US"
        }()
        languageID = d.string(forKey: "language") ?? defaultLanguage
        showBarWhenIdle = d.object(forKey: "showBarWhenIdle") as? Bool ?? true
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        smartSpacing = d.object(forKey: "smartSpacing") as? Bool ?? true
        dadMode = d.object(forKey: "dadMode") as? Bool ?? true
        hasCompletedSetup = d.bool(forKey: "hasCompletedSetup")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
