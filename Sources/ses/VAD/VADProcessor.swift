import Foundation

public final class VADProcessor {
    private let ctx: RuntimeContext
    private let sink: EventSink
    private let cfg: VADConfig
    private let state: VADState

    public init(ctx: RuntimeContext, sink: EventSink, cfg: VADConfig, state: VADState) {
        self.ctx = ctx
        self.sink = sink
        self.cfg = cfg
        self.state = state
    }

    /// returns: (rawDb, vadDb, speechStart?, speechEnd?, utteranceId)
    public func process(frame: AudioFrame) -> (Double, Double, Bool, Bool, Int64) {
        let rawDb = rmsDbFS(frame.samplesMono)
        let vadDb = state.update(rawDb: rawDb, nowMs: frame.timestampMs, alpha: cfg.emaAlpha)

        if state.shouldEmitLevel(nowMs: frame.timestampMs, intervalMs: cfg.levelIntervalMs) {
            let snap = state.levelSnapshot()
            sink.send(
                Event(
                    type: .level, tsMs: frame.timestampMs, session: ctx.session,
                    payload: [
                        "audio_level_db": snap.rawDb,
                        "vad_db": snap.vadDb,
                        "speaking": snap.speaking,
                        "sample_rate": Int(frame.sampleRate),
                    ]))
        }

        // warmup中は speech_start/end を出さない（commitも出さない想定）
        if frame.timestampMs < cfg.warmupMs {
            return (rawDb, vadDb, false, false, state.currentTimes().utteranceId)
        }

        let upd = state.vadUpdate(
            nowMs: frame.timestampMs, vadDb: vadDb, thresholdDb: cfg.thresholdDb, hangMs: cfg.hangMs
        )

        if upd.speechStart {
            sink.send(
                Event(
                    type: .speech_start, tsMs: frame.timestampMs, session: ctx.session,
                    payload: [
                        "audio_level_db": rawDb,
                        "vad_db": vadDb,
                        "utterance_id": upd.utteranceId,
                    ]))
        }
        if upd.speechEnd {
            sink.send(
                Event(
                    type: .speech_end, tsMs: frame.timestampMs, session: ctx.session,
                    payload: [
                        "audio_level_db": rawDb,
                        "vad_db": vadDb,
                        "utterance_id": upd.utteranceId,
                    ]))
        }

        return (rawDb, vadDb, upd.speechStart, upd.speechEnd, upd.utteranceId)
    }
}
