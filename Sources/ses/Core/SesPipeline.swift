import AVFoundation
import Foundation
import Speech

public final class SesPipeline: @unchecked Sendable {
    private let ctx: RuntimeContext
    private let args: Args
    private let sink: EventSink
    private let device: AVCaptureDevice

    private var capture: AudioCapture?
    private var vadTask: Task<Void, Never>?
    private var started: Bool = false

    public init(
        ctx: RuntimeContext,
        args: Args,
        sink: EventSink,
        device: AVCaptureDevice
    ) {
        self.ctx = ctx
        self.args = args
        self.sink = sink
        self.device = device
    }

    public func start() async {
        guard !started else { return }
        started = true

        let capture = AudioCapture(ctx: ctx, sink: sink, args: args)
        self.capture = capture
        let frames = capture.start(device: device)

        let vadState = VADState()
        let vadCfg = VADConfig(
            thresholdDb: args.vadThresholdDb,
            hangMs: args.vadHangMs,
            emaAlpha: args.vadEmaAlpha,
            warmupMs: args.warmupMs,
            levelIntervalMs: args.levelIntervalMs
        )
        let vad = VADProcessor(ctx: ctx, sink: sink, cfg: vadCfg, state: vadState)

        let commitPolicy = CommitPolicy(
            silenceMs: args.commitSilenceMs,
            commitOnSpeechEnd: args.commitOnSpeechEnd
        )
        let committer = CommitCoordinator(ctx: ctx, sink: sink, policy: commitPolicy)

        let locale = args.locale
        let ctxRef = ctx
        let sinkRef = sink
        await MainActor.run {
            let speech = SpeechRecognizerEngine(ctx: ctxRef, sink: sinkRef)
            speech.start(locale: locale, frames: frames, transcriptSink: committer)
        }

        vadTask = Task.detached {
            for await frame in frames {
                let (rawDb, vadDb, sStart, sEnd, uttId) = vad.process(frame: frame)

                await committer.onVAD(
                    nowMs: frame.timestampMs,
                    rawDb: rawDb,
                    vadDb: vadDb,
                    speechStart: sStart,
                    speechEnd: sEnd,
                    utteranceId: uttId
                )
            }
        }
    }

    public func stop() {
        guard started else { return }
        started = false

        capture?.stop()
        vadTask?.cancel()
        vadTask = nil

        Task { @MainActor in
            SpeechTaskRegistry.cancelAndClear()
        }
    }
}
