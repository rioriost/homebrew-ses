import Foundation

public final class VADState {
    private let lock = NSLock()

    public init() {}

    private var vadInitialized = false
    private var lastVadDb: Double = -160.0
    private var lastRawDb: Double = -160.0

    private var lastLevelEmitMs: Int64 = 0

    private var isSpeaking: Bool = false
    private var lastVoiceMs: Int64 = 0
    private var speechStartMs: Int64 = 0
    private var speechEndMs: Int64 = 0

    // “発話単位”ID：speech_startごとに増える
    private var utteranceId: Int64 = 0

    public func update(rawDb: Double, nowMs: Int64, alpha: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        lastRawDb = rawDb
        if !vadInitialized {
            lastVadDb = rawDb
            vadInitialized = true
        } else {
            lastVadDb = alpha * rawDb + (1.0 - alpha) * lastVadDb
        }
        return lastVadDb
    }

    public func shouldEmitLevel(nowMs: Int64, intervalMs: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if nowMs - lastLevelEmitMs >= intervalMs {
            lastLevelEmitMs = nowMs
            return true
        }
        return false
    }

    public func levelSnapshot() -> (rawDb: Double, vadDb: Double, speaking: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (lastRawDb, lastVadDb, isSpeaking)
    }

    public func vadUpdate(nowMs: Int64, vadDb: Double, thresholdDb: Double, hangMs: Int64) -> (
        speechStart: Bool, speechEnd: Bool, utteranceId: Int64
    ) {
        lock.lock()
        defer { lock.unlock() }

        var speechStart = false
        var speechEnd = false

        let above = vadDb >= thresholdDb
        if above {
            lastVoiceMs = nowMs
            if !isSpeaking {
                isSpeaking = true
                speechStart = true
                utteranceId += 1
                speechStartMs = nowMs
                speechEndMs = 0
            }
            return (speechStart, speechEnd, utteranceId)
        }

        if isSpeaking, lastVoiceMs > 0, nowMs - lastVoiceMs > hangMs {
            isSpeaking = false
            speechEnd = true
            speechEndMs = nowMs
        }

        return (speechStart, speechEnd, utteranceId)
    }

    public func currentTimes() -> (
        speechStartMs: Int64, speechEndMs: Int64, lastVoiceMs: Int64, isSpeaking: Bool,
        utteranceId: Int64
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (speechStartMs, speechEndMs, lastVoiceMs, isSpeaking, utteranceId)
    }
}
