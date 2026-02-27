import Foundation

public enum EventType: String, Sendable {
    case status
    case level
    case speech_start
    case speech_end
    case silence
    case partial
    case final
    case delta
    case commit
    case error
}

public struct Event: @unchecked Sendable {
    public let type: EventType
    public let tsMs: Int64
    public let session: String?
    public let payload: [String: Any]  // JSONSerialization前提の動的payload

    public init(type: EventType, tsMs: Int64, session: String?, payload: [String: Any]) {
        self.type = type
        self.tsMs = tsMs
        self.session = session
        self.payload = payload
    }
}
