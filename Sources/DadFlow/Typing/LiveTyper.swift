import AppKit
import CoreGraphics

/// Types text into whatever app has keyboard focus, live, as the transcript changes.
///
/// You give it the full desired text; it compares that to what it has already typed,
/// backspaces over anything that changed, and types the new part. So when the speech
/// engine revises "their" → "there", only those characters get corrected on screen.
final class LiveTyper {
    /// Tag on our synthetic key events so the hotkey monitor can ignore them.
    static let syntheticMarker: Int64 = 0x0DAD_F10E

    private let lock = NSLock()
    private let condition = NSCondition()
    private var target: [Character] = []
    private var typed: [Character] = []
    private var session = 0
    private var working = false
    private let queue = DispatchQueue(label: "dadflow.typer", qos: .userInteractive)
    private let source = CGEventSource(stateID: .privateState)

    /// Characters typed per keystroke event. Small chunks look like live typing and keep
    /// slower apps (browsers, Electron apps) from dropping input.
    private let chunkSize = 6

    var typedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return typed.count
    }

    /// Start a fresh dictation; returns a session token for `update`.
    func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        session += 1
        target = []
        typed = []
        return session
    }

    /// Erase everything typed in this session and ignore any later updates for it.
    func eraseAndEnd(session token: Int) {
        lock.lock()
        guard token == session else { lock.unlock(); return }
        session += 1
        target = []
        let needsKick = !working
        if needsKick { working = true }
        lock.unlock()
        if needsKick { queue.async { [weak self] in self?.drain() } }
    }

    /// Set the full text that should be on screen for this session.
    func update(_ text: String, session token: Int) {
        lock.lock()
        guard token == session else { lock.unlock(); return }
        target = Array(text)
        let needsKick = !working
        if needsKick { working = true }
        lock.unlock()
        if needsKick { queue.async { [weak self] in self?.drain() } }
    }

    /// Resolves once everything requested has been typed.
    func waitUntilIdle() async {
        for _ in 0..<400 { // up to ~8 s
            lock.lock()
            let done = !working && typed == target
            lock.unlock()
            if done { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func drain() {
        while true {
            lock.lock()
            let goal = target
            let current = typed
            var prefix = 0
            let limit = min(goal.count, current.count)
            while prefix < limit && goal[prefix] == current[prefix] { prefix += 1 }

            if current.count > prefix {
                // Something we typed changed: erase back to where it diverges.
                let n = min(current.count - prefix, 12)
                typed.removeLast(n)
                lock.unlock()
                for _ in 0..<n { postBackspace() }
                usleep(1500)
                continue
            }
            if goal.count > prefix {
                let end = min(goal.count, prefix + chunkSize)
                let chunk = goal[prefix..<end]
                typed.append(contentsOf: chunk)
                lock.unlock()
                postText(String(chunk))
                usleep(4000)
                continue
            }
            working = false
            lock.unlock()
            return
        }
    }

    private func postText(_ text: String) {
        // Newlines are typed as Return so they work everywhere.
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, part) in parts.enumerated() {
            if i > 0 { postKey(36) }
            let utf16 = Array(part.utf16)
            guard !utf16.isEmpty else { continue }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
                utf16.withUnsafeBufferPointer { ptr in
                    event.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
                }
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func postBackspace() { postKey(51) }

    private func postKey(_ code: CGKeyCode) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Peeks at the focused text field (via Accessibility) to decide whether dictated text
/// needs a leading space, e.g. when continuing an existing sentence.
enum FocusContext {
    static func needsLeadingSpace() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return false }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range), range.location > 0 else { return false }

        var previous: Character?
        var prevRange = CFRange(location: range.location - 1, length: 1)
        if let prevValue = AXValueCreate(.cfRange, &prevRange) {
            var strRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, prevValue, &strRef) == .success,
               let s = strRef as? String {
                previous = s.last
            }
        }
        if previous == nil {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String {
                let utf16 = Array(value.utf16)
                if range.location <= utf16.count, let s = String(utf16CodeUnits: Array(utf16[..<range.location]), count: range.location) as String? {
                    previous = s.last
                }
            }
        }
        guard let previous else { return false }
        return !previous.isWhitespace && !"([{\"'“‘/-".contains(previous)
    }
}
