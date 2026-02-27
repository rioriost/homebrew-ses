import Dispatch
import Foundation
import sesCore

enum TestRegistry {
    static func tests() -> [(String, () async throws -> Void)] {
        [
            ("EventBuffer.appendAndReadFromStart", testAppendAndReadFromStart),
            ("EventBuffer.readRespectsFromSeq", testReadRespectsFromSeq),
            ("EventBuffer.overflowDropsOldest", testOverflowDropsOldest),
            ("EventBuffer.latestSeq", testLatestSeq),

            ("commonPrefixDelta.basic", testCommonPrefixDeltaBasic),
            ("commonPrefixDelta.noCommonPrefix", testCommonPrefixDeltaNoCommonPrefix),
            ("commonPrefixDelta.emptyCurrent", testCommonPrefixDeltaWithEmptyCurrent),

            ("Args.defaults", testArgsDefaults),
            ("Args.recommendedPreset", testArgsRecommendedPreset),
            ("Args.overridesAndClamp", testArgsOverridesAndClamp),

            ("SesError.payload", testSesErrorPayload),
            ("SesError.messageKeyOverride", testSesErrorMessageKeyOverride),

            ("StdoutJSONLSink.prettyIncludesSession", testStdoutJSONLSinkPrettyIncludesSession),
            ("StdoutJSONLSink.omitsSession", testStdoutJSONLSinkOmitsSession),

            ("BufferedEventSink.appends", testBufferedEventSinkAppends),

            ("L10n.defaultAndOverride", testL10nDefaultAndOverride),
            ("OutputConfig.init", testOutputConfigInit),
            ("Permissions.overrides", testPermissionsOverrides),
            ("SpeechTaskRegistry.noop", testSpeechTaskRegistryNoop),

            ("VADConfig.init", testVADConfigInit),
            ("VADProcessor.process", testVADProcessorProcess),
            ("VADProcessor.levelIntervalNoEmit", testVADProcessorLevelIntervalNoEmit),
            ("VADState.updateAndLevel", testVADStateUpdateAndLevel),
            ("VADState.speechTransitions", testVADStateSpeechTransitions),

            ("SpeechRecognizerEngine.initFailed", testSpeechRecognizerInitFailed),
            ("SpeechRecognizerEngine.unavailable", testSpeechRecognizerUnavailable),
            ("SpeechRecognizerEngine.framesNoCrash", testSpeechRecognizerFramesNoCrash),
            (
                "SpeechRecognizerEngine.emitsPartialDeltaFinalWithFake",
                testSpeechRecognizerEmitsPartialDeltaFinalWithFake
            ),
            ("SpeechRecognizerEngine.skipsDeltaWhenEmpty", testSpeechRecognizerSkipsDeltaWhenEmpty),
            ("SpeechRecognizerEngine.emitsErrorWithFake", testSpeechRecognizerEmitsErrorWithFake),
            ("SpeechRecognizerEngine.ignoresNilResult", testSpeechRecognizerIgnoresNilResult),
            (
                "SpeechRecognizerEngine.skipsWhitespaceResult",
                testSpeechRecognizerSkipsWhitespaceResult
            ),
            (
                "SpeechRecognizerEngine.finalDoesNotEmitDelta",
                testSpeechRecognizerFinalDoesNotEmitDelta
            ),
            (
                "SFSpeechRecognitionTaskAdapter.cancel",
                testSFSpeechRecognitionTaskAdapterCancel
            ),
            ("TranscriptEvent.init", testTranscriptEventInit),

            ("MCPServer.setConfigStringParsing", testMCPServerSetConfigStringParsing),
            ("MCPServer.setConfigBooleanVariants", testMCPServerSetConfigBooleanVariants),
            ("MCPServer.setConfigInvalidBooleanString", testMCPServerSetConfigInvalidBooleanString),
            (
                "MCPServer.setConfigInvalidNumericStrings",
                testMCPServerSetConfigInvalidNumericStrings
            ),
            ("MCPServer.setConfigInvalidLocaleString", testMCPServerSetConfigInvalidLocaleString),
            ("MCPServer.setConfigDeviceIdOutOfRange", testMCPServerSetConfigDeviceIdOutOfRange),
            ("MCPServer.initializeReturnsCapabilities", testMCPServerInitializeReturnsCapabilities),
            (
                "MCPServer.directStartStreamMicPermissionDenied",
                testMCPServerDirectStartStreamMicPermissionDenied
            ),
            (
                "MCPServer.directStopStreamReturnsStopped",
                testMCPServerDirectStopStreamReturnsStopped
            ),
            (
                "MCPServer.directListDevicesReturnsInputs",
                testMCPServerDirectListDevicesReturnsInputs
            ),
            ("MCPServer.directSetConfigUpdatesArgs", testMCPServerDirectSetConfigUpdatesArgs),
            (
                "MCPServer.toolsCallStartStreamReturnsFailed",
                testMCPServerToolsCallStartStreamReturnsFailed
            ),
            (
                "MCPServer.toolsCallStopStreamReturnsStopped",
                testMCPServerToolsCallStopStreamReturnsStopped
            ),
            (
                "MCPServer.toolsCallListDevicesReturnsInputs",
                testMCPServerToolsCallListDevicesReturnsInputs
            ),
            (
                "MCPServer.toolsCallReadEventsReturnsItems",
                testMCPServerToolsCallReadEventsReturnsItems
            ),
            ("MCPServer.runReadsLinesAndStops", testMCPServerRunReadsLinesAndStops),
            (
                "MCPServer.defaultOutputWriterWritesToFile",
                testMCPServerDefaultOutputWriterWritesToFile
            ),

            ("MCPServer.unknownMethodReturnsError", testMCPServerUnknownMethodReturnsError),

            ("AudioCapture.initStop", testAudioCaptureInitStop),
            ("AudioCapture.captureOutputYieldsMono", testAudioCaptureCaptureOutputYieldsMono),
            (
                "AudioCapture.streamBasicDescriptionNilForNonAudioSampleBuffer",
                testStreamBasicDescriptionNilForNonAudioSampleBuffer
            ),
            (
                "AudioCapture.extractInt16InterleavedNilForEmptyBlockBuffer",
                testExtractInt16InterleavedNilForEmptyBlockBuffer
            ),
            (
                "AudioCapture.runtimeErrorNotification",
                testAudioCaptureHandlesRuntimeErrorNotification
            ),
            (
                "AudioCapture.runtimeErrorDebugEmitsStatus",
                testAudioCaptureRuntimeErrorDebugEmitsStatus
            ),
            ("AudioCapture.watchdogTimeoutEmitsError", testAudioCaptureWatchdogTimeoutEmitsError),
            (
                "AudioCapture.sessionInterruptedNotification",
                testAudioCaptureHandlesSessionInterruptedNotification
            ),

            ("SesApp.micPermissionDenied", testSesAppMicPermissionDenied),
            ("SesApp.speechPermissionDenied", testSesAppSpeechPermissionDenied),
            ("SesApp.listDevicesEmitsStatus", testSesAppListDevicesEmitsStatus),
            ("CLI.listDevicesRuns", testCLIDeviceListRuns),
            ("CLI.normalRunForTenSeconds", testCLINormalRunForTenSeconds),
            ("SesApp.normalRunKeepsAliveForTenSeconds", testSesAppNormalRunKeepsAliveForTenSeconds),
            ("SesApp.pipelineFactoryDeviceSelection", testSesAppPipelineFactoryDeviceSelection),

            (
                "StreamController.startMicPermissionDenied",
                testStreamControllerStartMicPermissionDenied
            ),
            (
                "StreamController.startSpeechPermissionDenied",
                testStreamControllerStartSpeechPermissionDenied
            ),
            ("StreamController.stopEmitsStopped", testStreamControllerStopEmitsStopped),
            ("StreamController.alreadyRunning", testStreamControllerAlreadyRunning),
            ("StreamController.accessors", testStreamControllerAccessors),
            ("StreamController.stopNoContext", testStreamControllerStopNoContext),

            ("MCPServer.toolsCallInvalidParams", testMCPServerToolsCallInvalidParams),
            ("MCPServer.toolsCallUnknownTool", testMCPServerToolsCallUnknownTool),
            ("MCPServer.resourcesReadInvalidUri", testMCPServerResourcesReadInvalidUri),
            ("MCPServer.readEventsDefaults", testMCPServerReadEventsDefaults),
            ("MCPServer.readEventsFromBuffer", testMCPServerReadEventsFromBuffer),
            ("MCPServer.resourcesReadFromBuffer", testMCPServerResourcesReadFromBuffer),
            ("MCPServer.basics", testMCPServerBasics),
            ("MCPServer.toolsCallSetConfig", testMCPServerToolsCallSetConfig),
            ("MCPServer.resourcesRead", testMCPServerResourcesRead),

            ("RuntimeContext.nowMs", testRuntimeContextNowMs),
            ("SesPipeline.startStop", testSesPipelineStartStop),
            ("CommitPolicy.init", testCommitPolicyInit),
            ("CommitCoordinator.speechEnd", testCommitCoordinatorSpeechEnd),
            ("CommitCoordinator.silence", testCommitCoordinatorSilence),
        ]
    }
}

Task {
    await runAllTestsAndExit()
}

dispatchMain()
