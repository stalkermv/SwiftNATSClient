//
//  NATSMsgHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS
import Foundation

/// Handle for a NATS message. Wraps the underlying C pointer and provides accessors.
public struct NATSMsgHandle {
    /// Underlying pointer to the C natsMsg object.
    public let ptr: OpaquePointer
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
    /// Destroys the message and releases memory.
    public func destroy() { natsMsg_Destroy(ptr) }

    public init(ptr: OpaquePointer) {
        self.ptr = ptr
    }
}
