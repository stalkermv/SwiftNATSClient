// NATSCore.swift
// Low-level Swift wrapper for CNATS. Provides type-safe, resource-safe, documented API for NATS core operations.

import CNATS
import Foundation

// MARK: - NATSConnectionHandle
public final class NATSConnectionHandle {
    var ptr: OpaquePointer?
    
    public init() { self.ptr = nil }
    
    deinit { if let ptr = ptr { natsConnection_Destroy(ptr) } }
    
    /// Connects to the NATS server using the provided options.
    public func connect(options: NATSOptionsHandle) throws {
        var c: OpaquePointer? = nil
        let status = natsConnection_Connect(&c, options.ptr)
        if status == NATS_OK {
            self.ptr = c
        } else {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.connectionFailed(errStr)
        }
    }
    
    /// Publishes a message to the specified subject.
    public func publish(subject: String, data: Data) throws {
        guard let ptr = ptr else { throw NATSError.publishFailed("Not connected") }
        let status = data.withUnsafeBytes { buf in
            natsConnection_Publish(ptr, subject, buf.baseAddress, Int32(buf.count))
        }
        if status != NATS_OK {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.publishFailed(errStr)
        }
    }
    
    /// Closes the connection.
    public func close() {
        if let ptr = ptr { natsConnection_Close(ptr) }
    }
    
    /// Checks if the connection is currently connected.
    public var isConnected: Bool {
        guard let ptr = ptr else { return false }
        return natsConnection_Status(ptr) == NATS_CONN_STATUS_CONNECTED
    }
    
    /// Subscribes to a subject with a callback handler.
    public func subscribe(subject: String, callback: @escaping NATSMsgHandler, closure: UnsafeMutableRawPointer?) throws -> NATSSubscriptionHandle {
        guard let ptr = ptr else { throw NATSError.subscribeFailed("Not connected") }
        var subPtr: OpaquePointer? = nil
        let status = natsConnection_Subscribe(&subPtr, ptr, subject, callback, closure)
        if status == NATS_OK, let subPtr = subPtr {
            return NATSSubscriptionHandle(ptr: subPtr)
        } else {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.subscribeFailed(errStr)
        }
    }
}

// MARK: - NATSConnectionHandle
extension NATSConnectionHandle {
    /// Unsubscribes and destroys the subscription.
    /// - Parameter subscription: Subscription handle to unsubscribe.
    /// - Throws: NATSError on failure.
    public func unsubscribe(_ subscription: NATSSubscriptionHandle) throws {
        guard let subPtr = subscription.ptr else { throw NATSError.subscribeFailed("Invalid subscription") }
        let status = natsSubscription_Unsubscribe(subPtr)
        if status != NATS_OK {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.subscribeFailed("Unsubscribe failed: \(errStr)")
        }
    }

    /// Drains the subscription (graceful unsubscribe).
    /// - Parameter subscription: Subscription handle to drain.
    /// - Throws: NATSError on failure.
    public func drain(_ subscription: NATSSubscriptionHandle) throws {
        guard let subPtr = subscription.ptr else { throw NATSError.subscribeFailed("Invalid subscription") }
        let status = natsSubscription_Drain(subPtr)
        if status != NATS_OK {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.subscribeFailed("Drain failed: \(errStr)")
        }
    }

    /// Creates a queue subscription.
    /// - Parameters:
    ///   - subject: Subject to subscribe to.
    ///   - queue: Queue group name.
    ///   - callback: C-style message handler.
    ///   - closure: User context (e.g. Unmanaged.passUnretained(...).toOpaque()).
    /// - Returns: NATSSubscriptionHandle
    /// - Throws: NATSError on failure.
    public func queueSubscribe(subject: String, queue: String, callback: @escaping NATSMsgHandler, closure: UnsafeMutableRawPointer?) throws -> NATSSubscriptionHandle {
        guard let ptr = ptr else { throw NATSError.subscribeFailed("Not connected") }
        var subPtr: OpaquePointer? = nil
        let status = natsConnection_QueueSubscribe(&subPtr, ptr, subject, queue, callback, closure)
        if status == NATS_OK, let subPtr = subPtr {
            return NATSSubscriptionHandle(ptr: subPtr)
        } else {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.subscribeFailed("QueueSubscribe failed: \(errStr)")
        }
    }

    /// Sends a request and waits for a reply (low-level).
    /// - Parameters:
    ///   - subject: Subject to send request to.
    ///   - data: Request payload.
    ///   - timeout: Timeout in milliseconds.
    /// - Returns: NATSMsgHandle with reply.
    /// - Throws: NATSError on failure or timeout.
    public func request(subject: String, data: Data, timeout: Int64 = 2000) throws -> NATSMsgHandle {
        guard let ptr = ptr else { throw NATSError.publishFailed("Not connected") }
        var msgPtr: OpaquePointer? = nil
        let status = data.withUnsafeBytes { buf in
            natsConnection_Request(&msgPtr, ptr, subject, buf.baseAddress, Int32(buf.count), timeout)
        }
        if status == NATS_OK, let msgPtr = msgPtr {
            return NATSMsgHandle(ptr: msgPtr)
        } else {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.publishFailed("Request failed: \(errStr)")
        }
    }
}

// MARK: - NATSSubscriptionHandle (доповнення)
extension NATSSubscriptionHandle {
    /// Unsubscribes and destroys the subscription.
    /// - Throws: NATSError on failure.
    public func unsubscribe() throws {
        guard let ptr = ptr else { throw NATSError.subscribeFailed("Invalid subscription") }
        let status = natsSubscription_Unsubscribe(ptr)
        if status != NATS_OK {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.subscribeFailed("Unsubscribe failed: \(errStr)")
        }
    }
    /// Drains the subscription (graceful unsubscribe).
    /// - Throws: NATSError on failure.
    public func drain() throws {
        guard let ptr = ptr else { throw NATSError.subscribeFailed("Invalid subscription") }
        let status = natsSubscription_Drain(ptr)
        if status != NATS_OK {
            let errStr = String(cString: natsStatus_GetText(status))
            throw NATSError.subscribeFailed("Drain failed: \(errStr)")
        }
    }
}
