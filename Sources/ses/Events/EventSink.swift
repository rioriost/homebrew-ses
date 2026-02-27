import Foundation

public protocol EventSink: Sendable {
    func send(_ event: Event)
}
