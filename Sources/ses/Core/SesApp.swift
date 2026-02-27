import AVFoundation
import Darwin
import Foundation
import Speech

public protocol SesPipelineProtocol {
    func start() async
}

extension SesPipeline: SesPipelineProtocol {}

public struct SesApp {
    private var exitHandler: ((Int32) -> Void)?
    private var pipelineFactory:
        ((RuntimeContext, Args, EventSink, AVCaptureDevice) -> any SesPipelineProtocol)?
    private var keepAliveSecondsOverride: Double?

    public init() {}

    #if DEBUG
        public mutating func setExitHandlerForTesting(_ handler: ((Int32) -> Void)?) {
            exitHandler = handler
        }

        public mutating func setPipelineFactoryForTesting(
            _ factory: (
                (RuntimeContext, Args, EventSink, AVCaptureDevice) -> any SesPipelineProtocol
            )?
        ) {
            pipelineFactory = factory
        }

        public mutating func setKeepAliveSecondsForTesting(_ seconds: Double?) {
            keepAliveSecondsOverride = seconds
        }
    #endif

    public func run() async {
        let args = Args.parse()
        await run(args: args)
    }

    public func run(args: Args) async {
        let ctx = RuntimeContext()

        let config = OutputConfig(pretty: args.pretty, includeSession: !args.noSession)
        let sink = StdoutJSONLSink(config: config)

        // startup status
        sink.send(
            Event(
                type: .status, tsMs: ctx.nowMs(), session: ctx.session,
                payload: [
                    "state": "starting",
                    "schema_version": 1,
                    "locale": args.locale.identifier,
                    "device_id": args.deviceId ?? -1,
                    "recommended": args.recommendedPreset,
                    "pretty": args.pretty,
                    "no_session": args.noSession,
                    "debug": args.debug,
                    "mcp": args.mcp,
                    "level_interval_ms": args.levelIntervalMs,
                    "vad_threshold_db": args.vadThresholdDb,
                    "vad_hang_ms": args.vadHangMs,
                    "vad_ema_alpha": args.vadEmaAlpha,
                    "commit_silence_ms": args.commitSilenceMs,
                    "warmup_ms": args.warmupMs,
                    "commit_on_speech_end": args.commitOnSpeechEnd,
                ]))

        // device list
        if args.listDevices {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            )
            let inputs: [[String: Any]] = discovery.devices.enumerated().map { (i, d) in
                ["id": i, "name": d.localizedName, "uid": d.uniqueID]
            }
            sink.send(
                Event(
                    type: .status, tsMs: ctx.nowMs(), session: ctx.session,
                    payload: [
                        "state": "devices",
                        "schema_version": 1,
                        "inputs": inputs,
                    ]))
            if let exitHandler {
                exitHandler(0)
            } else {
                exit(0)
            }
            return
        }

        // permissions
        guard await requestMicPermission() else {
            sink.send(
                Event(
                    type: .error, tsMs: ctx.nowMs(), session: ctx.session,
                    payload: SesError(
                        code: .micPermissionDenied,
                        messageKey: "mic_permission_denied_message",
                        recoverable: true,
                        hintKey: "mic_permission_denied_hint"
                    ).payload()))
            return
        }

        let speechAuth = await requestSpeechPermission()
        guard speechAuth == .authorized else {
            sink.send(
                Event(
                    type: .error, tsMs: ctx.nowMs(), session: ctx.session,
                    payload: SesError(
                        code: .speechPermissionDenied,
                        messageKey: "speech_permission_denied_message",
                        messageArgs: ["\(speechAuth)"],
                        recoverable: true,
                        hintKey: "speech_permission_denied_hint"
                    ).payload()))
            return
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
            sink.send(
                Event(
                    type: .error, tsMs: ctx.nowMs(), session: ctx.session,
                    payload: SesError(
                        code: .deviceNotFound,
                        messageKey: "device_not_found_message",
                        messageArgs: ["\(args.deviceId ?? -1)"],
                        recoverable: true
                    ).payload()))
            return
        }

        // status
        sink.send(
            Event(
                type: .status, tsMs: ctx.nowMs(), session: ctx.session,
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
                ]))

        let pipeline =
            pipelineFactory?(ctx, args, sink, device)
            ?? SesPipeline(ctx: ctx, args: args, sink: sink, device: device)
        await pipeline.start()

        // keep alive
        if let keepAliveSecondsOverride {
            let nanos = UInt64(max(0, keepAliveSecondsOverride) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            return
        }
        while true { try? await Task.sleep(nanoseconds: 200_000_000) }
    }
}
