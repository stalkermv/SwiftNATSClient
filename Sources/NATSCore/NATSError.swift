//
//  NATSError.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

/// Represents errors that can occur in the NATS client operations.
public enum NATSError: Error {
    case connectionFailed(String)
    case publishFailed(String)
    case subscribeFailed(String)
    case unknown(Int32)
}
