import Foundation
import sesCore

func testVADConfigInit() async throws {
    let config = VADConfig(
        thresholdDb: -30.0,
        hangMs: 250,
        emaAlpha: 0.2,
        warmupMs: 1200,
        levelIntervalMs: 200
    )

    try assertTrue(config.thresholdDb == -30.0, "thresholdDb should be -30.0")
    try assertTrue(config.hangMs == 250, "hangMs should be 250")
    try assertTrue(config.emaAlpha == 0.2, "emaAlpha should be 0.2")
    try assertTrue(config.warmupMs == 1200, "warmupMs should be 1200")
    try assertTrue(config.levelIntervalMs == 200, "levelIntervalMs should be 200")
}

func testVADProcessorProcess() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let cfg = VADConfig(
        thresholdDb: -10.0,
        hangMs: 50,
        emaAlpha: 1.0,
        warmupMs: 50,
        levelIntervalMs: 0
    )
    let state = VADState()
    let processor = VADProcessor(ctx: ctx, sink: sink, cfg: cfg, state: state)

    let warm = AudioFrame(samplesMono: [Int16.max], sampleRate: 16000, timestampMs: 0)
    let r1 = processor.process(frame: warm)
    try assertTrue(r1.2 == false && r1.3 == false, "warmup should not emit speech transitions")

    let speech = AudioFrame(samplesMono: [Int16.max], sampleRate: 16000, timestampMs: 100)
    let r2 = processor.process(frame: speech)
    try assertTrue(r2.2 == true, "speechStart should be true")

    let silence = AudioFrame(samplesMono: [0], sampleRate: 16000, timestampMs: 200)
    let r3 = processor.process(frame: silence)
    try assertTrue(r3.3 == true, "speechEnd should be true")

    let events = sink.snapshot()
    let levels = events.filter { $0.type == .level }
    let starts = events.filter { $0.type == .speech_start }
    let ends = events.filter { $0.type == .speech_end }
    try assertTrue(levels.count >= 1, "should emit level events")
    try assertTrue(starts.count == 1, "should emit one speech_start")
    try assertTrue(ends.count == 1, "should emit one speech_end")
}

func testVADProcessorLevelIntervalNoEmit() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let cfg = VADConfig(
        thresholdDb: -30.0,
        hangMs: 100,
        emaAlpha: 1.0,
        warmupMs: 0,
        levelIntervalMs: 1000
    )
    let state = VADState()
    let processor = VADProcessor(ctx: ctx, sink: sink, cfg: cfg, state: state)

    _ = processor.process(
        frame: AudioFrame(samplesMono: [Int16.max], sampleRate: 16000, timestampMs: 1000))
    _ = processor.process(
        frame: AudioFrame(samplesMono: [Int16.max], sampleRate: 16000, timestampMs: 1500))

    let levels = sink.snapshot().filter { $0.type == .level }
    try assertTrue(levels.count == 1, "should emit only one level event within interval")
}

func testVADStateUpdateAndLevel() async throws {
    let state = VADState()

    let vad1 = state.update(rawDb: -10, nowMs: 10, alpha: 0.5)
    try assertTrue(vad1 == -10, "first update should match rawDb")

    let vad2 = state.update(rawDb: -20, nowMs: 20, alpha: 0.5)
    try assertTrue(vad2 == -15, "ema should be average of -20 and -10")

    try assertTrue(state.shouldEmitLevel(nowMs: 100, intervalMs: 50) == true, "first level emit")
    try assertTrue(
        state.shouldEmitLevel(nowMs: 120, intervalMs: 50) == false, "no emit within interval")
    try assertTrue(state.shouldEmitLevel(nowMs: 160, intervalMs: 50) == true, "emit after interval")

    let snapshot = state.levelSnapshot()
    try assertTrue(snapshot.rawDb == -20, "snapshot rawDb should be -20")
    try assertTrue(snapshot.vadDb == -15, "snapshot vadDb should be -15")
    try assertTrue(snapshot.speaking == false, "snapshot speaking should be false")
}

func testVADStateSpeechTransitions() async throws {
    let state = VADState()

    let start = state.vadUpdate(nowMs: 100, vadDb: -5, thresholdDb: -10, hangMs: 100)
    try assertTrue(start.speechStart == true, "speechStart should be true")
    try assertTrue(start.speechEnd == false, "speechEnd should be false")
    try assertTrue(start.utteranceId == 1, "utteranceId should be 1")

    let mid = state.vadUpdate(nowMs: 150, vadDb: -12, thresholdDb: -10, hangMs: 100)
    try assertTrue(mid.speechStart == false, "speechStart should be false")
    try assertTrue(mid.speechEnd == false, "speechEnd should be false")
    try assertTrue(mid.utteranceId == 1, "utteranceId should be 1")

    let end = state.vadUpdate(nowMs: 250, vadDb: -12, thresholdDb: -10, hangMs: 100)
    try assertTrue(end.speechStart == false, "speechStart should be false")
    try assertTrue(end.speechEnd == true, "speechEnd should be true")
    try assertTrue(end.utteranceId == 1, "utteranceId should be 1")

    let times = state.currentTimes()
    try assertTrue(times.speechStartMs == 100, "speechStartMs should be 100")
    try assertTrue(times.speechEndMs == 250, "speechEndMs should be 250")
    try assertTrue(times.lastVoiceMs == 100, "lastVoiceMs should be 100")
    try assertTrue(times.isSpeaking == false, "isSpeaking should be false")
    try assertTrue(times.utteranceId == 1, "utteranceId should be 1")
}
