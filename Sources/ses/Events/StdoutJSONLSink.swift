import Foundation

public final class StdoutJSONLSink: EventSink {
    private let config: OutputConfig
    private let q = DispatchQueue(label: "ses.stdout.jsonl.sink")

    public init(config: OutputConfig) {
        self.config = config
    }

    public func send(_ event: Event) {
        // ここで JSON を「同期で」組み立ててから、Stringだけをdispatchする
        var obj = event.payload
        obj["type"] = event.type.rawValue
        obj["ts_ms"] = event.tsMs
        if config.includeSession, let s = event.session {
            obj["session"] = s
        }

        let options: JSONSerialization.WritingOptions = config.pretty ? [.prettyPrinted] : []
        guard
            let data = try? JSONSerialization.data(withJSONObject: obj, options: options),
            let line = String(data: data, encoding: .utf8)
        else { return }

        if let data = (line + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
}
