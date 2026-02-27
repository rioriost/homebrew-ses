import Foundation

public actor EventBuffer {
    private var events: [Event] = []
    private var nextSeq: Int64 = 1

    private let maxEvents: Int

    public init(maxEvents: Int = 2000) {
        self.maxEvents = maxEvents
    }

    public func append(_ event: Event) -> Int64 {
        let seq = nextSeq
        nextSeq += 1

        events.append(event)

        if events.count > maxEvents {
            let overflow = events.count - maxEvents
            events.removeFirst(overflow)
        }

        return seq
    }

    public func read(fromSeq: Int64, maxCount: Int) -> [(seq: Int64, event: Event)] {
        guard maxCount > 0 else { return [] }

        let earliestSeq = max(1, nextSeq - Int64(events.count))
        let startSeq = max(fromSeq, earliestSeq)
        let startIndex = Int(startSeq - earliestSeq)

        guard startIndex < events.count else { return [] }

        let available = events.count - startIndex
        let count = min(available, maxCount)

        var result: [(Int64, Event)] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let seq = startSeq + Int64(i)
            result.append((seq, events[startIndex + i]))
        }
        return result
    }

    public func latestSeq() -> Int64 {
        return nextSeq - 1
    }
}
