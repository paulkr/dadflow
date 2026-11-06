import AVFoundation
import WhisperKit

/// Streams audio through OpenAI Whisper (via WhisperKit / Core ML, fully on-device).
///
/// Every ~0.4 s it re-transcribes the not-yet-confirmed audio. All segments except the
/// last are "confirmed" and frozen; the last segment is a live guess that may still be
/// revised (the typer fixes revisions with backspaces).
///
/// In steady mode ("Dad Mode") the live text flickers less when you pause to think:
/// punctuation at the very end is held back until Whisper is sure of it, and "..." is
/// never typed.
final class WhisperEngine: TranscriptionEngine {
    private let kit: WhisperKit
    private let language: String?
    private let steady: Bool
    private var suppressed: [Int] = []

    private let lock = NSLock()
    private var samples: [Float] = []
    private let converter = BufferConverter(outputFormat: BufferConverter.whisperFormat)

    private var running = false
    private var loopTask: Task<Void, Never>?
    private var confirmedText = ""
    private var confirmedEnd = 0 // sample index where unconfirmed audio begins
    private var hypothesis = ""
    private var onText: ((String) -> Void)?

    private static let sampleRate = 16_000

    init(kit: WhisperKit, language: String?, steady: Bool = false) {
        self.kit = kit
        self.language = language
        self.steady = steady
        if steady, let tokenizer = kit.tokenizer {
            // Stop Whisper from writing ellipses for thinking pauses.
            let special = tokenizer.specialTokens.specialTokenBegin
            let ids = ["...", " ...", "…", " …", "..", " .."].compactMap { text -> Int? in
                let t = tokenizer.encode(text: text).filter { $0 < special }
                return t.count == 1 ? t[0] : nil
            }
            suppressed = Array(Set(ids))
        }
    }

    func start(onText: @escaping (String) -> Void) async throws {
        lock.lock()
        self.onText = onText
        running = true
        lock.unlock()
        loopTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loop()
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let out = converter.convert(buffer), let data = out.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: data, count: Int(out.frameLength))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private func loop() async {
        var lastCount = 0
        while isRunning && !Task.isCancelled {
            lock.lock()
            let count = samples.count
            lock.unlock()
            if count - lastCount < Self.sampleRate * 2 / 5 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                continue
            }
            lastCount = count
            await step(final: false)
        }
    }

    private func decodeOptions() -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            suppressBlank: true,
            supressTokens: suppressed,
            noSpeechThreshold: 0.6
        )
    }

    private func step(final: Bool) async {
        lock.lock()
        let offset = confirmedEnd
        let window = offset < samples.count ? Array(samples[offset...]) : []
        lock.unlock()

        if ProcessInfo.processInfo.environment["DADFLOW_DEBUG"] != nil {
            let peak = window.map(abs).max() ?? 0
            print("whisper step final=\(final) window=\(window.count) peak=\(peak) voice=\(Self.hasVoice(window))")
        }
        guard window.count >= Self.sampleRate / 4, Self.hasVoice(window) else {
            if final || window.count >= Self.sampleRate {
                // Silence: nothing new to say.
                lock.lock()
                hypothesis = ""
                if steady {
                    // Skip the silence so the next window starts close to the next words.
                    confirmedEnd = max(confirmedEnd, samples.count - Self.sampleRate / 4)
                }
                lock.unlock()
                emit()
            }
            return
        }

        let segments: [TranscriptionSegment]
        do {
            let results = try await kit.transcribe(audioArray: window, decodeOptions: decodeOptions())
            segments = results.flatMap(\.segments).filter { !tidy($0.text).isEmpty }
            if ProcessInfo.processInfo.environment["DADFLOW_DEBUG"] != nil {
                print("whisper raw:", results.map(\.text), "segments:", results.flatMap(\.segments).map(\.text))
            }
        } catch {
            NSLog("DadFlow: whisper transcribe failed: \(error)")
            return
        }

        lock.lock()
        let texts = segments.map { tidy($0.text) }

        if final {
            confirmedText = TextJoin.join(confirmedText, texts.joined(separator: " "))
            hypothesis = ""
        } else if segments.count >= 2 {
            confirmedText = TextJoin.join(confirmedText, texts.dropLast().joined(separator: " "))
            let end = Int((segments[segments.count - 2].end * Float(Self.sampleRate)).rounded())
            confirmedEnd = min(samples.count, offset + max(0, min(end, window.count)))
            hypothesis = texts.last!
        } else if let only = segments.first, window.count > Self.sampleRate * 22 {
            // One very long segment: lock it in so the window stays under Whisper's 30 s limit.
            confirmedText = TextJoin.join(confirmedText, texts[0])
            let end = Int((only.end * Float(Self.sampleRate)).rounded())
            confirmedEnd = min(samples.count, offset + max(Self.sampleRate, min(end, window.count)))
            hypothesis = ""
        } else {
            hypothesis = texts.joined(separator: " ")
        }
        if steady && !final {
            // Hold back end-of-text punctuation until Whisper is sure (it flickers otherwise).
            hypothesis = Self.dropTrailingPunctuation(hypothesis)
        }
        lock.unlock()
        emit()
    }

    private func emit() {
        lock.lock()
        let text = TextJoin.join(confirmedText, hypothesis)
        let callback = onText
        lock.unlock()
        callback?(text)
    }

    private func tidy(_ text: String) -> String {
        var t = Self.clean(text)
        if steady {
            t = t.replacingOccurrences(of: #"\s*(?:\.{2,}|…)\s*"#, with: " ", options: .regularExpression)
            t = t.trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    static func dropTrailingPunctuation(_ text: String) -> String {
        var t = Substring(text)
        while let last = t.last, ".,;:!?…".contains(last) { t = t.dropLast() }
        return String(t)
    }

    /// Strip Whisper's non-speech annotations like "[BLANK_AUDIO]" or "*music*".
    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*[^*]*\*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cheap energy-based voice check so silence doesn't make Whisper hallucinate.
    static func hasVoice(_ window: [Float]) -> Bool {
        let frame = 480 // 30 ms
        var i = 0
        while i + frame <= window.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += window[j] * window[j] }
            if sqrt(sum / Float(frame)) > 0.012 { return true }
            i += frame
        }
        return false
    }

    func finish() async -> String {
        lock.lock()
        running = false
        lock.unlock()
        await loopTask?.value
        await step(final: true)
        lock.lock(); defer { lock.unlock() }
        return TextJoin.join(confirmedText, hypothesis)
    }

    func cancel() {
        lock.lock()
        running = false
        onText = nil
        lock.unlock()
        loopTask?.cancel()
    }
}
