import AVFoundation
import Foundation
import Speech
import sesCore

func testArgsDefaults() async throws {
    let args = Args.parse(from: ["ses"])

    try assertTrue(args.listDevices == false, "listDevices should be false")
    try assertTrue(args.deviceId == nil, "deviceId should be nil")
    try assertTrue(args.locale.identifier == Locale.current.identifier, "locale should be current")
    try assertTrue(args.pretty == false, "pretty should be false")
    try assertTrue(args.noSession == false, "noSession should be false")
    try assertTrue(args.debug == false, "debug should be false")
    try assertTrue(args.mcp == false, "mcp should be false")
    try assertTrue(args.version == false, "version should be false")
    try assertTrue(args.levelIntervalMs == 200, "levelIntervalMs should be 200")
    try assertTrue(args.vadThresholdDb == -30.0, "vadThresholdDb should be -30")
    try assertTrue(args.vadHangMs == 250, "vadHangMs should be 250")
    try assertTrue(args.vadEmaAlpha == 0.20, "vadEmaAlpha should be 0.20")
    try assertTrue(args.commitSilenceMs == 700, "commitSilenceMs should be 700")
    try assertTrue(args.warmupMs == 1200, "warmupMs should be 1200")
    try assertTrue(args.watchdogTimeoutMs == 3000, "watchdogTimeoutMs should be 3000")
    try assertTrue(args.watchdogIntervalMs == 1000, "watchdogIntervalMs should be 1000")
    try assertTrue(args.recommendedPreset == false, "recommendedPreset should be false")
    try assertTrue(args.commitOnSpeechEnd == true, "commitOnSpeechEnd should be true")
}

func testArgsRecommendedPreset() async throws {
    let args = Args.parse(from: ["ses", "--recommended"])

    try assertTrue(args.recommendedPreset == true, "recommendedPreset should be true")
    try assertTrue(args.vadThresholdDb == -35.0, "vadThresholdDb should be -35")
    try assertTrue(args.vadHangMs == 800, "vadHangMs should be 800")
    try assertTrue(args.vadEmaAlpha == 0.15, "vadEmaAlpha should be 0.15")
    try assertTrue(args.commitSilenceMs == 900, "commitSilenceMs should be 900")
}

func testArgsOverridesAndClamp() async throws {
    let args = Args.parse(from: [
        "ses",
        "--device-id", "3",
        "--locale", "ja_JP",
        "--vad-ema-alpha", "0.999",
        "--vad-threshold-db", "-20",
        "--vad-hang-ms", "150",
        "--commit-silence-ms", "500",
        "--level-interval-ms", "100",
        "--no-commit-on-speech-end",
        "--mcp",
        "--pretty",
        "--no-session",
        "--debug",
        "--version",
    ])

    try assertTrue(args.deviceId == 3, "deviceId should be 3")
    try assertTrue(args.locale.identifier == "ja_JP", "locale should be ja_JP")
    try assertTrue(args.vadEmaAlpha == 0.90, "vadEmaAlpha should be clamped to 0.90")
    try assertTrue(args.vadThresholdDb == -20, "vadThresholdDb should be -20")
    try assertTrue(args.vadHangMs == 150, "vadHangMs should be 150")
    try assertTrue(args.commitSilenceMs == 500, "commitSilenceMs should be 500")
    try assertTrue(args.levelIntervalMs == 100, "levelIntervalMs should be 100")
    try assertTrue(args.commitOnSpeechEnd == false, "commitOnSpeechEnd should be false")
    try assertTrue(args.mcp == true, "mcp should be true")
    try assertTrue(args.pretty == true, "pretty should be true")
    try assertTrue(args.noSession == true, "noSession should be true")
    try assertTrue(args.debug == true, "debug should be true")
    try assertTrue(args.version == true, "version should be true")
}

func testSesErrorPayload() async throws {
    let err = SesError(
        code: .deviceNotFound,
        message: "missing",
        recoverable: true,
        hint: "hint",
        underlying: "u"
    )
    let payload = err.payload()

    try assertTrue(
        payload["code"] as? String == "device_not_found", "code should be device_not_found")
    try assertTrue(payload["message"] as? String == "missing", "message should be missing")
    try assertTrue(payload["recoverable"] as? Bool == true, "recoverable should be true")
    try assertTrue(payload["hint"] as? String == "hint", "hint should be hint")
    try assertTrue(payload["underlying"] as? String == "u", "underlying should be u")
}

func testSesErrorMessageKeyOverride() async throws {
    L10n.setOverride { key, _, _ in
        switch key {
        case "msg_key":
            return "override:msg_key %@ %@"
        case "hint_key":
            return "override:hint_key %@"
        default:
            return "override:\(key)"
        }
    }
    defer { L10n.setOverride(nil) }

    let err = SesError(
        code: .deviceNotFound,
        messageKey: "msg_key",
        messageArgs: ["a", "b"],
        recoverable: true,
        hintKey: "hint_key",
        hintArgs: ["c"],
        underlying: "u"
    )
    let payload = err.payload()

    try assertTrue(
        payload["message"] as? String == "override:msg_key a b", "message should use override")
    try assertTrue(payload["hint"] as? String == "override:hint_key c", "hint should use override")
    try assertTrue(payload["recoverable"] as? Bool == true, "recoverable should be true")
    try assertTrue(payload["underlying"] as? String == "u", "underlying should be u")
}

func testStdoutJSONLSinkPrettyIncludesSession() async throws {
    let sink = StdoutJSONLSink(config: OutputConfig(pretty: true, includeSession: true))
    let event = Event(type: .status, tsMs: 123, session: "s1", payload: ["state": "listening"])

    let output = captureStdout(waitForWriteSeconds: 0.1) {
        sink.send(event)
    }

    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    try assertTrue(trimmed.isEmpty == false, "should print JSON")
    let data = trimmed.data(using: .utf8) ?? Data()
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    try assertTrue(obj?["type"] as? String == "status", "type should be status")
    try assertTrue(obj?["ts_ms"] as? Int == 123, "ts_ms should be 123")
    try assertTrue(obj?["session"] as? String == "s1", "session should be s1")
    try assertTrue(obj?["state"] as? String == "listening", "state should be listening")
}

func testStdoutJSONLSinkOmitsSession() async throws {
    let sink = StdoutJSONLSink(config: OutputConfig(pretty: false, includeSession: false))
    let event = Event(type: .level, tsMs: 456, session: "s2", payload: ["level": 5])

    let output = captureStdout(waitForWriteSeconds: 0.1) {
        sink.send(event)
    }

    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    try assertTrue(trimmed.isEmpty == false, "should print JSON")
    let data = trimmed.data(using: .utf8) ?? Data()
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    try assertTrue(obj?["type"] as? String == "level", "type should be level")
    try assertTrue(obj?["ts_ms"] as? Int == 456, "ts_ms should be 456")
    try assertTrue(obj?["session"] == nil, "session should be omitted")
    try assertTrue(obj?["level"] as? Int == 5, "level should be 5")
}

func testL10nDefaultAndOverride() async throws {
    let key = "ses_test_missing_key"
    let raw = L10n.string(key)
    try assertTrue(raw == key, "missing key should return key")

    L10n.setOverride { key, _, _ in
        return "override:\(key)"
    }
    defer { L10n.setOverride(nil) }

    let overridden = L10n.string(key)
    try assertTrue(overridden == "override:\(key)", "override should apply")
}

func testOutputConfigInit() async throws {
    let config = OutputConfig(pretty: true, includeSession: false)
    try assertTrue(config.pretty == true, "pretty should be true")
    try assertTrue(config.includeSession == false, "includeSession should be false")
}

func testPermissionsOverrides() async throws {
    setPermissionOverridesSync(mic: true, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let speechStatus = await requestSpeechPermission()
    let micAllowed = await requestMicPermission()

    try assertTrue(speechStatus == .authorized, "speech permission should be authorized")
    try assertTrue(micAllowed == true, "mic permission should be true")
}

func testSesAppMicPermissionDenied() async throws {
    setPermissionOverridesSync(mic: false, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let args = Args.parse(from: ["ses", "--no-session"])
    var didTimeout = false
    let output = captureStdout(waitForWriteSeconds: 0.2) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await SesApp().run(args: args)
            sem.signal()
        }
        if sem.wait(timeout: .now() + 2.0) == .timedOut {
            didTimeout = true
        }
    }

    try assertTrue(didTimeout == false, "SesApp should finish before timeout")
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    try assertTrue(lines.count >= 2, "should print startup and error lines")
    let startObj = try parseJSONLine(String(lines[0]))
    try assertTrue(startObj["type"] as? String == "status", "type should be status")
    try assertTrue(startObj["state"] as? String == "starting", "state should be starting")

    let obj = try parseJSONLine(String(lines[1]))
    try assertTrue(obj["type"] as? String == "error", "type should be error")
    try assertTrue(
        obj["code"] as? String == "mic_permission_denied",
        "code should be mic_permission_denied"
    )
}

func testSesAppSpeechPermissionDenied() async throws {
    setPermissionOverridesSync(mic: true, speech: .denied)
    defer { clearPermissionOverridesSync() }

    let args = Args.parse(from: ["ses", "--no-session"])
    var didTimeout = false
    let output = captureStdout(waitForWriteSeconds: 0.2) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await SesApp().run(args: args)
            sem.signal()
        }
        if sem.wait(timeout: .now() + 2.0) == .timedOut {
            didTimeout = true
        }
    }

    try assertTrue(didTimeout == false, "SesApp should finish before timeout")
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    try assertTrue(lines.count >= 2, "should print startup and error lines")
    let startObj = try parseJSONLine(String(lines[0]))
    try assertTrue(startObj["type"] as? String == "status", "type should be status")
    try assertTrue(startObj["state"] as? String == "starting", "state should be starting")

    let obj = try parseJSONLine(String(lines[1]))
    try assertTrue(obj["type"] as? String == "error", "type should be error")
    try assertTrue(
        obj["code"] as? String == "speech_permission_denied",
        "code should be speech_permission_denied"
    )
}

func testSesAppListDevicesEmitsStatus() async throws {
    let exitBox = ExitCodeBox()
    let args = Args.parse(from: ["ses", "--list-devices", "--no-session"])
    var didTimeout = false
    let output = captureStdout(waitForWriteSeconds: 0.2) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            var app = SesApp()
            app.setExitHandlerForTesting { code in
                exitBox.set(code)
            }
            await app.run(args: args)
            sem.signal()
        }
        if sem.wait(timeout: .now() + 2.0) == .timedOut {
            didTimeout = true
        }
    }

    try assertTrue(didTimeout == false, "SesApp list devices should finish before timeout")
    try assertTrue(exitBox.get() == 0, "exit handler should be called with 0")
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    try assertTrue(lines.count >= 2, "should print startup and devices lines")
    let startObj = try parseJSONLine(String(lines[0]))
    try assertTrue(startObj["type"] as? String == "status", "type should be status")
    try assertTrue(startObj["state"] as? String == "starting", "state should be starting")

    let obj = try parseJSONLine(String(lines[1]))
    try assertTrue(obj["type"] as? String == "status", "type should be status")
    try assertTrue(obj["state"] as? String == "devices", "state should be devices")
    try assertTrue(obj["inputs"] is [[String: Any]], "inputs should be an array")
}

func testCLIDeviceListRuns() async throws {
    let result = try runSesCLI(args: ["--list-devices"], timeoutSeconds: 5)
    try assertTrue(result.didTimeout == false, "process should exit before timeout")
    try assertTrue(result.exitCode == 0, "exit code should be 0")
    let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)
    try assertTrue(lines.count >= 2, "should print startup and devices lines")
    let startObj = try parseJSONLine(String(lines[0]))
    try assertTrue(startObj["type"] as? String == "status", "type should be status")
    try assertTrue(startObj["state"] as? String == "starting", "state should be starting")

    let obj = try parseJSONLine(String(lines[1]))
    try assertTrue(obj["type"] as? String == "status", "type should be status")
    try assertTrue(obj["state"] as? String == "devices", "state should be devices")
    try assertTrue(obj["inputs"] is [[String: Any]], "inputs should be an array")
}

func testCLINormalRunForTenSeconds() async throws {
    let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    )
    let devices = discovery.devices
    if devices.isEmpty {
        print("SKIP: CLI.normalRunForTenSeconds (no audio devices)")
        return
    }

    var ranAtLeastOne = false
    for (i, device) in devices.enumerated() {
        let result = try runSesCLI(args: ["--device-id", "\(i)"], timeoutSeconds: 10)
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)

        if lines.isEmpty {
            let stderrLower = result.stderr.lowercased()
            if stderrLower.contains("permission") || stderrLower.contains("denied") {
                print(
                    "SKIP: CLI.normalRunForTenSeconds (permission denied for \(device.localizedName))"
                )
                continue
            }
            try assertTrue(
                false,
                "no output for \(device.localizedName); stderr=\(result.stderr), timed_out=\(result.didTimeout)"
            )
        }

        var sawPermissionDenied = false
        var firstStatus: [String: Any]? = nil
        for line in lines {
            let obj = try parseJSONLine(String(line))
            if obj["type"] as? String == "error" {
                let code = obj["code"] as? String
                if code == "mic_permission_denied" || code == "speech_permission_denied" {
                    sawPermissionDenied = true
                    break
                }
            }
            if obj["type"] as? String == "status", firstStatus == nil {
                firstStatus = obj
            }
        }

        if sawPermissionDenied {
            print(
                "SKIP: CLI.normalRunForTenSeconds (permission denied for \(device.localizedName))"
            )
            continue
        }

        guard let status = firstStatus else {
            try assertTrue(
                false,
                "no status output for \(device.localizedName); stderr=\(result.stderr), timed_out=\(result.didTimeout)"
            )
            continue
        }

        try assertTrue(result.didTimeout == true, "process should be terminated after timeout")
        try assertTrue(lines.count >= 1, "should print at least one status line")
        try assertTrue(status["type"] as? String == "status", "type should be status")
        let state = status["state"] as? String
        try assertTrue(
            state == "starting" || state == "listening", "state should be starting or listening")
        ranAtLeastOne = true
    }

    try assertTrue(ranAtLeastOne, "should run at least one accessible audio device")
}

func testSesAppNormalRunKeepsAliveForTenSeconds() async throws {
    setPermissionOverridesSync(mic: true, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let args = Args.parse(from: ["ses", "--no-session"])
    var didTimeout = false
    let output = captureStdout(waitForWriteSeconds: 0.2) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            var app = SesApp()
            app.setPipelineFactoryForTesting { _, _, _, _ in
                NoopPipeline()
            }
            app.setKeepAliveSecondsForTesting(10.0)
            await app.run(args: args)
            sem.signal()
        }
        if sem.wait(timeout: .now() + 12.0) == .timedOut {
            didTimeout = true
        }
    }

    try assertTrue(didTimeout == false, "SesApp should finish before timeout")
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    try assertTrue(lines.count >= 2, "should print startup and listening lines")
    let startObj = try parseJSONLine(String(lines[0]))
    try assertTrue(startObj["type"] as? String == "status", "type should be status")
    try assertTrue(startObj["state"] as? String == "starting", "state should be starting")

    let obj = try parseJSONLine(String(lines[1]))
    try assertTrue(obj["type"] as? String == "status", "type should be status")
    try assertTrue(obj["state"] as? String == "listening", "state should be listening")
}

func testCommitPolicyInit() async throws {
    let policy = CommitPolicy(silenceMs: 123, commitOnSpeechEnd: false)
    try assertTrue(policy.silenceMs == 123, "silenceMs should be 123")
    try assertTrue(policy.commitOnSpeechEnd == false, "commitOnSpeechEnd should be false")
}

func testCommitCoordinatorSpeechEnd() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let policy = CommitPolicy(silenceMs: 500, commitOnSpeechEnd: true)
    let committer = CommitCoordinator(ctx: ctx, sink: sink, policy: policy)

    await committer.onTranscript(
        TranscriptEvent(seq: 1, text: "hello", delta: "hello", isFinal: false))
    await committer.onVAD(
        nowMs: 100, rawDb: -10, vadDb: -10, speechStart: true, speechEnd: false, utteranceId: 1)
    await committer.onVAD(
        nowMs: 200, rawDb: -12, vadDb: -12, speechStart: false, speechEnd: true, utteranceId: 1)

    let commits = sink.snapshot().filter { $0.type == .commit }
    try assertTrue(commits.count == 1, "commit should be emitted once")
    try assertTrue(
        commits[0].payload["commit_reason"] as? String == "speech_end",
        "commit_reason should be speech_end")
    try assertTrue(
        commits[0].payload["text"] as? String == "hello",
        "commit text should be hello")
}

func testCommitCoordinatorSilence() async throws {
    let ctx = RuntimeContext(session: "s")
    let sink = CollectingSink()
    let policy = CommitPolicy(silenceMs: 300, commitOnSpeechEnd: false)
    let committer = CommitCoordinator(ctx: ctx, sink: sink, policy: policy)

    await committer.onTranscript(TranscriptEvent(seq: 2, text: "hi", delta: "hi", isFinal: false))
    await committer.onVAD(
        nowMs: 100, rawDb: -10, vadDb: -10, speechStart: true, speechEnd: false, utteranceId: 2)
    await committer.onVAD(
        nowMs: 200, rawDb: -10, vadDb: -10, speechStart: false, speechEnd: true, utteranceId: 2)
    await committer.onVAD(
        nowMs: 600, rawDb: -40, vadDb: -40, speechStart: false, speechEnd: false, utteranceId: 2)
    await committer.onVAD(
        nowMs: 700, rawDb: -40, vadDb: -40, speechStart: false, speechEnd: false, utteranceId: 2)

    let events = sink.snapshot()
    let commits = events.filter { $0.type == .commit }
    let silences = events.filter { $0.type == .silence }

    try assertTrue(commits.count == 1, "silence commit should be emitted once")
    try assertTrue(
        commits[0].payload["commit_reason"] as? String == "silence",
        "commit_reason should be silence")
    try assertTrue(silences.count == 1, "silence event should be emitted once")
}

func testRuntimeContextNowMs() async throws {
    let ctx = RuntimeContext(session: "s")
    let t1 = ctx.nowMs()
    try await Task.sleep(nanoseconds: 5_000_000)
    let t2 = ctx.nowMs()

    try assertTrue(t1 >= 0, "t1 should be non-negative")
    try assertTrue(t2 >= t1, "t2 should be >= t1")
}

func testSesPipelineStartStop() async throws {
    let ctx = RuntimeContext(session: "s")
    guard let device = AVCaptureDevice.default(for: .audio) else {
        print("SKIP: SesPipeline.startStop (no audio device)")
        return
    }

    let args = Args.parse(from: ["ses", "--no-session"])
    let sink = CollectingSink()
    let pipeline = SesPipeline(ctx: ctx, args: args, sink: sink, device: device)
    await pipeline.start()
    pipeline.stop()
    pipeline.stop()
    try assertTrue(true, "SesPipeline start/stop should not crash")
}

func testSesAppPipelineFactoryDeviceSelection() async throws {
    setPermissionOverridesSync(mic: true, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
        print("SKIP: SesApp.pipelineFactoryDeviceSelection (no audio device)")
        return
    }

    var app = SesApp()
    var capturedDevice: AVCaptureDevice?
    app.setPipelineFactoryForTesting { _, _, _, device in
        capturedDevice = device
        return NoopPipeline()
    }
    app.setKeepAliveSecondsForTesting(0)

    let args = Args.parse(from: ["ses", "--device-id", "999", "--no-session"])
    await app.run(args: args)

    try assertTrue(
        capturedDevice?.uniqueID == defaultDevice.uniqueID,
        "should use default device when id is out of range")
}

func testCommonPrefixDeltaBasic() async throws {
    let delta = commonPrefixDelta(prev: "hello", curr: "hello world")
    try assertTrue(delta == " world", "delta should be the suffix after common prefix")
}

func testCommonPrefixDeltaNoCommonPrefix() async throws {
    let delta = commonPrefixDelta(prev: "abc", curr: "xyz")
    try assertTrue(delta == "xyz", "delta should be full curr when no common prefix")
}

func testCommonPrefixDeltaWithEmptyCurrent() async throws {
    let delta = commonPrefixDelta(prev: "hello", curr: "")
    try assertTrue(delta == "", "delta should be empty when curr is empty")
}
