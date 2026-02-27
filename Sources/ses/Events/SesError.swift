import Foundation

public enum SesErrorCode: String, Sendable {
    case micPermissionDenied = "mic_permission_denied"
    case speechPermissionDenied = "speech_permission_denied"
    case deviceNotFound = "device_not_found"
    case deviceInputFailed = "device_input_failed"
    case deviceDisconnected = "device_disconnected"
    case recognizerInitFailed = "recognizer_init_failed"
    case recognizerUnavailable = "recognizer_unavailable"
    case recognitionTaskError = "recognition_task_error"
}

public struct SesError: Sendable {
    public let code: SesErrorCode
    public let message: String
    public let messageKey: String?
    public let messageArgs: [String]
    public let recoverable: Bool
    public let hint: String?
    public let hintKey: String?
    public let hintArgs: [String]
    public let underlying: String?

    public init(
        code: SesErrorCode,
        message: String,
        recoverable: Bool = false,
        hint: String? = nil,
        underlying: String? = nil
    ) {
        self.code = code
        self.message = message
        self.messageKey = nil
        self.messageArgs = []
        self.recoverable = recoverable
        self.hint = hint
        self.hintKey = nil
        self.hintArgs = []
        self.underlying = underlying
    }

    public init(
        code: SesErrorCode,
        messageKey: String,
        messageArgs: [String] = [],
        recoverable: Bool = false,
        hintKey: String? = nil,
        hintArgs: [String] = [],
        underlying: String? = nil
    ) {
        let message = Self.format(key: messageKey, args: messageArgs)
        let hint = hintKey.map { Self.format(key: $0, args: hintArgs) }
        self.code = code
        self.message = message
        self.messageKey = messageKey
        self.messageArgs = messageArgs
        self.recoverable = recoverable
        self.hint = hint
        self.hintKey = hintKey
        self.hintArgs = hintArgs
        self.underlying = underlying
    }

    private static func format(key: String, args: [String]) -> String {
        let format = L10n.string(key)
        if args.isEmpty { return format }
        let cargs: [CVarArg] = args.map { $0 as NSString }
        return String(format: format, locale: Locale.current, arguments: cargs)
    }

    private func resolvedMessage() -> String {
        if let messageKey {
            return Self.format(key: messageKey, args: messageArgs)
        }
        return message
    }

    private func resolvedHint() -> String? {
        if let hintKey {
            return Self.format(key: hintKey, args: hintArgs)
        }
        return hint
    }

    public func payload() -> [String: Any] {
        var p: [String: Any] = [
            "code": code.rawValue,
            "message": resolvedMessage(),
            "recoverable": recoverable,
        ]
        if let hint = resolvedHint() { p["hint"] = hint }
        if let underlying { p["underlying"] = underlying }
        return p
    }
}
