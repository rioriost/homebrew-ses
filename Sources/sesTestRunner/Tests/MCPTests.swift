import Darwin
import Foundation
import sesCore

func testMCPServerSetConfigStringParsing() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 12,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "device_id": "2",
                "locale": "ja_JP",
                "level_interval_ms": "150",
                "vad_threshold_db": "-25.5",
                "vad_hang_ms": "300",
                "vad_ema_alpha": "0.12",
                "commit_silence_ms": "800",
                "commit_on_speech_end": "false",
            ],
        ],
    ])
    await server.handleLineForTesting(request)

    let args = server.currentArgsForTesting()
    try assertTrue(args.deviceId == 2, "deviceId should be 2")
    try assertTrue(args.locale.identifier == "ja_JP", "locale should be ja_JP")
    try assertTrue(args.levelIntervalMs == 150, "levelIntervalMs should be 150")
    try assertTrue(args.vadThresholdDb == -25.5, "vadThresholdDb should be -25.5")
    try assertTrue(args.vadHangMs == 300, "vadHangMs should be 300")
    try assertTrue(args.vadEmaAlpha == 0.12, "vadEmaAlpha should be 0.12")
    try assertTrue(args.commitSilenceMs == 800, "commitSilenceMs should be 800")
    try assertTrue(args.commitOnSpeechEnd == false, "commitOnSpeechEnd should be false")
}

func testMCPServerSetConfigBooleanVariants() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let requestTrue = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 13,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "commit_on_speech_end": "1"
            ],
        ],
    ])
    await server.handleLineForTesting(requestTrue)
    var args = server.currentArgsForTesting()
    try assertTrue(args.commitOnSpeechEnd == true, "commitOnSpeechEnd should be true for '1'")

    let requestYes = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 14,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "commit_on_speech_end": "yes"
            ],
        ],
    ])
    await server.handleLineForTesting(requestYes)
    args = server.currentArgsForTesting()
    try assertTrue(args.commitOnSpeechEnd == true, "commitOnSpeechEnd should be true for 'yes'")

    let requestNo = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 15,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "commit_on_speech_end": "no"
            ],
        ],
    ])
    await server.handleLineForTesting(requestNo)
    args = server.currentArgsForTesting()
    try assertTrue(args.commitOnSpeechEnd == false, "commitOnSpeechEnd should be false for 'no'")

    let requestZero = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 16,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "commit_on_speech_end": "0"
            ],
        ],
    ])
    await server.handleLineForTesting(requestZero)
    args = server.currentArgsForTesting()
    try assertTrue(args.commitOnSpeechEnd == false, "commitOnSpeechEnd should be false for '0'")
}

func testMCPServerSetConfigInvalidBooleanString() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let requestTrue = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 17,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "commit_on_speech_end": "1"
            ],
        ],
    ])
    await server.handleLineForTesting(requestTrue)
    var args = server.currentArgsForTesting()
    try assertTrue(
        args.commitOnSpeechEnd == true, "commitOnSpeechEnd should be true before invalid input")

    let requestMaybe = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 18,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "commit_on_speech_end": "maybe"
            ],
        ],
    ])
    await server.handleLineForTesting(requestMaybe)
    args = server.currentArgsForTesting()
    try assertTrue(
        args.commitOnSpeechEnd == true, "commitOnSpeechEnd should remain true for invalid input")
}

func testMCPServerSetConfigInvalidNumericStrings() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let requestValid = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 19,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "device_id": 3,
                "level_interval_ms": 120,
                "vad_threshold_db": -20.0,
                "vad_hang_ms": 250,
                "vad_ema_alpha": 0.33,
                "commit_silence_ms": 900,
            ],
        ],
    ])
    await server.handleLineForTesting(requestValid)
    var args = server.currentArgsForTesting()
    try assertTrue(args.deviceId == 3, "deviceId should be 3 before invalid input")
    try assertTrue(
        args.levelIntervalMs == 120, "levelIntervalMs should be 120 before invalid input")
    try assertTrue(
        args.vadThresholdDb == -20.0, "vadThresholdDb should be -20.0 before invalid input")
    try assertTrue(args.vadHangMs == 250, "vadHangMs should be 250 before invalid input")
    try assertTrue(args.vadEmaAlpha == 0.33, "vadEmaAlpha should be 0.33 before invalid input")
    try assertTrue(
        args.commitSilenceMs == 900, "commitSilenceMs should be 900 before invalid input")

    let requestInvalid = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 20,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "device_id": "oops",
                "level_interval_ms": "nope",
                "vad_threshold_db": "bad",
                "vad_hang_ms": "bad",
                "vad_ema_alpha": "bad",
                "commit_silence_ms": "bad",
            ],
        ],
    ])
    await server.handleLineForTesting(requestInvalid)
    args = server.currentArgsForTesting()
    try assertTrue(args.deviceId == 3, "deviceId should remain 3 for invalid input")
    try assertTrue(
        args.levelIntervalMs == 120, "levelIntervalMs should remain 120 for invalid input")
    try assertTrue(
        args.vadThresholdDb == -20.0, "vadThresholdDb should remain -20.0 for invalid input")
    try assertTrue(args.vadHangMs == 250, "vadHangMs should remain 250 for invalid input")
    try assertTrue(args.vadEmaAlpha == 0.33, "vadEmaAlpha should remain 0.33 for invalid input")
    try assertTrue(
        args.commitSilenceMs == 900, "commitSilenceMs should remain 900 for invalid input")
}

func testMCPServerSetConfigInvalidLocaleString() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let requestValid = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 21,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "locale": "en_US"
            ],
        ],
    ])
    await server.handleLineForTesting(requestValid)
    var args = server.currentArgsForTesting()
    try assertTrue(args.locale.identifier == "en_US", "locale should be en_US before invalid input")

    let requestInvalid = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 22,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "locale": "invalid-locale!!"
            ],
        ],
    ])
    await server.handleLineForTesting(requestInvalid)
    args = server.currentArgsForTesting()
    try assertTrue(
        args.locale.identifier == "invalid-locale!!",
        "locale should accept invalid identifier string"
    )
}

func testMCPServerSetConfigDeviceIdOutOfRange() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let requestValid = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 23,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "device_id": 1
            ],
        ],
    ])
    await server.handleLineForTesting(requestValid)
    var args = server.currentArgsForTesting()
    try assertTrue(args.deviceId == 1, "deviceId should be 1 before out-of-range input")

    let requestOutOfRange = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 24,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "device_id": -1
            ],
        ],
    ])
    await server.handleLineForTesting(requestOutOfRange)
    args = server.currentArgsForTesting()
    try assertTrue(args.deviceId == -1, "deviceId should accept out-of-range value")
}

func testMCPServerToolsCallInvalidParams() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": [
            "arguments": [:]
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let err = obj["error"] as? [String: Any]
    try assertTrue(err?["code"] as? Int == -32602, "invalid params code should be -32602")
}

func testMCPServerToolsCallUnknownTool() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": [
            "name": "no_such_tool",
            "arguments": [:],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let err = obj["error"] as? [String: Any]
    try assertTrue(err?["code"] as? Int == -32601, "method not found code should be -32601")
}

func testMCPServerResourcesReadInvalidUri() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 4,
        "method": "resources/read",
        "params": [
            "uri": "ses://test/invalid"
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let err = obj["error"] as? [String: Any]
    try assertTrue(err?["code"] as? Int == -32602, "invalid params code should be -32602")
}

func testMCPServerReadEventsDefaults() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 5,
        "method": "read_events",
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let events = result?["events"] as? [[String: Any]]
    try assertTrue(events?.isEmpty == true, "events should be empty")
    try assertTrue(result?["next_seq"] as? Int == 1, "next_seq should be 1")
    try assertTrue(result?["latest_seq"] as? Int == 0, "latest_seq should be 0")
}

func testMCPServerReadEventsFromBuffer() async throws {
    let buffer = EventBuffer()
    _ = await buffer.append(
        Event(type: .status, tsMs: 10, session: "s", payload: ["state": "listening"])
    )
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 6,
        "method": "read_events",
        "params": [
            "from_seq": 1,
            "max_count": 5,
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let events = result?["events"] as? [[String: Any]]
    try assertTrue(events?.count == 1, "events should have one item")
    let first = events?.first
    try assertTrue(first?["type"] as? String == "status", "type should be status")
    try assertTrue(first?["state"] as? String == "listening", "state should be listening")
    try assertTrue(first?["session"] as? String == "s", "session should be s")
    try assertTrue(first?["seq"] as? Int == 1, "seq should be 1")
}

func testMCPServerResourcesReadFromBuffer() async throws {
    let buffer = EventBuffer()
    _ = await buffer.append(
        Event(type: .delta, tsMs: 20, session: "s", payload: ["delta": "hi"])
    )
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 7,
        "method": "resources/read",
        "params": [
            "uri": "ses://test/events",
            "from_seq": 1,
            "max_count": 1,
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let contents = result?["contents"] as? [[String: Any]]
    let text = contents?.first?["text"] as? String
    try assertTrue(text != nil, "text should be present")
    let parsed = try parseJSONLine(text ?? "{}")
    let events = parsed["events"] as? [[String: Any]]
    try assertTrue(events?.count == 1, "events should have one item")
    try assertTrue(events?.first?["delta"] as? String == "hi", "delta should be hi")
}

func testMCPServerBasics() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    await server.handleLineForTesting("not-json")
    let lines1 = collector.snapshot()
    try assertTrue(lines1.count == 1, "should write one response")
    let obj1 = try parseJSONLine(lines1[0])
    let err = obj1["error"] as? [String: Any]
    try assertTrue(err?["code"] as? Int == -32700, "parse error code should be -32700")

    await server.handleLineForTesting("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}")
    let lines2 = collector.snapshot()
    try assertTrue(lines2.count == 2, "should write second response")
    let obj2 = try parseJSONLine(lines2[1])
    let result = obj2["result"] as? [String: Any]
    let tools = result?["tools"] as? [[String: Any]]
    try assertTrue(tools != nil, "tools list should be present")
}

func testMCPServerToolsCallSetConfig() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 10,
        "method": "tools/call",
        "params": [
            "name": "set_config",
            "arguments": [
                "vad_threshold_db": -25.0,
                "commit_on_speech_end": false,
            ],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    try assertTrue(data?["status"] as? String == "ok", "status should be ok")
}

func testMCPServerToolsCallStartStreamReturnsFailed() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    setPermissionOverridesSync(mic: false, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 200,
        "method": "tools/call",
        "params": [
            "name": "start_stream",
            "arguments": [:],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    try assertTrue(data?["status"] as? String == "failed", "status should be failed")

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one error event")
    try assertTrue(items[0].event.type == .error, "event type should be error")
    try assertTrue(
        items[0].event.payload["code"] as? String == "mic_permission_denied",
        "error code should be mic_permission_denied"
    )
}

func testMCPServerToolsCallStopStreamReturnsStopped() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 201,
        "method": "tools/call",
        "params": [
            "name": "stop_stream",
            "arguments": [:],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    try assertTrue(data?["status"] as? String == "stopped", "status should be stopped")
}

func testMCPServerToolsCallListDevicesReturnsInputs() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 202,
        "method": "tools/call",
        "params": [
            "name": "list_devices",
            "arguments": [:],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    try assertTrue(data?["inputs"] is [[String: Any]], "inputs should be an array")
}

func testMCPServerToolsCallReadEventsReturnsItems() async throws {
    let buffer = EventBuffer()
    _ = await buffer.append(
        Event(type: .status, tsMs: 10, session: "s", payload: ["state": "listening"])
    )
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 203,
        "method": "tools/call",
        "params": [
            "name": "read_events",
            "arguments": [
                "from_seq": 1,
                "max_count": 1,
            ],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    let events = data?["events"] as? [[String: Any]]
    try assertTrue(events?.count == 1, "events should have one item")
    try assertTrue(events?.first?["type"] as? String == "status", "type should be status")
    try assertTrue(events?.first?["state"] as? String == "listening", "state should be listening")
}

func testMCPServerRunReadsLinesAndStops() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request =
        encodeJSONLine([
            "jsonrpc": "2.0",
            "id": 300,
            "method": "tools/list",
        ]) + "\n"

    guard let data = request.data(using: .utf8) else {
        throw TestFailure.assertionFailed("request should be encoded")
    }

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: tempURL.path, contents: data)
    let fileHandle = try FileHandle(forReadingFrom: tempURL)
    defer { try? fileHandle.close() }
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let originalStdin = dup(fileno(stdin))
    defer {
        _ = dup2(originalStdin, fileno(stdin))
        close(originalStdin)
    }
    _ = dup2(fileHandle.fileDescriptor, fileno(stdin))

    let task = Task {
        await server.run(args: Args.parse(from: ["ses"]))
    }
    let didTimeout = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await task.value
            return false
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return true
        }
        let result = await group.next() ?? true
        group.cancelAll()
        return result
    }
    if didTimeout {
        throw TestFailure.assertionFailed("MCPServer.run should finish before timeout")
    }

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    try assertTrue(result?["tools"] is [[String: Any]], "tools list should be present")
}

func testMCPServerDefaultOutputWriterWritesToFile() async throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: tempURL.path, contents: Data())
    let fileHandle = try FileHandle(forWritingTo: tempURL)
    defer { try? fileHandle.close() }
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let originalStdout = dup(fileno(stdout))
    defer {
        fflush(stdout)
        _ = dup2(originalStdout, fileno(stdout))
        close(originalStdout)
    }
    _ = dup2(fileHandle.fileDescriptor, fileno(stdout))

    let task = Task {
        let server = MCPServer()
        let request = encodeJSONLine([
            "jsonrpc": "2.0",
            "id": 301,
            "method": "tools/list",
        ])
        await server.handleLineForTesting(request)
    }
    let didTimeout = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await task.value
            return false
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return true
        }
        let result = await group.next() ?? true
        group.cancelAll()
        return result
    }
    if didTimeout {
        throw TestFailure.assertionFailed("default output writer should finish before timeout")
    }

    fflush(stdout)

    let output = try String(contentsOf: tempURL, encoding: .utf8)
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    try assertTrue(trimmed.isEmpty == false, "should write JSON")
    let firstLine = trimmed.split(separator: "\n", omittingEmptySubsequences: true).first
    let obj = try parseJSONLine(String(firstLine ?? ""))
    let result = obj["result"] as? [String: Any]
    try assertTrue(result?["tools"] is [[String: Any]], "tools list should be present")
}

func testMCPServerUnknownMethodReturnsError() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 205,
        "method": "unknown_method",
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let err = obj["error"] as? [String: Any]
    try assertTrue(err?["code"] as? Int == -32601, "method not found code should be -32601")
}

func testMCPServerInitializeReturnsCapabilities() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 100,
        "method": "initialize",
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let serverInfo = result?["serverInfo"] as? [String: Any]
    try assertTrue(serverInfo?["name"] as? String == "ses", "server name should be ses")
    let capabilities = result?["capabilities"] as? [String: Any]
    let tools = capabilities?["tools"] as? [String]
    try assertTrue(tools?.contains("start_stream") == true, "tools should include start_stream")
}

func testMCPServerDirectStartStreamMicPermissionDenied() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    setPermissionOverridesSync(mic: false, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 101,
        "method": "start_stream",
        "params": [:],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    try assertTrue(result?["status"] as? String == "failed", "status should be failed")

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one error event")
    try assertTrue(items[0].event.type == .error, "event type should be error")
    try assertTrue(
        items[0].event.payload["code"] as? String == "mic_permission_denied",
        "error code should be mic_permission_denied"
    )
}

func testMCPServerDirectStopStreamReturnsStopped() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 102,
        "method": "stop_stream",
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    try assertTrue(result?["status"] as? String == "stopped", "status should be stopped")
}

func testMCPServerDirectListDevicesReturnsInputs() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 103,
        "method": "list_devices",
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    try assertTrue(result?["inputs"] is [[String: Any]], "inputs should be an array")
}

func testMCPServerDirectSetConfigUpdatesArgs() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 104,
        "method": "set_config",
        "params": [
            "locale": "en_US",
            "level_interval_ms": 123,
            "commit_on_speech_end": false,
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    try assertTrue(result?["status"] as? String == "ok", "status should be ok")

    let args = server.currentArgsForTesting()
    try assertTrue(args.locale.identifier == "en_US", "locale should be updated")
    try assertTrue(args.levelIntervalMs == 123, "levelIntervalMs should be updated")
    try assertTrue(args.commitOnSpeechEnd == false, "commitOnSpeechEnd should be updated")
}

func testMCPServerStartStreamMicPermissionDenied() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    setPermissionOverridesSync(mic: false, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 101,
        "method": "tools/call",
        "params": [
            "name": "start_stream",
            "arguments": [:],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    try assertTrue(data?["status"] as? String == "failed", "status should be failed")

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one error event")
    try assertTrue(items[0].event.type == .error, "event type should be error")
    try assertTrue(
        items[0].event.payload["code"] as? String == "mic_permission_denied",
        "error code should be mic_permission_denied"
    )
}

func testMCPServerStartStreamSpeechPermissionDenied() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let collector = OutputCollector()
    let server = MCPServer(buffer: buffer, outputWriter: collector.append)

    setPermissionOverridesSync(mic: true, speech: .denied)
    defer { clearPermissionOverridesSync() }

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 102,
        "method": "tools/call",
        "params": [
            "name": "start_stream",
            "arguments": [:],
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let data = result?["data"] as? [String: Any]
    try assertTrue(data?["status"] as? String == "failed", "status should be failed")

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one error event")
    try assertTrue(items[0].event.type == .error, "event type should be error")
    try assertTrue(
        items[0].event.payload["code"] as? String == "speech_permission_denied",
        "error code should be speech_permission_denied"
    )
}

func testMCPServerResourcesRead() async throws {
    let collector = OutputCollector()
    let server = MCPServer(outputWriter: collector.append)

    let request = encodeJSONLine([
        "jsonrpc": "2.0",
        "id": 11,
        "method": "resources/read",
        "params": [
            "uri": "ses://test/events",
            "from_seq": 1,
            "max_count": 1,
        ],
    ])
    await server.handleLineForTesting(request)

    let lines = collector.snapshot()
    try assertTrue(lines.count == 1, "should write one response")
    let obj = try parseJSONLine(lines[0])
    let result = obj["result"] as? [String: Any]
    let contents = result?["contents"] as? [[String: Any]]
    try assertTrue(contents?.count == 1, "contents should have one item")
    try assertTrue(contents?.first?["uri"] as? String == "ses://test/events", "uri should match")
}

func testAppendAndReadFromStart() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let e1 = Event(type: .status, tsMs: 1, session: "s1", payload: ["state": "listening"])
    let e2 = Event(type: .delta, tsMs: 2, session: "s1", payload: ["delta": "he"])

    let seq1 = await buffer.append(e1)
    let seq2 = await buffer.append(e2)

    try assertTrue(seq1 == 1, "seq1 should be 1")
    try assertTrue(seq2 == 2, "seq2 should be 2")

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 2, "items.count should be 2")
    try assertTrue(items[0].seq == 1, "first seq should be 1")
    try assertTrue(items[1].seq == 2, "second seq should be 2")
    try assertTrue(items[0].event.type == .status, "first event type should be status")
    try assertTrue(items[1].event.type == .delta, "second event type should be delta")
    try assertTrue(
        items[1].event.payload["delta"] as? String == "he", "delta payload should be 'he'")
}

func testReadRespectsFromSeq() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    _ = await buffer.append(Event(type: .status, tsMs: 1, session: "s1", payload: [:]))
    _ = await buffer.append(Event(type: .level, tsMs: 2, session: "s1", payload: [:]))
    _ = await buffer.append(Event(type: .delta, tsMs: 3, session: "s1", payload: ["delta": "llo"]))

    let items = await buffer.read(fromSeq: 2, maxCount: 10)
    try assertTrue(items.count == 2, "items.count should be 2")
    try assertTrue(items[0].seq == 2, "first seq should be 2")
    try assertTrue(items[1].seq == 3, "second seq should be 3")
    try assertTrue(items[0].event.type == .level, "first event type should be level")
    try assertTrue(items[1].event.type == .delta, "second event type should be delta")
}

func testOverflowDropsOldest() async throws {
    let buffer = EventBuffer(maxEvents: 2)
    _ = await buffer.append(Event(type: .status, tsMs: 1, session: "s1", payload: [:]))
    _ = await buffer.append(Event(type: .level, tsMs: 2, session: "s1", payload: [:]))
    _ = await buffer.append(Event(type: .delta, tsMs: 3, session: "s1", payload: ["delta": "x"]))

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 2, "items.count should be 2")
    try assertTrue(items[0].seq == 2, "first seq should be 2")
    try assertTrue(items[1].seq == 3, "second seq should be 3")
    try assertTrue(items[0].event.type == .level, "first event type should be level")
    try assertTrue(items[1].event.type == .delta, "second event type should be delta")
}

func testLatestSeq() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let initial = await buffer.latestSeq()
    try assertTrue(initial == 0, "initial latestSeq should be 0")

    _ = await buffer.append(Event(type: .status, tsMs: 1, session: "s1", payload: [:]))
    _ = await buffer.append(Event(type: .level, tsMs: 2, session: "s1", payload: [:]))

    let latest = await buffer.latestSeq()
    try assertTrue(latest == 2, "latestSeq should be 2")
}

func testBufferedEventSinkAppends() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let sink = BufferedEventSink(buffer: buffer)
    let event = Event(type: .delta, tsMs: 10, session: "s", payload: ["delta": "x"])

    sink.send(event)
    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "buffer should have one event")
    try assertTrue(items[0].event.type == .delta, "event type should be delta")
    try assertTrue(items[0].event.payload["delta"] as? String == "x", "delta should be x")
}

func testStreamControllerStartMicPermissionDenied() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let controller = StreamController(buffer: buffer)
    setPermissionOverridesSync(mic: false, speech: .authorized)
    defer { clearPermissionOverridesSync() }

    let args = Args.parse(from: ["ses"])
    let result = await controller.start(args: args)
    switch result {
    case .failed:
        break
    default:
        throw TestFailure.assertionFailed("start should fail when mic permission denied")
    }

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one error event")
    try assertTrue(items[0].event.type == .error, "event type should be error")
    try assertTrue(
        items[0].event.payload["code"] as? String == "mic_permission_denied",
        "error code should be mic_permission_denied"
    )
}

func testStreamControllerStartSpeechPermissionDenied() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let controller = StreamController(buffer: buffer)
    setPermissionOverridesSync(mic: true, speech: .denied)
    defer { clearPermissionOverridesSync() }

    let args = Args.parse(from: ["ses"])
    let result = await controller.start(args: args)
    switch result {
    case .failed:
        break
    default:
        throw TestFailure.assertionFailed("start should fail when speech permission denied")
    }

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one error event")
    try assertTrue(items[0].event.type == .error, "event type should be error")
    try assertTrue(
        items[0].event.payload["code"] as? String == "speech_permission_denied",
        "error code should be speech_permission_denied"
    )
}

func testStreamControllerStopEmitsStopped() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let controller = StreamController(buffer: buffer)
    await controller.setContextForTesting(RuntimeContext(session: "s"))
    await controller.stop()

    try await Task.sleep(nanoseconds: 5_000_000)

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.count == 1, "should emit one status event")
    try assertTrue(items[0].event.type == .status, "event type should be status")
    try assertTrue(
        items[0].event.payload["state"] as? String == "stopped",
        "state should be stopped"
    )
}

func testStreamControllerAlreadyRunning() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let controller = StreamController(buffer: buffer)
    let ctx = RuntimeContext(session: "existing")
    await controller.setContextForTesting(ctx)

    let args = Args.parse(from: ["ses"])
    let result = await controller.start(args: args)

    switch result {
    case .alreadyRunning(let session):
        try assertTrue(session == "existing", "should return existing session")
    default:
        throw TestFailure.assertionFailed("start should return alreadyRunning when ctx exists")
    }
}

func testStreamControllerAccessors() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let controller = StreamController(buffer: buffer)

    let isRunningBefore = await controller.isRunning()
    let sessionBefore = await controller.currentSession()
    try assertTrue(isRunningBefore == false, "isRunning should be false before start")
    try assertTrue(sessionBefore == nil, "currentSession should be nil")

    let ctx = RuntimeContext(session: "session-1")
    await controller.setContextForTesting(ctx)

    let isRunningAfter = await controller.isRunning()
    let sessionAfter = await controller.currentSession()
    try assertTrue(isRunningAfter == false, "isRunning should remain false without pipeline")
    try assertTrue(
        sessionAfter == "session-1",
        "currentSession should return context session"
    )
}

func testStreamControllerStopNoContext() async throws {
    let buffer = EventBuffer(maxEvents: 10)
    let controller = StreamController(buffer: buffer)

    await controller.stop()

    let items = await buffer.read(fromSeq: 1, maxCount: 10)
    try assertTrue(items.isEmpty, "stop with no context should not emit events")
}
