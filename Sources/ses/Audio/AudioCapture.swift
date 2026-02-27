import AVFoundation
import Darwin
import Foundation

public final class AudioCapture: NSObject {
    private let session = AVCaptureSession()
    private var continuation: AsyncStream<AudioFrame>.Continuation?
    private var activeDevice: AVCaptureDevice?
    private var watchdogTimer: DispatchSourceTimer?
    private var lastSampleMs: Int64 = 0
    private var watchdogIntervalMs: Int64 { args.watchdogIntervalMs }
    private var watchdogTimeoutMs: Int64 { args.watchdogTimeoutMs }

    private let ctx: RuntimeContext
    private let sink: EventSink
    private let args: Args
    private var exitHandler: ((Int32) -> Void)?

    public init(ctx: RuntimeContext, sink: EventSink, args: Args) {
        self.ctx = ctx
        self.sink = sink
        self.args = args
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceWasDisconnected(_:)),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )

        let interruptionName: Notification.Name
        if #available(macOS 15.0, *) {
            interruptionName = AVCaptureSession.wasInterruptedNotification
        } else {
            interruptionName = .AVCaptureSessionWasInterrupted
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterrupted(_:)),
            name: interruptionName,
            object: session
        )
    }

    #if DEBUG
        public func setContinuationForTesting(_ continuation: AsyncStream<AudioFrame>.Continuation?)
        {
            self.continuation = continuation
        }

        public func setExitHandlerForTesting(_ handler: ((Int32) -> Void)?) {
            self.exitHandler = handler
        }

        public func sessionForTesting() -> AVCaptureSession {
            session
        }

        public func setLastSampleMsForTesting(_ value: Int64) {
            lastSampleMs = value
        }

        public func startWatchdogForTesting() {
            startWatchdog()
        }

        public func stopWatchdogForTesting() {
            stopWatchdog()
        }

        public func isWatchdogActiveForTesting() -> Bool {
            watchdogTimer != nil
        }
    #endif

    private func emitDebug(_ fields: [String: Any]) {
        guard args.debug else { return }
        var payload: [String: Any] = [
            "state": "debug",
            "schema_version": 1,
            "source": "audio_capture",
        ]
        for (k, v) in fields {
            payload[k] = v
        }
        sink.send(
            Event(
                type: .status,
                tsMs: ctx.nowMs(),
                session: ctx.session,
                payload: payload
            )
        )
    }

    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "ses.audio.watchdog"))
        timer.schedule(
            deadline: .now() + .milliseconds(Int(watchdogIntervalMs)),
            repeating: .milliseconds(Int(watchdogIntervalMs))
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = self.ctx.nowMs()
            if now - self.lastSampleMs >= self.watchdogTimeoutMs {
                self.emitDebug([
                    "event": "watchdog_timeout",
                    "last_sample_ms": self.lastSampleMs,
                    "now_ms": now,
                    "timeout_ms": self.watchdogTimeoutMs,
                ])
                self.handleDeviceDisconnected()
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    @objc private func handleRuntimeError(_ note: Notification) {
        guard let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError else { return }
        emitDebug([
            "event": "runtime_error",
            "notification": note.name.rawValue,
            "domain": err.domain,
            "code": err.code,
            "user_info": String(describing: note.userInfo ?? [:]),
        ])
        if err.domain == AVError.errorDomain,
            err.code == AVError.deviceWasDisconnected.rawValue
        {
            handleDeviceDisconnected()
        }
    }

    @objc private func handleDeviceWasDisconnected(_ note: Notification) {
        guard let device = note.object as? AVCaptureDevice else { return }
        guard let active = activeDevice, device.uniqueID == active.uniqueID else { return }
        emitDebug([
            "event": "device_was_disconnected",
            "notification": note.name.rawValue,
            "device_uid": device.uniqueID,
            "device_name": device.localizedName,
            "active_device_uid": active.uniqueID,
        ])
        handleDeviceDisconnected()
    }

    @objc private func handleSessionInterrupted(_ note: Notification) {
        guard let interruptedSession = note.object as? AVCaptureSession,
            interruptedSession === session
        else { return }
        var fields: [String: Any] = [
            "event": "session_interrupted",
            "notification": note.name.rawValue,
        ]
        fields["user_info"] = String(describing: note.userInfo ?? [:])
        emitDebug(fields)
        handleDeviceDisconnected()
    }

    public func start(device: AVCaptureDevice) -> AsyncStream<AudioFrame> {
        AsyncStream { cont in
            self.continuation = cont
            self.activeDevice = device
            self.lastSampleMs = self.ctx.nowMs()

            self.session.beginConfiguration()
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
            } catch {
                self.sink.send(
                    Event(
                        type: .error,
                        tsMs: self.ctx.nowMs(),
                        session: self.ctx.session,
                        payload: SesError(
                            code: .deviceInputFailed,
                            messageKey: "device_input_failed",
                            recoverable: false
                        ).payload()
                    ))
                cont.finish()
                return
            }

            let output = AVCaptureAudioDataOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            output.setSampleBufferDelegate(
                self, queue: DispatchQueue(label: "ses.audio.capture.queue"))
            if self.session.canAddOutput(output) { self.session.addOutput(output) }

            self.session.commitConfiguration()
            self.session.startRunning()
            self.startWatchdog()

            self.sink.send(
                Event(
                    type: .status, tsMs: self.ctx.nowMs(), session: self.ctx.session,
                    payload: [
                        "state": "audio_started",
                        "schema_version": 1,
                    ]))
        }
    }

    public func stop() {
        session.stopRunning()
        stopWatchdog()
        continuation?.finish()
    }

    private func handleDeviceDisconnected() {
        sink.send(
            Event(
                type: .error,
                tsMs: ctx.nowMs(),
                session: ctx.session,
                payload: SesError(
                    code: .deviceDisconnected,
                    messageKey: "device_disconnected",
                    recoverable: false
                ).payload()
            )
        )
        stop()
        if let exitHandler {
            exitHandler(0)
        } else {
            exit(0)
        }
    }
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let nowMs = ctx.nowMs()
        self.lastSampleMs = nowMs

        guard let asbd = streamBasicDescription(from: sampleBuffer) else { return }
        let sampleRate = Double(asbd.mSampleRate)
        let channels = Int(asbd.mChannelsPerFrame)

        guard let interleaved = extractInt16Interleaved(from: sampleBuffer) else { return }
        let mono = downmixToMono(interleaved: interleaved, channels: max(1, channels))

        continuation?.yield(
            AudioFrame(samplesMono: mono, sampleRate: sampleRate, timestampMs: nowMs))
    }
}
