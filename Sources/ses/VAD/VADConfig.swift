import Foundation

public struct VADConfig: Sendable {
    public let thresholdDb: Double
    public let hangMs: Int64
    public let emaAlpha: Double
    public let warmupMs: Int64
    public let levelIntervalMs: Int64

    public init(
        thresholdDb: Double, hangMs: Int64, emaAlpha: Double, warmupMs: Int64,
        levelIntervalMs: Int64
    ) {
        self.thresholdDb = thresholdDb
        self.hangMs = hangMs
        self.emaAlpha = emaAlpha
        self.warmupMs = warmupMs
        self.levelIntervalMs = levelIntervalMs
    }
}
