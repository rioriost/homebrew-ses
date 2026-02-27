import Foundation
import Speech

@MainActor
public enum SpeechTaskRegistry {
    private static var task: SFSpeechRecognitionTask?
    public static func set(_ t: SFSpeechRecognitionTask) { task = t }
    public static func cancelAndClear() {
        task?.cancel()
        task = nil
    }
    public static func clear() { task = nil }
}
