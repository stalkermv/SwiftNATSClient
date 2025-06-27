//
//  NATSMessage.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import Foundation

public struct NATSMessage: Sendable {
    public let subject: String
    public let data: Data
    public let replyTo: String?
    
    public init(subject: String, data: Data, replyTo: String? = nil) {
        self.subject = subject
        self.data = data
        self.replyTo = replyTo
    }
    
    /// Returns the message data as a UTF-8 string, if possible.
    public var string: String? {
        String(data: data, encoding: .utf8)
    }
}
