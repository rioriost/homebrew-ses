import AVFoundation
import Foundation
import Speech

public typealias SpeechPermissionOverride =
    @Sendable () async -> SFSpeechRecognizerAuthorizationStatus
public typealias MicPermissionOverride = @Sendable () async -> Bool

actor PermissionOverrideStore {
    var speech: SpeechPermissionOverride?
    var mic: MicPermissionOverride?

    func setSpeech(_ block: SpeechPermissionOverride?) {
        speech = block
    }

    func setMic(_ block: MicPermissionOverride?) {
        mic = block
    }

    func getSpeech() -> SpeechPermissionOverride? {
        speech
    }

    func getMic() -> MicPermissionOverride? {
        mic
    }
}

private let permissionOverrides = PermissionOverrideStore()

public func setSpeechPermissionOverride(
    _ block: SpeechPermissionOverride?
) async {
    await permissionOverrides.setSpeech(block)
}

public func setMicPermissionOverride(_ block: MicPermissionOverride?) async {
    await permissionOverrides.setMic(block)
}

public func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
    if let override = await permissionOverrides.getSpeech() {
        return await override()
    }

    return await withCheckedContinuation { cont in
        SFSpeechRecognizer.requestAuthorization { status in
            cont.resume(returning: status)
        }
    }
}

public func requestMicPermission() async -> Bool {
    if let override = await permissionOverrides.getMic() {
        return await override()
    }

    return await AVCaptureDevice.requestAccess(for: .audio)
}
