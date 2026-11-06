import AVFoundation
import Foundation

/// Feeds an audio file through an engine at real-time speed and prints every live
/// transcript update, so streaming can be checked without a microphone.
enum SelfTest {
    static func run(path: String, engine kind: String) -> Never {
        Task { @MainActor in
            do {
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                let engine: TranscriptionEngine
                if kind == "whisper" || kind == "whisper-dad" {
                    let kit = try await ModelManager.shared.whisper(.largeV3Turbo)
                    engine = WhisperEngine(kit: kit, language: "en", steady: kind == "whisper-dad")
                } else if #available(macOS 26.0, *) {
                    engine = AppleSpeechEngine(localeID: "en-US")
                } else {
                    print("Apple engine needs macOS 26"); exit(1)
                }
                let started = Date()
                var updates = 0
                try await engine.start { text in
                    updates += 1
                    print(String(format: "[%5.2fs] %@", Date().timeIntervalSince(started), text))
                }
                let format = file.processingFormat
                let chunk: AVAudioFrameCount = 1600
                while file.framePosition < file.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                    try file.read(into: buffer, frameCount: chunk)
                    engine.feed(buffer)
                    try await Task.sleep(nanoseconds: UInt64(Double(buffer.frameLength) / format.sampleRate * 1_000_000_000))
                }
                let final = await engine.finish()
                print("FINAL (\(updates) live updates): \(final)")
                exit(0)
            } catch {
                print("Self-test failed: \(error)")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }
}
