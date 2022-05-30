/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggerBuilderTests: XCTestCase {
    let core = DatadogCoreMock()

    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()

        let feature: LoggingFeature = .mockByRecordingLogMatchers(
            directory: temporaryDirectory,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.2.3",
                    applicationBundleIdentifier: "com.datadog.unit-tests",
                    serviceName: "service-name",
                    environment: "tests"
                )
            ),
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        )

        core.register(feature: feature)
    }

    override func tearDown() {
        core.flush()
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = Logger.builder.build(in: core)

        XCTAssertNil(logger.rumContextIntegration)
        XCTAssertNil(logger.activeSpanIntegration)

        let feature = try XCTUnwrap(core.feature(LoggingFeature.self))
        XCTAssertTrue(
            logger.logOutput is LogFileOutput,
            "When Logging feature is enabled the Logger should use `LogFileOutput`."
        )
        let logBuilder = try XCTUnwrap(
            logger.logBuilder,
            "When Logging feature is enabled the Logger should use `LogBuilder`."
        )

        XCTAssertEqual(logBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(logBuilder.serviceName, "service-name")
        XCTAssertEqual(logBuilder.environment, "tests")
        XCTAssertEqual(logBuilder.loggerName, "com.datadog.unit-tests")
        XCTAssertTrue(logBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertNil(logBuilder.networkConnectionInfoProvider)
        XCTAssertNil(logBuilder.carrierInfoProvider)
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil(logger1.rumContextIntegration)

        let logger2 = Logger.builder.bundleWithRUM(false).build()
        XCTAssertNil(logger2.rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        let tracing: TracingFeature = .mockNoOp()
        core.register(feature: tracing)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil(logger1.activeSpanIntegration)

        let logger2 = Logger.builder.bundleWithTrace(false).build(in: core)
        XCTAssertNil(logger2.activeSpanIntegration)
    }

    func testCustomizedLogger() throws {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let tracing: TracingFeature = .mockNoOp()
        core.register(feature: tracing)

        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .bundleWithRUM(false)
            .bundleWithTrace(false)
            .build(in: core)

        XCTAssertNil(logger.rumContextIntegration)
        XCTAssertNil(logger.activeSpanIntegration)

        let feature = try XCTUnwrap(core.feature(LoggingFeature.self))
        XCTAssertTrue(
            logger.logOutput is LogFileOutput,
            "When Logging feature is enabled the Logger should use `LogFileOutput`."
        )
        let logBuilder = try XCTUnwrap(
            logger.logBuilder,
            "When Logging feature is enabled the Logger should use `LogBuilder`."
        )

        XCTAssertEqual(logBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(logBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(logBuilder.environment, "tests")
        XCTAssertEqual(logBuilder.loggerName, "custom-logger-name")
        XCTAssertTrue(logBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(logBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(logBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
    }

    func testUsingDifferentOutputs() throws {
        var logger: Logger

        logger = Logger.builder.build(in: core)
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertTrue(logger.logOutput is LogFileOutput)

        logger = Logger.builder.sendLogsToDatadog(true).build(in: core)
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertTrue(logger.logOutput is LogFileOutput)

        logger = Logger.builder.sendLogsToDatadog(false).build(in: core)
        XCTAssertNil(logger.logBuilder)
        XCTAssertNil(logger.logOutput)

        logger = Logger.builder.printLogsToConsole(true).build(in: core)
        var combinedOutputs = try (logger.logOutput as? CombinedLogOutput).unwrapOrThrow().combinedOutputs
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertEqual(combinedOutputs.count, 2)
        XCTAssertTrue(combinedOutputs[0] is LogFileOutput)
        XCTAssertTrue(combinedOutputs[1] is LogConsoleOutput)

        logger = Logger.builder.printLogsToConsole(false).build(in: core)
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertTrue(logger.logOutput is LogFileOutput)

        logger = Logger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(in: core)
        combinedOutputs = try (logger.logOutput as? CombinedLogOutput).unwrapOrThrow().combinedOutputs
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertEqual(combinedOutputs.count, 2)
        XCTAssertTrue(combinedOutputs[0] is LogFileOutput)
        XCTAssertTrue(combinedOutputs[1] is LogConsoleOutput)

        logger = Logger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(in: core)
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertTrue(logger.logOutput is LogConsoleOutput)

        logger = Logger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(in: core)
        XCTAssertNotNil(logger.logBuilder)
        XCTAssertTrue(logger.logOutput is LogFileOutput)

        logger = Logger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(in: core)
        XCTAssertNil(logger.logBuilder)
        XCTAssertNil(logger.logOutput)
    }
}
