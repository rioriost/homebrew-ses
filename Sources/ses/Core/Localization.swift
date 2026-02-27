import Foundation

public enum L10n {
    private static let bundle: Bundle = .module
    private static let lock = NSLock()
    nonisolated(unsafe) private static var overrideString: ((String, [CVarArg], String) -> String)?

    public static func setOverride(_ block: ((String, [CVarArg], String) -> String)?) {
        lock.lock()
        overrideString = block
        lock.unlock()
    }

    public static func string(_ key: String, _ args: CVarArg..., comment: String = "") -> String {
        let argArray = args
        let override: ((String, [CVarArg], String) -> String)?
        lock.lock()
        override = overrideString
        lock.unlock()

        if let override {
            return override(key, argArray, comment)
        }
        let format = NSLocalizedString(key, tableName: nil, bundle: bundle, comment: comment)
        if argArray.isEmpty {
            return format
        }
        return String(format: format, locale: Locale.current, arguments: argArray)
    }
}
