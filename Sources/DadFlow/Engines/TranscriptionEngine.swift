import AVFoundation

/// A speech-to-text engine that produces a running transcript while audio streams in.
///
/// `onText` receives the *entire* transcript so far (stable part + still-changing tail)
/// every time it changes; the live typer diffs it against what's already on screen.
protocol TranscriptionEngine: AnyObject {
    func start(onText: @escaping (String) -> Void) async throws
    /// Called from the audio thread.
    func feed(_ buffer: AVAudioPCMBuffer)
    /// Stop listening, flush everything, and return the final transcript.
    func finish() async -> String
    func cancel()
}

enum TextJoin {
    /// Joins two transcript pieces with exactly one space between them.
    static func join(_ a: String, _ b: String) -> String {
        let a2 = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let b2 = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a2.isEmpty { return b2 }
        if b2.isEmpty { return a2 }
        return a2 + " " + b2
    }
}

/// Holds audio that arrives before the engine is ready (e.g. while a model loads),
/// then hands everything to the engine in order.
final class BufferRouter {
    private let lock = NSLock()
    private var engine: TranscriptionEngine?
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingFrames: AVAudioFramePosition = 0
    private let maxPendingSeconds: Double = 120

    func reset() {
        lock.lock(); defer { lock.unlock() }
        engine = nil
        pending.removeAll()
        pendingFrames = 0
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if let engine {
            engine.feed(buffer)
            return
        }
        guard Double(pendingFrames) / buffer.format.sampleRate < maxPendingSeconds,
              let copy = buffer.deepCopy() else { return }
        pending.append(copy)
        pendingFrames += AVAudioFramePosition(buffer.frameLength)
    }

    func attach(_ engine: TranscriptionEngine) {
        lock.lock(); defer { lock.unlock() }
        for buffer in pending { engine.feed(buffer) }
        pending.removeAll()
        pendingFrames = 0
        self.engine = engine
    }
}
