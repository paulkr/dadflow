import AVFoundation
import Speech

/// Apple's on-device SpeechAnalyzer (macOS 26+). Streams "volatile" (in-progress)
/// results word by word, then replaces them with finalized text, which is ideal for live typing.
@available(macOS 26.0, *)
final class AppleSpeechEngine: TranscriptionEngine {
    private let localeID: String
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: BufferConverter?
    private var resultsTask: Task<Void, Never>?

    private let lock = NSLock()
    private var finalized = ""
    private var volatileText = ""
    private var onText: ((String) -> Void)?

    init(localeID: String) {
        self.localeID = localeID
    }

    static func resolveLocale(_ id: String) async -> Locale {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) ?? Locale(identifier: "en-US")
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    /// Makes sure Apple's speech model for this language is installed (downloaded from Apple once).
    static func ensureAssets(localeID: String, status: ((String) -> Void)? = nil) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw DadFlowError.speechUnavailable("Apple on-device speech isn't available on this Mac")
        }
        let locale = await resolveLocale(localeID)
        let transcriber = makeTranscriber(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status?("Downloading Apple speech model…")
            try await request.downloadAndInstall()
        }
    }

    static func isInstalled(localeID: String) async -> Bool {
        let locale = await resolveLocale(localeID)
        let status = await AssetInventory.status(forModules: [makeTranscriber(locale: locale)])
        return status == .installed
    }

    func start(onText: @escaping (String) -> Void) async throws {
        self.onText = onText
        try await Self.ensureAssets(localeID: localeID)
        let locale = await Self.resolveLocale(localeID)
        let transcriber = Self.makeTranscriber(locale: locale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DadFlowError.audioFormatUnavailable
        }
        converter = BufferConverter(outputFormat: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(text: String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                NSLog("DadFlow: Apple speech results ended: \(error)")
            }
        }

        try await analyzer.start(inputSequence: stream)
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        guard let continuation, let converter, let converted = converter.convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private func handle(text: String, isFinal: Bool) {
        lock.lock()
        if isFinal {
            finalized = TextJoin.join(finalized, text)
            volatileText = ""
        } else {
            volatileText = text
        }
        let full = TextJoin.join(finalized, volatileText)
        let callback = onText
        lock.unlock()
        callback?(full)
    }

    private var composed: String {
        lock.lock(); defer { lock.unlock() }
        return TextJoin.join(finalized, volatileText)
    }

    func finish() async -> String {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            NSLog("DadFlow: finalize failed: \(error)")
        }
        // Wait for the last finalized results, but never hang forever.
        let resultsTask = self.resultsTask
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await resultsTask?.value }
            group.addTask { try? await Task.sleep(nanoseconds: 4_000_000_000) }
            await group.next()
            group.cancelAll()
        }
        return composed
    }

    func cancel() {
        lock.lock()
        onText = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
        resultsTask?.cancel()
        let analyzer = self.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
    }
}
