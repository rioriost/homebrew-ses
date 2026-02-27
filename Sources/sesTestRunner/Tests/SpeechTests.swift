import Foundation
import Speech
import sesCore

func testSpeechTaskRegistryNoop() async throws {
    await MainActor.run {
        SpeechTaskRegistry.cancelAndClear()
        SpeechTaskRegistry.clear()
    }
    try assertTrue(true, "speech task registry no-op should not crash")
}

func testSpeechRecognizerInitFailed() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }

    await MainActor.run {
        let supportedLocale = SFSpeechRecognizer.supportedLocales().first ?? Locale.current
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in nil as SpeechRecognizerProtocol? }
        )
        engine.start(locale: supportedLocale, frames: frames, transcriptSink: transcriptSink)
    }

    let events = sink.snapshot()
    try assertTrue(events.count == 1, "should emit one error")
    try assertTrue(events[0].type == .error, "event type should be error")
    try assertTrue(
        events[0].payload["code"] as? String == "recognizer_init_failed",
        "error code should be recognizer_init_failed"
    )
}

func testSpeechRecognizerUnavailable() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }

    await MainActor.run {
        let supportedLocale = SFSpeechRecognizer.supportedLocales().first ?? Locale.current
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { (locale: Locale) in
                SFSpeechRecognizer(locale: locale)
            },
            availabilityOverride: { (_: SFSpeechRecognizer) in false }
        )
        engine.start(locale: supportedLocale, frames: frames, transcriptSink: transcriptSink)
    }

    let events = sink.snapshot()
    try assertTrue(events.count == 1, "should emit one error")
    try assertTrue(events[0].type == .error, "event type should be error")
    try assertTrue(
        events[0].payload["code"] as? String == "recognizer_unavailable",
        "error code should be recognizer_unavailable"
    )
}

func testSpeechRecognizerFramesNoCrash() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.yield(
            AudioFrame(samplesMono: [0, 0], sampleRate: 16000, timestampMs: 0)
        )
        continuation.finish()
    }

    await MainActor.run {
        let supportedLocale = SFSpeechRecognizer.supportedLocales().first ?? Locale.current
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            availabilityOverride: { _ in true }
        )
        engine.start(locale: supportedLocale, frames: frames, transcriptSink: transcriptSink)
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    let events = sink.snapshot()
    let ok = events.allSatisfy { event in
        switch event.type {
        case .error, .partial, .final, .delta:
            return true
        default:
            return false
        }
    }
    try assertTrue(ok, "events should be speech-related or error")
}

func testSpeechRecognizerEmitsPartialDeltaFinalWithFake() async throws {
    struct FakeTranscription: SpeechTranscriptionProtocol {
        let formattedString: String
    }
    struct FakeResult: SpeechRecognitionResultProtocol {
        let isFinal: Bool
        let bestTranscription: SpeechTranscriptionProtocol
    }
    final class FakeTask: SpeechRecognitionTaskProtocol {
        func cancel() {}
    }
    @MainActor
    final class FakeRecognizer: SpeechRecognizerProtocol {
        var isAvailable: Bool = true
        private var handler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

        func recognitionTask(
            with request: SFSpeechAudioBufferRecognitionRequest,
            resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
        ) -> SpeechRecognitionTaskWrapper {
            handler = resultHandler
            return SpeechRecognitionTaskBox(task: FakeTask(), rawTask: nil)
        }

        func emitResult(_ result: SpeechRecognitionResultProtocol) {
            handler?(result, nil)
        }
    }

    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }
    let fake = await MainActor.run { FakeRecognizer() }
    await MainActor.run {
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in fake },
            availabilityOverride: { (_: SpeechRecognizerProtocol) in true }
        )
        engine.start(locale: Locale.current, frames: frames, transcriptSink: transcriptSink)
    }

    await MainActor.run {
        fake.emitResult(
            FakeResult(
                isFinal: false,
                bestTranscription: FakeTranscription(formattedString: "hello")
            )
        )
        fake.emitResult(
            FakeResult(
                isFinal: true,
                bestTranscription: FakeTranscription(formattedString: "hello world")
            )
        )
    }

    let events = sink.snapshot()
    let partial = events.first { $0.type == .partial }
    let delta = events.first { $0.type == .delta }
    let final = events.first { $0.type == .final }

    try assertTrue(partial != nil, "should emit partial")
    try assertTrue(delta != nil, "should emit delta")
    try assertTrue(final != nil, "should emit final")

    try assertTrue(
        partial?.payload["text"] as? String == "hello",
        "partial text should match"
    )
    try assertTrue(
        partial?.payload["delta"] == nil,
        "partial should not include delta"
    )
    try assertTrue(
        delta?.payload["delta"] as? String == "hello",
        "delta payload should be hello"
    )
    try assertTrue(
        final?.payload["text"] as? String == "hello world",
        "final text should match"
    )
}

func testSpeechRecognizerSkipsDeltaWhenEmpty() async throws {
    struct FakeTranscription: SpeechTranscriptionProtocol {
        let formattedString: String
    }
    struct FakeResult: SpeechRecognitionResultProtocol {
        let isFinal: Bool
        let bestTranscription: SpeechTranscriptionProtocol
    }
    final class FakeTask: SpeechRecognitionTaskProtocol {
        func cancel() {}
    }
    @MainActor
    final class FakeRecognizer: SpeechRecognizerProtocol {
        var isAvailable: Bool = true
        private var handler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

        func recognitionTask(
            with request: SFSpeechAudioBufferRecognitionRequest,
            resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
        ) -> SpeechRecognitionTaskWrapper {
            handler = resultHandler
            return SpeechRecognitionTaskBox(task: FakeTask(), rawTask: nil)
        }

        func emitResult(_ result: SpeechRecognitionResultProtocol) {
            handler?(result, nil)
        }
    }

    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }
    let fake = await MainActor.run { FakeRecognizer() }
    await MainActor.run {
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in fake },
            availabilityOverride: { (_: SpeechRecognizerProtocol) in true }
        )
        engine.start(locale: Locale.current, frames: frames, transcriptSink: transcriptSink)
    }

    await MainActor.run {
        fake.emitResult(
            FakeResult(
                isFinal: false,
                bestTranscription: FakeTranscription(formattedString: "hello")
            )
        )
        fake.emitResult(
            FakeResult(
                isFinal: false,
                bestTranscription: FakeTranscription(formattedString: "hello")
            )
        )
    }

    let events = sink.snapshot()
    let deltaCount = events.filter { $0.type == .delta }.count
    let partialCount = events.filter { $0.type == .partial }.count

    try assertTrue(partialCount == 2, "should emit two partials")
    try assertTrue(deltaCount == 1, "should emit one delta")
}

func testSpeechRecognizerEmitsErrorWithFake() async throws {
    struct FakeTranscription: SpeechTranscriptionProtocol {
        let formattedString: String
    }
    struct FakeResult: SpeechRecognitionResultProtocol {
        let isFinal: Bool
        let bestTranscription: SpeechTranscriptionProtocol
    }
    final class FakeTask: SpeechRecognitionTaskProtocol {
        func cancel() {}
    }
    @MainActor
    final class FakeRecognizer: SpeechRecognizerProtocol {
        var isAvailable: Bool = true
        private var handler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

        func recognitionTask(
            with request: SFSpeechAudioBufferRecognitionRequest,
            resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
        ) -> SpeechRecognitionTaskWrapper {
            handler = resultHandler
            return SpeechRecognitionTaskBox(task: FakeTask(), rawTask: nil)
        }

        func emitError(_ error: Error) {
            handler?(nil, error)
        }
    }

    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }
    let fake = await MainActor.run { FakeRecognizer() }
    await MainActor.run {
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in fake },
            availabilityOverride: { (_: SpeechRecognizerProtocol) in true }
        )
        engine.start(locale: Locale.current, frames: frames, transcriptSink: transcriptSink)
    }

    await MainActor.run {
        struct FakeError: Error {}
        fake.emitError(FakeError())
    }

    let events = sink.snapshot()
    let error = events.first { $0.type == .error }
    try assertTrue(error != nil, "should emit error")
    try assertTrue(
        error?.payload["code"] as? String == "recognition_task_error",
        "error code should be recognition_task_error"
    )
}

func testSpeechRecognizerIgnoresNilResult() async throws {
    final class FakeTask: SpeechRecognitionTaskProtocol {
        func cancel() {}
    }
    @MainActor
    final class FakeRecognizer: SpeechRecognizerProtocol {
        var isAvailable: Bool = true
        private var handler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

        func recognitionTask(
            with request: SFSpeechAudioBufferRecognitionRequest,
            resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
        ) -> SpeechRecognitionTaskWrapper {
            handler = resultHandler
            return SpeechRecognitionTaskBox(task: FakeTask(), rawTask: nil)
        }

        func emitNil() {
            handler?(nil, nil)
        }
    }

    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }
    let fake = await MainActor.run { FakeRecognizer() }
    await MainActor.run {
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in fake },
            availabilityOverride: { (_: SpeechRecognizerProtocol) in true }
        )
        engine.start(locale: Locale.current, frames: frames, transcriptSink: transcriptSink)
    }

    await MainActor.run {
        fake.emitNil()
    }

    let events = sink.snapshot()
    try assertTrue(events.isEmpty, "should not emit events for nil result")
}

func testSpeechRecognizerSkipsWhitespaceResult() async throws {
    struct FakeTranscription: SpeechTranscriptionProtocol {
        let formattedString: String
    }
    struct FakeResult: SpeechRecognitionResultProtocol {
        let isFinal: Bool
        let bestTranscription: SpeechTranscriptionProtocol
    }
    final class FakeTask: SpeechRecognitionTaskProtocol {
        func cancel() {}
    }
    @MainActor
    final class FakeRecognizer: SpeechRecognizerProtocol {
        var isAvailable: Bool = true
        private var handler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

        func recognitionTask(
            with request: SFSpeechAudioBufferRecognitionRequest,
            resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
        ) -> SpeechRecognitionTaskWrapper {
            handler = resultHandler
            return SpeechRecognitionTaskBox(task: FakeTask(), rawTask: nil)
        }

        func emitResult(_ result: SpeechRecognitionResultProtocol) {
            handler?(result, nil)
        }
    }

    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }
    let fake = await MainActor.run { FakeRecognizer() }
    await MainActor.run {
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in fake },
            availabilityOverride: { (_: SpeechRecognizerProtocol) in true }
        )
        engine.start(locale: Locale.current, frames: frames, transcriptSink: transcriptSink)
    }

    await MainActor.run {
        fake.emitResult(
            FakeResult(
                isFinal: false,
                bestTranscription: FakeTranscription(formattedString: "  \n")
            )
        )
    }

    let events = sink.snapshot()
    try assertTrue(events.isEmpty, "should not emit events for whitespace-only result")
}

func testSpeechRecognizerFinalDoesNotEmitDelta() async throws {
    struct FakeTranscription: SpeechTranscriptionProtocol {
        let formattedString: String
    }
    struct FakeResult: SpeechRecognitionResultProtocol {
        let isFinal: Bool
        let bestTranscription: SpeechTranscriptionProtocol
    }
    final class FakeTask: SpeechRecognitionTaskProtocol {
        func cancel() {}
    }
    @MainActor
    final class FakeRecognizer: SpeechRecognizerProtocol {
        var isAvailable: Bool = true
        private var handler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

        func recognitionTask(
            with request: SFSpeechAudioBufferRecognitionRequest,
            resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
        ) -> SpeechRecognitionTaskWrapper {
            handler = resultHandler
            return SpeechRecognitionTaskBox(task: FakeTask(), rawTask: nil)
        }

        func emitResult(_ result: SpeechRecognitionResultProtocol) {
            handler?(result, nil)
        }
    }

    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let transcriptSink = CollectingTranscriptSink()
    let frames = AsyncStream<AudioFrame> { continuation in
        continuation.finish()
    }
    let fake = await MainActor.run { FakeRecognizer() }
    await MainActor.run {
        let engine = SpeechRecognizerEngine(
            ctx: ctx,
            sink: sink,
            recognizerFactory: { _ in fake },
            availabilityOverride: { (_: SpeechRecognizerProtocol) in true }
        )
        engine.start(locale: Locale.current, frames: frames, transcriptSink: transcriptSink)
    }

    await MainActor.run {
        fake.emitResult(
            FakeResult(
                isFinal: false,
                bestTranscription: FakeTranscription(formattedString: "hello")
            )
        )
        fake.emitResult(
            FakeResult(
                isFinal: true,
                bestTranscription: FakeTranscription(formattedString: "hello world")
            )
        )
    }

    try await Task.sleep(nanoseconds: 10_000_000)

    let events = sink.snapshot()
    let deltaCount = events.filter { $0.type == .delta }.count
    let partialCount = events.filter { $0.type == .partial }.count
    let finalCount = events.filter { $0.type == .final }.count

    try assertTrue(partialCount == 1, "should emit one partial")
    try assertTrue(finalCount == 1, "should emit one final")
    try assertTrue(deltaCount == 1, "should emit delta only for partial result")

    let transcripts = await transcriptSink.snapshot()
    try assertTrue(transcripts.count == 2, "should emit two transcript events")
    try assertTrue(
        transcripts[1].delta == " world",
        "final transcript delta should be suffix"
    )
}

func testTranscriptEventInit() async throws {
    let te = TranscriptEvent(seq: 3, text: "hello", delta: "he", isFinal: true)
    try assertTrue(te.seq == 3, "seq should be 3")
    try assertTrue(te.text == "hello", "text should be hello")
    try assertTrue(te.delta == "he", "delta should be he")
    try assertTrue(te.isFinal == true, "isFinal should be true")
}

func testSFSpeechRecognitionTaskAdapterCancel() async throws {
    guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
        try assertTrue(true, "recognizer not available on this locale")
        return
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    let task = recognizer.recognitionTask(with: request) { _, _ in }
    let adapter = SFSpeechRecognitionTaskAdapter(task: task)
    adapter.cancel()
    try assertTrue(true, "cancel should not crash")
}
