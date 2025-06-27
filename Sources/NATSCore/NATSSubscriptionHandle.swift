//
//  NATSSubscriptionHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS

/// Handle for a NATS subscription. Wraps the underlying C pointer and manages its lifecycle.
public final class NATSSubscriptionHandle {
    /// Underlying pointer to the C natsSubscription object.
    var ptr: OpaquePointer?
    /// Create a handle from a C pointer.
    public init(ptr: OpaquePointer?) { self.ptr = ptr }
    /// Destroys the subscription on deinit.
    deinit { if let ptr = ptr { natsSubscription_Destroy(ptr) } }
}
