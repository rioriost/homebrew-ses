import Foundation

public struct Args: Sendable {
    public let listDevices: Bool
    public let deviceId: Int?
    public let locale: Locale

    public let pretty: Bool
    public let noSession: Bool
    public let debug: Bool
    public let mcp: Bool

    public let levelIntervalMs: Int64
    public let vadThresholdDb: Double
    public let vadHangMs: Int64
    public let vadEmaAlpha: Double

    public let commitSilenceMs: Int64
    public let warmupMs: Int64
    public let watchdogTimeoutMs: Int64
    public let watchdogIntervalMs: Int64

    public let recommendedPreset: Bool
    public let commitOnSpeechEnd: Bool

    public static func parse() -> Args {
        return parse(from: CommandLine.arguments)
    }

    public static func parse(from a: [String]) -> Args {

        func has(_ key: String) -> Bool { a.contains(key) }
        func value(_ key: String) -> String? {
            guard let i = a.firstIndex(of: key), i + 1 < a.count else { return nil }
            return a[i + 1]
        }
        func i64(_ key: String, _ def: Int64) -> Int64 { value(key).flatMap(Int64.init) ?? def }
        func dbl(_ key: String, _ def: Double) -> Double { value(key).flatMap(Double.init) ?? def }
        func int(_ key: String) -> Int? { value(key).flatMap(Int.init) }

        let list = has("--list-devices")
        let devId = int("--device-id")
        let loc = value("--locale").map(Locale.init(identifier:)) ?? Locale.current

        let pretty = has("--pretty")
        let noSession = has("--no-session")
        let debug = has("--debug")
        let mcp = has("--mcp")

        let watchdogTimeoutMs = i64("--watchdog-timeout-ms", 3000)
        let watchdogIntervalMs = i64("--watchdog-interval-ms", 1000)

        let recommended = has("--recommended")

        var defaultVadThresholdDb = -30.0
        var defaultVadHangMs: Int64 = 250
        var defaultVadEmaAlpha = 0.20
        var defaultCommitSilenceMs: Int64 = 700

        if recommended {
            defaultVadThresholdDb = -35.0
            defaultVadHangMs = 800
            defaultVadEmaAlpha = 0.15
            defaultCommitSilenceMs = 900
        }

        var alpha = dbl("--vad-ema-alpha", defaultVadEmaAlpha)
        alpha = min(0.90, max(0.01, alpha))

        let commitOnSpeechEnd = has("--commit-on-speech-end") || !has("--no-commit-on-speech-end")

        return Args(
            listDevices: list,
            deviceId: devId,
            locale: loc,
            pretty: pretty,
            noSession: noSession,
            debug: debug,
            mcp: mcp,
            levelIntervalMs: i64("--level-interval-ms", 200),
            vadThresholdDb: dbl("--vad-threshold-db", defaultVadThresholdDb),
            vadHangMs: i64("--vad-hang-ms", defaultVadHangMs),
            vadEmaAlpha: alpha,
            commitSilenceMs: i64("--commit-silence-ms", defaultCommitSilenceMs),
            warmupMs: i64("--warmup-ms", 1200),
            watchdogTimeoutMs: watchdogTimeoutMs,
            watchdogIntervalMs: watchdogIntervalMs,
            recommendedPreset: recommended,
            commitOnSpeechEnd: commitOnSpeechEnd
        )
    }
}
