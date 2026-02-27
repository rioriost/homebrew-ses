import AVFoundation
import Darwin
import Foundation
import Speech
import sesCore

enum TestFailure: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let message):
            return message
        }
    }
}

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure.assertionFailed(message)
    }
}

func run(_ name: String, _ block: () async throws -> Void) async -> Bool {
    do {
        try await block()
        print("PASS: \(name)")
        return true
    } catch {
        print("FAIL: \(name) - \(error)")
        return false
    }
}

func setPermissionOverridesSync(
    mic: Bool?,
    speech: SFSpeechRecognizerAuthorizationStatus?
) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        if let mic {
            await setMicPermissionOverride { mic }
        } else {
            await setMicPermissionOverride(nil)
        }

        if let speech {
            await setSpeechPermissionOverride { speech }
        } else {
            await setSpeechPermissionOverride(nil)
        }

        sem.signal()
    }
    sem.wait()
}

func clearPermissionOverridesSync() {
    setPermissionOverridesSync(mic: nil, speech: nil)
}

final class CollectingSink: EventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Event] = []

    func send(_ event: Event) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

actor CollectingTranscriptSink: TranscriptSink {
    private var events: [TranscriptEvent] = []

    func onTranscript(_ te: TranscriptEvent) async {
        events.append(te)
    }

    func snapshot() async -> [TranscriptEvent] {
        events
    }
}

final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

final class ExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int32?

    func set(_ code: Int32) {
        lock.lock()
        value = code
        lock.unlock()
    }

    func get() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class NoopPipeline: SesPipelineProtocol {
    private let onStart: (() -> Void)?

    init(onStart: (() -> Void)? = nil) {
        self.onStart = onStart
    }

    func start() async {
        onStart?()
    }
}

func parseJSONLine(_ line: String) throws -> [String: Any] {
    let data = line.data(using: .utf8) ?? Data()
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return obj ?? [:]
}

func parseJSONLines(_ text: String) throws -> [[String: Any]] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    return try lines.map { try parseJSONLine(String($0)) }
}

func encodeJSONLine(_ obj: [String: Any]) -> String {
    guard
        let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
        let text = String(data: data, encoding: .utf8)
    else { return "{}" }
    return text
}

func captureStdout(waitForWriteSeconds: TimeInterval = 0.1, _ block: () -> Void) -> String {
    let pipe = Pipe()
    let originalStdout = dup(fileno(stdout))
    fflush(stdout)
    dup2(pipe.fileHandleForWriting.fileDescriptor, fileno(stdout))

    block()

    if waitForWriteSeconds > 0 {
        Thread.sleep(forTimeInterval: waitForWriteSeconds)
    }

    fflush(stdout)
    pipe.fileHandleForWriting.closeFile()
    dup2(originalStdout, fileno(stdout))
    close(originalStdout)

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let didTimeout: Bool
}

func resolveSesCLIExecutable() -> (URL, [String]) {
    if let path = ProcessInfo.processInfo.environment["SES_CLI_PATH"], !path.isEmpty {
        return (URL(fileURLWithPath: path), [])
    }

    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let debug = cwd.appendingPathComponent(".build/debug/ses")
    if FileManager.default.isExecutableFile(atPath: debug.path) {
        return (debug, [])
    }

    let release = cwd.appendingPathComponent(".build/release/ses")
    if FileManager.default.isExecutableFile(atPath: release.path) {
        return (release, [])
    }

    return (URL(fileURLWithPath: "/usr/bin/env"), ["ses"])
}

func runProcess(
    executableURL: URL,
    arguments: [String],
    timeoutSeconds: TimeInterval
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        process.waitUntilExit()
        group.leave()
    }

    var didTimeout = false
    if group.wait(timeout: .now() + timeoutSeconds) == .timedOut {
        didTimeout = true
        process.terminate()
        process.waitUntilExit()
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? "",
        exitCode: process.terminationStatus,
        didTimeout: didTimeout
    )
}

func runSesCLI(args: [String], timeoutSeconds: TimeInterval) throws -> ProcessResult {
    let (exe, prefixArgs) = resolveSesCLIExecutable()
    return try runProcess(
        executableURL: exe,
        arguments: prefixArgs + args,
        timeoutSeconds: timeoutSeconds
    )
}

func makeInt16SampleBuffer(samples: [Int16], sampleRate: Double, channels: Int) -> CMSampleBuffer? {
    let length = samples.count * MemoryLayout<Int16>.size
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: length,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: length,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }
    let replaceStatus = samples.withUnsafeBytes { ptr in
        CMBlockBufferReplaceDataBytes(
            with: ptr.baseAddress!,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: length
        )
    }
    guard replaceStatus == kCMBlockBufferNoErr else { return nil }

    var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(channels * 2),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(channels * 2),
        mChannelsPerFrame: UInt32(channels),
        mBitsPerChannel: 16,
        mReserved: 0
    )
    var formatDesc: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDesc
    )
    guard formatStatus == noErr, let formatDesc else { return nil }

    var sampleBuffer: CMSampleBuffer?
    let sampleCount = samples.count / max(1, channels)
    let sampleStatus = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: formatDesc,
        sampleCount: sampleCount,
        sampleTimingEntryCount: 0,
        sampleTimingArray: nil,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }
    return sampleBuffer
}

func makeEmptyAudioSampleBuffer(sampleRate: Double = 16000, channels: Int = 1) -> CMSampleBuffer? {
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateEmpty(
        allocator: kCFAllocatorDefault,
        capacity: 0,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

    var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(channels * 2),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(channels * 2),
        mChannelsPerFrame: UInt32(channels),
        mBitsPerChannel: 16,
        mReserved: 0
    )
    var formatDesc: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDesc
    )
    guard formatStatus == noErr, let formatDesc else { return nil }

    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: formatDesc,
        sampleCount: 0,
        sampleTimingEntryCount: 0,
        sampleTimingArray: nil,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }
    return sampleBuffer
}

func makeVideoSampleBuffer(width: Int = 2, height: Int = 2) -> CMSampleBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: CFDictionary =
        [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else { return nil }

    var sampleBuffer: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid
    )
    var videoFormat: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &videoFormat
    )
    guard formatStatus == noErr, let videoFormat else { return nil }
    let sampleStatus = CMSampleBufferCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: videoFormat,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }
    return sampleBuffer
}
