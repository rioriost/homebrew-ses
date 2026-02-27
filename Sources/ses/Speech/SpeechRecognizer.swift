import AVFoundation
import Foundation
import Speech

public struct TranscriptEvent: Sendable {
    public let seq: Int64
    public let text: String
    public let delta: String
    public let isFinal: Bool

    public init(seq: Int64, text: String, delta: String, isFinal: Bool) {
        self.seq = seq
        self.text = text
        self.delta = delta
        self.isFinal = isFinal
    }
}

public func commonPrefixDelta(prev: String, curr: String) -> String {
    if prev.isEmpty { return curr }
    if curr.isEmpty { return "" }
    if prev == curr { return "" }
    var iPrev = prev.startIndex
    var iCurr = curr.startIndex
    while iPrev < prev.endIndex && iCurr < curr.endIndex {
        if prev[iPrev] != curr[iCurr] { break }
        iPrev = prev.index(after: iPrev)
        iCurr = curr.index(after: iCurr)
    }
    return String(curr[iCurr...])
}

public protocol SpeechTranscriptionProtocol {
    var formattedString: String { get }
}

public protocol SpeechRecognitionResultProtocol {
    var isFinal: Bool { get }
    var bestTranscription: SpeechTranscriptionProtocol { get }
}

public protocol SpeechRecognitionTaskProtocol {
    func cancel()
}

public protocol SpeechRecognitionTaskWrapper {
    var task: SpeechRecognitionTaskProtocol { get }
    var rawTask: SFSpeechRecognitionTask? { get }
}

@MainActor
public protocol SpeechRecognizerProtocol {
    var isAvailable: Bool { get }
    func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
    ) -> SpeechRecognitionTaskWrapper
}

public struct SpeechRecognitionTaskBox: SpeechRecognitionTaskWrapper {
    public let task: SpeechRecognitionTaskProtocol
    public let rawTask: SFSpeechRecognitionTask?

    public init(task: SpeechRecognitionTaskProtocol, rawTask: SFSpeechRecognitionTask?) {
        self.task = task
        self.rawTask = rawTask
    }
}

public struct SFSpeechTranscriptionAdapter: SpeechTranscriptionProtocol {
    public let transcription: SFTranscription

    public init(transcription: SFTranscription) {
        self.transcription = transcription
    }

    public var formattedString: String { transcription.formattedString }
}

public struct SFSpeechRecognitionResultAdapter: SpeechRecognitionResultProtocol {
    public let result: SFSpeechRecognitionResult

    public init(result: SFSpeechRecognitionResult) {
        self.result = result
    }

    public var isFinal: Bool { result.isFinal }
    public var bestTranscription: SpeechTranscriptionProtocol {
        SFSpeechTranscriptionAdapter(transcription: result.bestTranscription)
    }
}

public final class SFSpeechRecognitionTaskAdapter: SpeechRecognitionTaskProtocol {
    public let task: SFSpeechRecognitionTask

    public init(task: SFSpeechRecognitionTask) {
        self.task = task
    }

    public func cancel() {
        task.cancel()
    }
}

public final class SFSpeechRecognizerAdapter: SpeechRecognizerProtocol {
    public let recognizer: SFSpeechRecognizer

    public init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    public var isAvailable: Bool { recognizer.isAvailable }

    public func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void
    ) -> SpeechRecognitionTaskWrapper {
        let task = recognizer.recognitionTask(with: request) { result, error in
            let wrapped = result.map { SFSpeechRecognitionResultAdapter(result: $0) }
            resultHandler(wrapped, error)
        }
        return SpeechRecognitionTaskBox(
            task: SFSpeechRecognitionTaskAdapter(task: task),
            rawTask: task
        )
    }
}

@MainActor
public final class SpeechRecognizerEngine {
    private let ctx: RuntimeContext
    private let sink: EventSink
    private let recognizerFactory: (Locale) -> SpeechRecognizerProtocol?
    private let availabilityOverride: ((SpeechRecognizerProtocol) -> Bool)?

    public init(
        ctx: RuntimeContext,
        sink: EventSink,
        recognizerFactory: @escaping (Locale) -> SpeechRecognizerProtocol?,
        availabilityOverride: ((SpeechRecognizerProtocol) -> Bool)? = nil
    ) {
        self.ctx = ctx
        self.sink = sink
        self.recognizerFactory = recognizerFactory
        self.availabilityOverride = availabilityOverride
    }

    public init(
        ctx: RuntimeContext,
        sink: EventSink,
        recognizerFactory: @escaping (Locale) -> SFSpeechRecognizer? = {
            SFSpeechRecognizer(locale: $0)
        },
        availabilityOverride: ((SFSpeechRecognizer) -> Bool)? = nil
    ) {
        self.ctx = ctx
        self.sink = sink
        self.recognizerFactory = { locale in
            guard let recognizer = recognizerFactory(locale) else { return nil }
            return SFSpeechRecognizerAdapter(recognizer: recognizer)
        }
        self.availabilityOverride = availabilityOverride.map { override in
            { recognizer in
                guard let adapter = recognizer as? SFSpeechRecognizerAdapter else {
                    return recognizer.isAvailable
                }
                return override(adapter.recognizer)
            }
        }
    }

    public func start(
        locale: Locale, frames: AsyncStream<AudioFrame>, transcriptSink: TranscriptSink
    ) {
        guard let recognizer = recognizerFactory(locale) else {
            sink.send(
                Event(
                    type: .error, tsMs: ctx.nowMs(), session: ctx.session,
                    payload: SesError(
                        code: .recognizerInitFailed,
                        messageKey: "recognizer_init_failed_message",
                        messageArgs: [String(describing: locale.identifier)],
                        recoverable: true
                    ).payload()))
            return
        }
        let isAvailable = availabilityOverride?(recognizer) ?? recognizer.isAvailable
        guard isAvailable else {
            sink.send(
                Event(
                    type: .error, tsMs: ctx.nowMs(), session: ctx.session,
                    payload: SesError(
                        code: .recognizerUnavailable,
                        messageKey: "recognizer_unavailable_message",
                        recoverable: true
                    ).payload()))
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        var seq: Int64 = 0
        var lastTextLocal = ""

        let taskBox = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                self.sink.send(
                    Event(
                        type: .error, tsMs: self.ctx.nowMs(), session: self.ctx.session,
                        payload: SesError(
                            code: .recognitionTaskError,
                            messageKey: "recognition_task_error_message",
                            recoverable: true,
                            underlying: error.localizedDescription
                        ).payload()))
                Task { @MainActor in SpeechTaskRegistry.clear() }
                return
            }
            guard let result else { return }

            let txt = result.bestTranscription.formattedString.trimmingCharacters(
                in: .whitespacesAndNewlines)
            if txt.isEmpty { return }

            seq += 1
            let delta = commonPrefixDelta(prev: lastTextLocal, curr: txt)
            lastTextLocal = txt

            let te = TranscriptEvent(seq: seq, text: txt, delta: delta, isFinal: result.isFinal)
            Task { await transcriptSink.onTranscript(te) }

            self.sink.send(
                Event(
                    type: result.isFinal ? .final : .partial, tsMs: self.ctx.nowMs(),
                    session: self.ctx.session,
                    payload: [
                        "seq": seq,
                        "text": txt,
                    ]))
            if !result.isFinal && !delta.isEmpty {
                self.sink.send(
                    Event(
                        type: .delta, tsMs: self.ctx.nowMs(), session: self.ctx.session,
                        payload: [
                            "seq": seq,
                            "delta": delta,
                        ]))
            }
        }
        if let rawTask = taskBox.rawTask {
            SpeechTaskRegistry.set(rawTask)
        }

        // frames → request.append
        Task { @MainActor in
            for await frame in frames {
                guard
                    let format = AVAudioFormat(
                        commonFormat: .pcmFormatInt16, sampleRate: frame.sampleRate, channels: 1,
                        interleaved: true)
                else { continue }
                guard
                    let pcmBuffer = AVAudioPCMBuffer(
                        pcmFormat: format, frameCapacity: AVAudioFrameCount(frame.samplesMono.count)
                    )
                else { continue }
                pcmBuffer.frameLength = pcmBuffer.frameCapacity

                frame.samplesMono.withUnsafeBufferPointer { src in
                    guard let base = src.baseAddress else { return }
                    memcpy(
                        pcmBuffer.int16ChannelData![0], base,
                        frame.samplesMono.count * MemoryLayout<Int16>.size)
                }
                request.append(pcmBuffer)
            }
            request.endAudio()
            SpeechTaskRegistry.cancelAndClear()
        }
    }
}
