import AVFoundation
import Foundation
import Speech

public actor StreamController {
    public enum StartResult: Sendable {
        case started(session: String)
        case alreadyRunning(session: String)
        case failed
    }

    private let buffer: EventBuffer
    private let sink: EventSink

    private var pipeline: SesPipeline?
    private var ctx: RuntimeContext?
    private var activeDevice: AVCaptureDevice?

    public init(buffer: EventBuffer) {
        self.buffer = buffer
        self.sink = BufferedEventSink(buffer: buffer)
    }

    public func isRunning() -> Bool {
        return pipeline != nil
    }

    public func currentSession() -> String? {
        return ctx?.session
    }

    #if DEBUG
        public func setContextForTesting(_ ctx: RuntimeContext?) {
            self.ctx = ctx
        }
    #endif

    public func start(args: Args) async -> StartResult {
        if let ctx {
            return .alreadyRunning(session: ctx.session)
        }

        let ctx = RuntimeContext()
        self.ctx = ctx

        // permissions
        guard await requestMicPermission() else {
            emitError(
                ctx: ctx,
                error: SesError(
                    code: .micPermissionDenied,
                    messageKey: "mic_permission_denied_message",
                    recoverable: true,
                    hintKey: "mic_permission_denied_hint"
                )
            )
            self.ctx = nil
            return .failed
        }

        let speechAuth = await requestSpeechPermission()
        guard speechAuth == .authorized else {
            emitError(
                ctx: ctx,
                error: SesError(
                    code: .speechPermissionDenied,
                    messageKey: "speech_permission_denied_message",
                    messageArgs: ["\(speechAuth)"],
                    recoverable: true,
                    hintKey: "speech_permission_denied_hint"
                )
            )
            self.ctx = nil
            return .failed
        }

        // pick device
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
        let device: AVCaptureDevice? = {
            if let id = args.deviceId, id >= 0, id < devices.count { return devices[id] }
            return AVCaptureDevice.default(for: .audio)
        }()

        guard let device else {
            emitError(
                ctx: ctx,
                error: SesError(
                    code: .deviceNotFound,
                    messageKey: "device_not_found_message",
                    messageArgs: ["\(args.deviceId ?? -1)"],
                    recoverable: true
                )
            )
            self.ctx = nil
            return .failed
        }

        activeDevice = device

        emitStatus(
            ctx: ctx,
            payload: [
                "state": "listening",
                "schema_version": 1,
                "device": device.localizedName,
                "device_uid": device.uniqueID,
                "locale": args.locale.identifier,
                "recommended": args.recommendedPreset,
                "level_interval_ms": args.levelIntervalMs,
                "vad_threshold_db": args.vadThresholdDb,
                "vad_hang_ms": args.vadHangMs,
                "vad_ema_alpha": args.vadEmaAlpha,
                "commit_silence_ms": args.commitSilenceMs,
                "warmup_ms": args.warmupMs,
                "commit_on_speech_end": args.commitOnSpeechEnd,
            ]
        )

        let pipeline = SesPipeline(ctx: ctx, args: args, sink: sink, device: device)
        await pipeline.start()
        self.pipeline = pipeline

        return .started(session: ctx.session)
    }

    public func stop() {
        guard let ctx else { return }
        pipeline?.stop()
        pipeline = nil
        activeDevice = nil
        self.ctx = nil

        emitStatus(
            ctx: ctx,
            payload: [
                "state": "stopped",
                "schema_version": 1,
            ]
        )
    }

    private func emitStatus(ctx: RuntimeContext, payload: [String: Any]) {
        sink.send(
            Event(
                type: .status,
                tsMs: ctx.nowMs(),
                session: ctx.session,
                payload: payload
            )
        )
    }

    private func emitError(ctx: RuntimeContext, error: SesError) {
        sink.send(
            Event(
                type: .error,
                tsMs: ctx.nowMs(),
                session: ctx.session,
                payload: error.payload()
            )
        )
    }
}
