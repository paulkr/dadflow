import AppKit
import Foundation
import WhisperKit

/// Downloads / loads speech models and reports their status to the UI.
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    enum Status: Equatable {
        case unknown
        case notDownloaded
        case downloaded
        case downloading(Double?)
        case loading
        case ready
        case failed(String)

        var description: String {
            switch self {
            case .unknown: return "Checking…"
            case .notDownloaded: return "Not downloaded yet"
            case .downloaded: return "Downloaded. It loads the first time you dictate."
            case .downloading(let p?): return "Downloading… \(Int(p * 100))%"
            case .downloading(nil): return "Downloading…"
            case .loading: return "Getting ready (first time can take a minute)…"
            case .ready: return "Ready"
            case .failed(let why): return "Problem: \(why)"
            }
        }

        var isBusy: Bool {
            switch self {
            case .downloading, .loading: return true
            default: return false
            }
        }
    }

    @Published private(set) var appleStatus: Status = .unknown
    @Published private(set) var whisperStatus: Status = .unknown

    private var whisperKit: WhisperKit?
    private var whisperVariant: String?
    private var whisperTask: Task<WhisperKit, Error>?
    private var whisperTaskVariant: String?

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DadFlow/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func localFolder(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.rawValue)", isDirectory: true)
    }

    static func isDownloaded(_ model: WhisperModel) -> Bool {
        let folder = localFolder(for: model)
        let fm = FileManager.default
        return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
            .allSatisfy { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    // MARK: Apple

    func refreshAppleStatus(localeID: String) {
        guard #available(macOS 26.0, *) else {
            appleStatus = .failed("Needs macOS 26 or newer")
            return
        }
        Task {
            appleStatus = await AppleSpeechEngine.isInstalled(localeID: localeID) ? .ready : .notDownloaded
        }
    }

    func prepareApple(localeID: String) async {
        guard #available(macOS 26.0, *) else {
            appleStatus = .failed("Needs macOS 26 or newer")
            return
        }
        if await AppleSpeechEngine.isInstalled(localeID: localeID) {
            appleStatus = .ready
            return
        }
        appleStatus = .downloading(nil)
        do {
            try await AppleSpeechEngine.ensureAssets(localeID: localeID)
            appleStatus = .ready
        } catch {
            appleStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: Whisper

    /// README screenshots: show every model as ready.
    func showcaseReady() {
        appleStatus = .ready
        whisperStatus = .ready
    }

    func refreshWhisperStatus(model: WhisperModel) {
        if whisperKit != nil && whisperVariant == model.rawValue {
            whisperStatus = .ready
        } else if whisperTask != nil && whisperTaskVariant == model.rawValue {
            // keep whatever progress status is showing
        } else {
            whisperStatus = Self.isDownloaded(model) ? .downloaded : .notDownloaded
        }
    }

    /// Returns a loaded Whisper model, downloading it the first time.
    func whisper(_ model: WhisperModel) async throws -> WhisperKit {
        if let kit = whisperKit, whisperVariant == model.rawValue { return kit }
        if let task = whisperTask, whisperTaskVariant == model.rawValue { return try await task.value }

        let task = Task { @MainActor () throws -> WhisperKit in
            var folder = Self.localFolder(for: model)
            if !Self.isDownloaded(model) {
                self.whisperStatus = .downloading(0)
                folder = try await WhisperKit.download(
                    variant: model.rawValue,
                    downloadBase: Self.modelsDirectory,
                    progressCallback: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in self.whisperStatus = .downloading(fraction) }
                    }
                )
            }
            self.whisperStatus = .loading
            let config = WhisperKitConfig(
                model: model.rawValue,
                modelFolder: folder.path,
                tokenizerFolder: Self.modelsDirectory,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            return try await WhisperKit(config)
        }
        whisperTask = task
        whisperTaskVariant = model.rawValue
        do {
            let began = Date()
            let kit = try await task.value
            whisperKit = kit
            whisperVariant = model.rawValue
            whisperStatus = .ready
            // A real download / first-time setup just finished: let them know with a ding.
            if Date().timeIntervalSince(began) > 3, AppSettings.shared.playSounds {
                NSSound(named: "Glass")?.play()
            }
            whisperTask = nil
            return kit
        } catch {
            whisperTask = nil
            whisperStatus = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Warm up whatever engine is selected so the first dictation is instant.
    func prepareSelected() {
        let settings = AppSettings.shared
        switch settings.engine {
        case .apple:
            Task { await prepareApple(localeID: settings.languageID) }
        case .whisper:
            Task { _ = try? await whisper(settings.whisperModel) }
        }
    }
}
