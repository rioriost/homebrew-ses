import AVFoundation
import Foundation
import sesCore

func testAudioCaptureInitStop() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let args = Args.parse(from: ["ses"])
    let capture = AudioCapture(ctx: ctx, sink: sink, args: args)
    capture.stop()
    try assertTrue(true, "AudioCapture init/stop should not crash")
}

func testAudioCaptureCaptureOutputYieldsMono() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let args = Args.parse(from: ["ses"])
    let capture = AudioCapture(ctx: ctx, sink: sink, args: args)

    var continuationRef: AsyncStream<AudioFrame>.Continuation?
    var yielded: [AudioFrame] = []
    let stream = AsyncStream<AudioFrame> { continuation in
        continuationRef = continuation
        capture.setContinuationForTesting(continuation)
    }

    let samples: [Int16] = [100, -100, 200, -200]
    guard
        let sampleBuffer = makeInt16SampleBuffer(
            samples: samples, sampleRate: 16000, channels: 2)
    else {
        throw TestFailure.assertionFailed("sample buffer should be created")
    }

    let output = AVCaptureAudioDataOutput()
    let connection = AVCaptureConnection(inputPorts: [], output: output)
    capture.captureOutput(output, didOutput: sampleBuffer, from: connection)
    continuationRef?.finish()
    for await frame in stream {
        yielded.append(frame)
        break
    }

    try assertTrue(yielded.count == 1, "should yield one audio frame")
    try assertTrue(yielded[0].samplesMono == [100, 200], "downmix should take channel 0")
    try assertTrue(yielded[0].sampleRate == 16000, "sampleRate should match")
    try assertTrue(yielded[0].timestampMs >= 0, "timestampMs should be non-negative")

    var continuationRef2: AsyncStream<AudioFrame>.Continuation?
    var yielded2: [AudioFrame] = []
    let stream2 = AsyncStream<AudioFrame> { continuation in
        continuationRef2 = continuation
        capture.setContinuationForTesting(continuation)
    }
    guard let videoSampleBuffer = makeVideoSampleBuffer() else {
        throw TestFailure.assertionFailed("video sample buffer should be created")
    }
    capture.captureOutput(output, didOutput: videoSampleBuffer, from: connection)
    continuationRef2?.finish()
    for await frame in stream2 {
        yielded2.append(frame)
        break
    }
    try assertTrue(yielded2.isEmpty, "should not yield for non-audio sample buffer")
}

func testStreamBasicDescriptionNilForNonAudioSampleBuffer() async throws {
    guard let videoSampleBuffer = makeVideoSampleBuffer() else {
        throw TestFailure.assertionFailed("video sample buffer should be created")
    }
    let asbd = streamBasicDescription(from: videoSampleBuffer)
    try assertTrue(
        asbd == nil,
        "streamBasicDescription should be nil for non-audio sample buffer"
    )
}

func testExtractInt16InterleavedNilForEmptyBlockBuffer() async throws {
    guard let emptySampleBuffer = makeEmptyAudioSampleBuffer() else {
        throw TestFailure.assertionFailed("empty sample buffer should be created")
    }
    let samples = extractInt16Interleaved(from: emptySampleBuffer)
    try assertTrue(
        samples == nil,
        "extractInt16Interleaved should be nil for empty block buffer"
    )
}

func testAudioCaptureHandlesRuntimeErrorNotification() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let args = Args.parse(from: ["ses"])
    let capture = AudioCapture(ctx: ctx, sink: sink, args: args)

    var exitCode: Int32?
    capture.setExitHandlerForTesting { code in
        exitCode = code
    }

    let err = NSError(
        domain: AVError.errorDomain,
        code: AVError.deviceWasDisconnected.rawValue,
        userInfo: nil
    )
    let note = Notification(
        name: AVCaptureSession.runtimeErrorNotification,
        object: capture.sessionForTesting(),
        userInfo: [AVCaptureSessionErrorKey: err]
    )
    NotificationCenter.default.post(note)

    let events = sink.snapshot()
    let errors = events.filter { $0.type == .error }
    try assertTrue(exitCode == 0, "exit handler should be called")
    try assertTrue(errors.count == 1, "should emit one error event")
    try assertTrue(
        errors[0].payload["code"] as? String == "device_disconnected",
        "error code should be device_disconnected"
    )
}

func testAudioCaptureRuntimeErrorDebugEmitsStatus() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let args = Args.parse(from: ["ses", "--debug"])
    let capture = AudioCapture(ctx: ctx, sink: sink, args: args)

    let err = NSError(domain: "unit_test", code: 42, userInfo: ["info": "x"])
    let note = Notification(
        name: AVCaptureSession.runtimeErrorNotification,
        object: capture.sessionForTesting(),
        userInfo: [AVCaptureSessionErrorKey: err]
    )
    NotificationCenter.default.post(note)

    let events = sink.snapshot()
    let status = events.filter { $0.type == .status }
    let errors = events.filter { $0.type == .error }
    try assertTrue(status.count == 1, "should emit one debug status")
    try assertTrue(errors.isEmpty, "should not emit error for non-disconnect runtime error")
    try assertTrue(
        status[0].payload["state"] as? String == "debug",
        "status state should be debug"
    )
    try assertTrue(
        status[0].payload["event"] as? String == "runtime_error",
        "debug event should be runtime_error"
    )
}

func testAudioCaptureWatchdogTimeoutEmitsError() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let args = Args.parse(from: [
        "ses",
        "--debug",
        "--watchdog-timeout-ms", "1",
        "--watchdog-interval-ms", "10",
    ])
    let capture = AudioCapture(ctx: ctx, sink: sink, args: args)

    var exitCode: Int32?
    capture.setExitHandlerForTesting { code in
        exitCode = code
    }

    capture.setLastSampleMsForTesting(0)
    capture.startWatchdogForTesting()
    defer { capture.stopWatchdogForTesting() }

    try await Task.sleep(nanoseconds: 100_000_000)

    let events = sink.snapshot()
    let status = events.filter {
        $0.type == .status && ($0.payload["event"] as? String) == "watchdog_timeout"
    }
    let errors = events.filter { $0.type == .error }
    try assertTrue(exitCode == 0, "exit handler should be called")
    try assertTrue(status.count == 1, "should emit watchdog debug status")
    try assertTrue(errors.count == 1, "should emit one error event")
    try assertTrue(
        capture.isWatchdogActiveForTesting() == false,
        "watchdog should stop after timeout"
    )
}

func testAudioCaptureHandlesSessionInterruptedNotification() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let args = Args.parse(from: ["ses"])
    let capture = AudioCapture(ctx: ctx, sink: sink, args: args)

    var exitCode: Int32?
    capture.setExitHandlerForTesting { code in
        exitCode = code
    }

    let interruptionName: Notification.Name
    if #available(macOS 15.0, *) {
        interruptionName = AVCaptureSession.wasInterruptedNotification
    } else {
        interruptionName = .AVCaptureSessionWasInterrupted
    }

    NotificationCenter.default.post(
        name: interruptionName,
        object: capture.sessionForTesting()
    )

    let events = sink.snapshot()
    let errors = events.filter { $0.type == .error }
    try assertTrue(exitCode == 0, "exit handler should be called")
    try assertTrue(errors.count == 1, "should emit one error event")
    try assertTrue(
        errors[0].payload["code"] as? String == "device_disconnected",
        "error code should be device_disconnected"
    )
}
