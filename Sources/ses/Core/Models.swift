import Foundation

public struct OutputConfig: Sendable {
    public let pretty: Bool
    public let includeSession: Bool
    public init(pretty: Bool, includeSession: Bool) {
        self.pretty = pretty
        self.includeSession = includeSession
    }
}

public struct CommitPayload: Sendable {
    public let commitId: Int64
    public let reason: String  // "speech_end" / "silence"
    public let text: String
    public let fromSeq: Int64
    public let toSeq: Int64
    public let spanMs: Int64
    public let audioLevelDb: Double
    public let vadDb: Double
}
