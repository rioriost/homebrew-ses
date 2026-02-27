import AVFoundation
import Foundation

public final class MCPServer {
    private let buffer: EventBuffer
    private let controller: StreamController
    private var currentArgs: Args
    private let outputWriter: (String) -> Void

    public init(
        buffer: EventBuffer = EventBuffer(),
        outputWriter: @escaping (String) -> Void = { line in
            FileHandle.standardOutput.write((line + "\n").data(using: .utf8) ?? Data())
            FileHandle.standardOutput.synchronizeFile()
        }
    ) {
        self.buffer = buffer
        self.controller = StreamController(buffer: buffer)
        self.currentArgs = Args.parse()
        self.outputWriter = outputWriter
    }

    public func run(args: Args) async {
        self.currentArgs = args

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            await handleLine(trimmed)
        }
    }

    public func handleLineForTesting(_ line: String) async {
        await handleLine(line)
    }

    public func currentArgsForTesting() -> Args {
        return currentArgs
    }

    private func handleLine(_ line: String) async {
        guard let data = line.data(using: .utf8) else {
            writeError(id: nil, code: -32700, message: "Parse error")
            return
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let obj = json as? [String: Any],
            let method = obj["method"] as? String
        else {
            writeError(id: nil, code: -32700, message: "Parse error")
            return
        }

        let id = obj["id"]
        let params = obj["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            writeResult(
                id: id,
                result: [
                    "serverInfo": [
                        "name": "ses",
                        "version": "0.1.0",
                    ],
                    "capabilities": [
                        "tools": [
                            "start_stream",
                            "stop_stream",
                            "list_devices",
                            "read_events",
                            "set_config",
                        ]
                    ],
                ]
            )

        case "tools/list":
            writeResult(id: id, result: ["tools": toolsList()])

        case "tools/call":
            guard let toolName = params["name"] as? String else {
                writeError(id: id, code: -32602, message: "Invalid params")
                return
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]

            let data: [String: Any]
            switch toolName {
            case "start_stream":
                data = await startStream(params: arguments)
            case "stop_stream":
                data = await stopStream()
            case "list_devices":
                data = listDevices()
            case "read_events":
                data = await readEvents(params: arguments)
            case "set_config":
                data = setConfig(params: arguments)
            default:
                writeError(id: id, code: -32601, message: "Method not found")
                return
            }

            writeToolResult(id: id, data: data)

        case "resources/read":
            guard let uri = params["uri"] as? String, isEventsUri(uri) else {
                writeError(id: id, code: -32602, message: "Invalid params")
                return
            }
            let data = await resourcesRead(params: params)
            writeResult(id: id, result: data)

        case "start_stream":
            let data = await startStream(params: params)
            writeResult(id: id, result: data)

        case "stop_stream":
            let data = await stopStream()
            writeResult(id: id, result: data)

        case "list_devices":
            let data = listDevices()
            writeResult(id: id, result: data)

        case "read_events":
            let data = await readEvents(params: params)
            writeResult(id: id, result: data)

        case "set_config":
            let data = setConfig(params: params)
            writeResult(id: id, result: data)

        case "shutdown":
            writeResult(id: id, result: ["status": "ok"])
            exit(0)

        default:
            writeError(id: id, code: -32601, message: "Method not found")
        }
    }

    private func eventToObject(_ event: Event) -> [String: Any] {
        var obj = event.payload
        obj["type"] = event.type.rawValue
        obj["ts_ms"] = event.tsMs
        if let session = event.session {
            obj["session"] = session
        }
        return obj
    }

    private func applyConfig(base: Args, params: [String: Any]) -> Args {
        var locale = base.locale
        if let loc = params["locale"] as? String {
            locale = Locale(identifier: loc)
        }

        let deviceId = int(params["device_id"]) ?? base.deviceId
        let levelIntervalMs = int64(params["level_interval_ms"]) ?? base.levelIntervalMs
        let vadThresholdDb = double(params["vad_threshold_db"]) ?? base.vadThresholdDb
        let vadHangMs = int64(params["vad_hang_ms"]) ?? base.vadHangMs
        let vadEmaAlpha = double(params["vad_ema_alpha"]) ?? base.vadEmaAlpha
        let commitSilenceMs = int64(params["commit_silence_ms"]) ?? base.commitSilenceMs
        let commitOnSpeechEnd = bool(params["commit_on_speech_end"]) ?? base.commitOnSpeechEnd

        return Args(
            listDevices: base.listDevices,
            deviceId: deviceId,
            locale: locale,
            pretty: base.pretty,
            noSession: base.noSession,
            debug: base.debug,
            mcp: true,
            version: base.version,
            levelIntervalMs: levelIntervalMs,
            vadThresholdDb: vadThresholdDb,
            vadHangMs: vadHangMs,
            vadEmaAlpha: vadEmaAlpha,
            commitSilenceMs: commitSilenceMs,
            warmupMs: base.warmupMs,
            watchdogTimeoutMs: base.watchdogTimeoutMs,
            watchdogIntervalMs: base.watchdogIntervalMs,
            recommendedPreset: base.recommendedPreset,
            commitOnSpeechEnd: commitOnSpeechEnd
        )
    }

    private func toolsList() -> [[String: Any]] {
        return [
            [
                "name": "start_stream",
                "description": "Start microphone streaming and begin emitting events",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "device_id": ["type": "integer"],
                        "locale": ["type": "string"],
                        "vad_threshold_db": ["type": "number"],
                        "vad_hang_ms": ["type": "integer"],
                        "vad_ema_alpha": ["type": "number"],
                        "level_interval_ms": ["type": "integer"],
                        "commit_silence_ms": ["type": "integer"],
                        "commit_on_speech_end": ["type": "boolean"],
                    ],
                    "additionalProperties": true,
                ],
            ],
            [
                "name": "stop_stream",
                "description": "Stop the current stream",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": true,
                ],
            ],
            [
                "name": "list_devices",
                "description": "List available input devices",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": true,
                ],
            ],
            [
                "name": "read_events",
                "description": "Read buffered events from a given sequence",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "from_seq": ["type": "integer"],
                        "max_count": ["type": "integer"],
                    ],
                    "additionalProperties": true,
                ],
            ],
            [
                "name": "set_config",
                "description": "Update stream configuration for the next start",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "device_id": ["type": "integer"],
                        "locale": ["type": "string"],
                        "vad_threshold_db": ["type": "number"],
                        "vad_hang_ms": ["type": "integer"],
                        "vad_ema_alpha": ["type": "number"],
                        "level_interval_ms": ["type": "integer"],
                        "commit_silence_ms": ["type": "integer"],
                        "commit_on_speech_end": ["type": "boolean"],
                    ],
                    "additionalProperties": true,
                ],
            ],
        ]
    }

    private func startStream(params: [String: Any]) async -> [String: Any] {
        let mergedArgs = applyConfig(base: currentArgs, params: params)
        currentArgs = mergedArgs

        let result = await controller.start(args: mergedArgs)
        switch result {
        case .started(let session):
            return ["status": "started", "session": session]
        case .alreadyRunning(let session):
            return ["status": "already_running", "session": session]
        case .failed:
            return ["status": "failed"]
        }
    }

    private func stopStream() async -> [String: Any] {
        await controller.stop()
        return ["status": "stopped"]
    }

    private func listDevices() -> [String: Any] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let inputs: [[String: Any]] = discovery.devices.enumerated().map { (i, d) in
            ["id": i, "name": d.localizedName, "uid": d.uniqueID]
        }
        return ["inputs": inputs]
    }

    private func readEvents(params: [String: Any]) async -> [String: Any] {
        let fromSeq = int64(params["from_seq"]) ?? 1
        let maxCount = int(params["max_count"]) ?? 200

        let items = await buffer.read(fromSeq: fromSeq, maxCount: maxCount)
        let events: [[String: Any]] = items.map { (seq, event) in
            var payload = eventToObject(event)
            payload["seq"] = seq
            return payload
        }

        let latest = await buffer.latestSeq()
        let nextSeq = (items.last?.seq ?? fromSeq - 1) + 1

        return [
            "events": events,
            "next_seq": nextSeq,
            "latest_seq": latest,
        ]
    }

    private func setConfig(params: [String: Any]) -> [String: Any] {
        currentArgs = applyConfig(base: currentArgs, params: params)
        return ["status": "ok"]
    }

    private func resourcesRead(params: [String: Any]) async -> [String: Any] {
        guard let uri = params["uri"] as? String, isEventsUri(uri) else {
            return ["contents": []]
        }
        let data = await readEvents(params: params)
        return [
            "contents": [
                [
                    "uri": uri,
                    "mimeType": "application/json",
                    "text": jsonString(data),
                ]
            ]
        ]
    }

    private func isEventsUri(_ uri: String) -> Bool {
        return uri.hasPrefix("ses://") && uri.hasSuffix("/events")
    }

    private func writeToolResult(id: Any?, data: [String: Any]) {
        let text = jsonString(data)
        writeResult(
            id: id,
            result: [
                "content": [
                    [
                        "type": "text",
                        "text": text,
                    ]
                ],
                "data": data,
                "isError": false,
            ]
        )
    }

    private func jsonString(_ obj: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func writeResult(id: Any?, result: [String: Any]) {
        var obj: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]
        obj["id"] = id ?? NSNull()
        writeJSON(obj)
    }

    private func writeError(id: Any?, code: Int, message: String) {
        var obj: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        obj["id"] = id ?? NSNull()
        writeJSON(obj)
    }

    private func writeJSON(_ obj: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
            let line = String(data: data, encoding: .utf8)
        else { return }

        outputWriter(line)
    }

    private func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            switch s.lowercased() {
            case "true", "1", "yes", "y": return true
            case "false", "0", "no", "n": return false
            default: return nil
            }
        }
        return nil
    }
}
