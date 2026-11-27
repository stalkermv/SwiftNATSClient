//
//  NATSSubscriptionHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS

public typealias NATSSubscriptionCompletionHandler = @convention(c) (UnsafeMutableRawPointer?) -> Void

/// Handle for a NATS subscription. Wraps the underlying C pointer and manages its lifecycle.
public final class NATSSubscriptionHandle {
    /// Underlying pointer to the C natsSubscription object.
    var ptr: OpaquePointer?
    /// Create a handle from a C pointer.
    public init(ptr: OpaquePointer?) { self.ptr = ptr }
    /// Registers a callback invoked after the last message handler returns.
    public func setCompletionCallback(
        _ handler: @escaping NATSSubscriptionCompletionHandler,
        closure: UnsafeMutableRawPointer?
    ) throws {
        guard let ptr else { throw NATSError.subscribeFailed("Invalid subscription") }
        let status = natsSubscription_SetOnCompleteCB(ptr, handler, closure)
        guard status == NATS_OK else {
            throw NATSError.subscribeFailed(String(cString: natsStatus_GetText(status)))
        }
    }

    /// Destroys the subscription on deinit.
    deinit { if let ptr = ptr { natsSubscription_Destroy(ptr) } }
}
