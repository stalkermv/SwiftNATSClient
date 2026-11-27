//
//  NATSMsgHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS
import Foundation

/// Owns a C NATS message and releases it when the handle is deinitialized.
public final class NATSMsgHandle {
    private let ptr: OpaquePointer

    /// Takes ownership of a message delivered by a subscription or returned by a request.
    public init(takingOwnershipOf ptr: OpaquePointer) {
        self.ptr = ptr
    }

    deinit {
        natsMsg_Destroy(ptr)
    }

    /// The subject of the message.
    public var subject: String? {
        guard let cstr = natsMsg_GetSubject(ptr) else { return nil }
        return String(cString: cstr)
    }
    /// The data payload of the message.
    public var data: Data? {
        let len = natsMsg_GetDataLength(ptr)
        guard let base = natsMsg_GetData(ptr) else { return nil }
        return Data(bytes: base, count: Int(len))
    }
}
