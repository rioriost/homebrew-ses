import Foundation

public struct CommitPolicy: Sendable {
    public let silenceMs: Int64
    public let commitOnSpeechEnd: Bool

    public init(silenceMs: Int64, commitOnSpeechEnd: Bool) {
        self.silenceMs = silenceMs
        self.commitOnSpeechEnd = commitOnSpeechEnd
    }
}
