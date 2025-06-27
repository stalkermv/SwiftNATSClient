//
//  NATSClientConfiguration.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import Foundation

public enum NATSAuthMode: Sendable, Equatable {
    case none
    case userPassword(user: String, password: String)
    case token(String)
    case nkey(seed: String)
    case jwtCredsFile(file: String)
}

public struct NATSClientConfiguration: Sendable {
    public let url: String
    public let reconnect: Bool
    public let maxReconnects: Int
    public let reconnectWait: TimeInterval
    public let auth: NATSAuthMode
    
    public init(
        url: String = "nats://localhost:4222",
        reconnect: Bool = true,
        maxReconnects: Int = 10,
        reconnectWait: TimeInterval = 2.0,
        auth: NATSAuthMode = .none
    ) {
        self.url = url
        self.reconnect = reconnect
        self.maxReconnects = maxReconnects
        self.reconnectWait = reconnectWait
        self.auth = auth
    }
}
