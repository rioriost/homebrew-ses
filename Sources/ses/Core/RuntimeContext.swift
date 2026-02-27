import Foundation

public struct RuntimeContext: Sendable {
    public let session: String
    public let startNs: UInt64

    public init(session: String = UUID().uuidString) {
        self.session = session
        self.startNs = DispatchTime.now().uptimeNanoseconds
    }

    public func nowMs() -> Int64 {
        Int64((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
    }
}
