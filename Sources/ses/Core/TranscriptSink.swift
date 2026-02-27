import Foundation

public protocol TranscriptSink: AnyObject {
    func onTranscript(_ te: TranscriptEvent) async
}
