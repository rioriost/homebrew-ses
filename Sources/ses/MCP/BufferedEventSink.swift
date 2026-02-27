import Foundation

public final class BufferedEventSink: EventSink, @unchecked Sendable {
    private let buffer: EventBuffer

    public init(buffer: EventBuffer) {
        self.buffer = buffer
    }

    public func send(_ event: Event) {
        let eventCopy = event
        Task.detached { @Sendable [buffer] in
            _ = await buffer.append(eventCopy)
        }
    }
}
