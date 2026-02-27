import Foundation

/// ここが “確定テキスト” の唯一の生成者
/// - speech_endで即commit（任意）
/// - silenceでcommit（保険）
/// - ただし utterance_id 単位で二重commitは絶対に出さない
public actor CommitCoordinator {
    private let lock = NSLock()

    private let ctx: RuntimeContext
    private let sink: EventSink
    private let policy: CommitPolicy

    // transcript state
    private var lastText: String = ""
    private var lastSeq: Int64 = 0

    // utterance bookkeeping
    private var currentUtteranceId: Int64 = 0
    private var committedUtteranceId: Int64 = 0  // ここで二重commitガード

    private var speechStartMs: Int64 = 0
    private var speechEndMs: Int64 = 0
    private var speechStartSeq: Int64 = 0

    private var lastVoiceMs: Int64 = 0
    private var isSpeaking: Bool = false
    private var lastSilenceUtteranceId: Int64 = 0

    private var commitId: Int64 = 0
    private var lastCommitText: String = ""

    // last levels
    private var lastRawDb: Double = -160
    private var lastVadDb: Double = -160

    public init(ctx: RuntimeContext, sink: EventSink, policy: CommitPolicy) {
        self.ctx = ctx
        self.sink = sink
        self.policy = policy
    }

    public func onTranscript(_ t: TranscriptEvent) {
        lock.lock()
        defer { lock.unlock() }
        lastSeq = t.seq
        lastText = t.text
    }

    /// VADProcessorの結果を食わせる
    public func onVAD(
        nowMs: Int64, rawDb: Double, vadDb: Double, speechStart: Bool, speechEnd: Bool,
        utteranceId: Int64
    ) {
        lock.lock()
        defer { lock.unlock() }

        lastRawDb = rawDb
        lastVadDb = vadDb

        // state tracking
        if speechStart {
            currentUtteranceId = utteranceId
            isSpeaking = true
            lastVoiceMs = nowMs
            speechStartMs = nowMs
            speechEndMs = 0
            speechStartSeq = max(1, lastSeq)
            lastSilenceUtteranceId = 0
        } else if isSpeaking {
            // speaking継続中の「最後に声があった時刻」は、vadが閾値より上の間のみ更新されるべきだが
            // ここは VADState側が管理している想定なので、speechEndまでは手動更新しない
        }

        if speechEnd {
            isSpeaking = false
            speechEndMs = nowMs
            lastVoiceMs = nowMs

            if policy.commitOnSpeechEnd {
                emitCommitLocked(reason: "speech_end", nowMs: nowMs)
            }
            return
        }

        // silence commit（保険）
        if !isSpeaking, lastVoiceMs > 0, nowMs - lastVoiceMs >= policy.silenceMs {
            if lastSilenceUtteranceId == currentUtteranceId { return }
            sink.send(
                Event(
                    type: .silence, tsMs: nowMs, session: ctx.session,
                    payload: [
                        "audio_level_db": lastRawDb,
                        "vad_db": lastVadDb,
                        "utterance_id": currentUtteranceId,
                        "silence_ms": policy.silenceMs,
                    ]))
            lastSilenceUtteranceId = currentUtteranceId
            emitCommitLocked(reason: "silence", nowMs: nowMs)
        }
    }

    private func emitCommitLocked(reason: String, nowMs: Int64) {
        // 二重commitガード：utterance_id単位で一度だけ
        if currentUtteranceId > 0, committedUtteranceId == currentUtteranceId {
            return
        }

        let t = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }

        // これは「別発話で同じ文を言った」ケースを抑制（必要なら削ってもOK）
        if t == lastCommitText {
            // ただし utterance_id を進めるなら、ここで committedUtteranceId を立てるかは設計次第
            // 今回は「同文でも新発話ならcommitしていい」方が自然なので、抑制しない方が良いケースもある。
            // いったん抑制は残しつつ、utterance_idガードは必ず立てる。
        }

        commitId += 1
        lastCommitText = t
        committedUtteranceId = max(committedUtteranceId, currentUtteranceId)

        let endMs = (speechEndMs > 0) ? speechEndMs : nowMs
        let span = (speechStartMs > 0) ? max(0, endMs - speechStartMs) : 0
        let fromSeq = (speechStartSeq > 0) ? speechStartSeq : max(1, lastSeq)
        let toSeq = max(1, lastSeq)

        sink.send(
            Event(
                type: .commit, tsMs: nowMs, session: ctx.session,
                payload: [
                    "commit_id": commitId,
                    "commit_reason": reason,
                    "text": t,
                    "commit_from_seq": fromSeq,
                    "commit_to_seq": toSeq,
                    "commit_span_ms": span,
                    "audio_level_db": lastRawDb,
                    "vad_db": lastVadDb,
                    "utterance_id": currentUtteranceId,
                ]))
    }
}

extension CommitCoordinator: TranscriptSink {}
