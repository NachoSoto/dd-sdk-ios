/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal class SessionReplayFeature: SessionReplayConfiguration, DatadogRemoteFeature {
    static let name: String = "session-replay"

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?
    let privacyLevel: SessionReplayPrivacyLevel

    // MARK: - Main Components

    /// Orchestrates the process of capturing next snapshots on the main thread.
    let recordingCoordinator: RecordingCoordinator

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws {
        let processorsQueue = BackgroundAsyncQueue(named: "com.datadoghq.session-replay.processors")
        let snapshotProcessor = SnapshotProcessor(
            queue: processorsQueue,
            recordWriter: RecordWriter(core: core),
            srContextPublisher: SRContextPublisher(core: core),
            telemetry: core.telemetry
        )
        let resourceProcessor = ResourceProcessor(
            queue: processorsQueue,
            resourcesWriter: ResourcesWriter(scope: core.scope(for: ResourcesFeature.self))
        )
        let recorder = try Recorder(
            snapshotProcessor: snapshotProcessor,
            resourceProcessor: resourceProcessor,
            telemetry: core.telemetry,
            additionalNodeRecorders: configuration._additionalNodeRecorders
        )
        let scheduler = MainThreadScheduler(interval: 0.1)
        let contextReceiver = RUMContextReceiver()

        self.privacyLevel = configuration.defaultPrivacyLevel
        self.messageReceiver = CombinedFeatureMessageReceiver([
            contextReceiver,
            WebViewRecordReceiver(
                scope: core.scope(for: SessionReplayFeature.self)
            )
        ])

        self.recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            privacy: configuration.defaultPrivacyLevel,
            rumContextObserver: contextReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.replaySampleRate)
        )
        self.requestBuilder = SegmentRequestBuilder(
            customUploadURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: SessionReplay.maxObjectSize,
            maxObjectSize: SessionReplay.maxObjectSize,
            meanFileAge: 2, // vs 5s with `batchSize: .small` - see `DatadogCore.PerformancePreset`
            uploadDelay: (
                initial: 2, // vs 5s with `uploadFrequency: .frequent`
                range: 0.6..<6, // vs 1s ..< 10s with `uploadFrequency: .frequent`
                changeRate: 0.75 // vs 0.1 with `uploadFrequency: .frequent`
            )
        )
    }
}
#endif
