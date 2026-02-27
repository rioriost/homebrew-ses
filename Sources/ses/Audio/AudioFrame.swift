import Foundation

public struct AudioFrame: Sendable {
    public let samplesMono: [Int16]
    public let sampleRate: Double
    public let timestampMs: Int64

    public init(samplesMono: [Int16], sampleRate: Double, timestampMs: Int64) {
        self.samplesMono = samplesMono
        self.sampleRate = sampleRate
        self.timestampMs = timestampMs
    }
}
