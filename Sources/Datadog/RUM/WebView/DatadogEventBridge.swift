/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias JSON = [String: Any]

internal protocol WebEventConsumer {
    func consume(event: JSON, eventType: String)
}

internal enum WebEventError: Error {
    case dataSerialization(message: String)
    case JSONSerialization(rawJSON: Any)
    case invalidMessage(message: Any)
    case missingKey(key: String, json: JSON)
}

internal class DatadogEventBridge {
    struct Constants {
        static let eventTypeKey = "eventType"
        static let eventKey = "event"
        static let eventTypeLog = "log"
    }

    private let logEventConsumer: WebEventConsumer
    private let rumEventConsumer: WebEventConsumer

    init(logEventConsumer: WebEventConsumer, rumEventConsumer: WebEventConsumer) {
        self.logEventConsumer = logEventConsumer
        self.rumEventConsumer = rumEventConsumer
    }

    func consume(_ message: Any) throws {
        guard let message = message as? String else {
            throw WebEventError.invalidMessage(message: message)
        }
        let eventJSON = try Self.parse(message)
        guard let eventType = eventJSON[Constants.eventTypeKey] as? String else {
            throw WebEventError.missingKey(key: Constants.eventTypeKey, json: eventJSON)
        }
        guard let wrappedEvent = eventJSON[Constants.eventKey] as? JSON else {
            throw WebEventError.missingKey(key: Constants.eventKey, json: eventJSON)
        }

        if eventType == Constants.eventTypeLog {
            logEventConsumer.consume(event: wrappedEvent, eventType: eventType)
        } else {
            rumEventConsumer.consume(event: wrappedEvent, eventType: eventType)
        }
    }

    static func parse(_ message: String) throws -> JSON {
        guard let data = message.data(using: .utf8) else {
            throw WebEventError.dataSerialization(message: message)
        }
        let rawJSON = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = rawJSON as? JSON else {
            throw WebEventError.JSONSerialization(rawJSON: rawJSON)
        }
        return json
    }
}
