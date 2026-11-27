//
//  NATSOptionsHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS
import Foundation

/// Handle for NATS options. Wraps the underlying C pointer and provides methods to set various options.
public final class NATSOptionsHandle {
    
    var ptr: OpaquePointer?
    
    public init() {
        natsOptions_Create(&ptr)
    }
    
    deinit {
        if let ptr = ptr { natsOptions_Destroy(ptr) }
    }
    
    public func setURL(_ url: String) {
        natsOptions_SetURL(ptr, url)
    }
    
    public func setClosedCallback(_ cb: @escaping NATSConnectionHandler, closure: UnsafeMutableRawPointer?) {
        natsOptions_SetClosedCB(ptr, cb, closure)
    }
    
    public func setDisconnectedCallback(_ cb: @escaping NATSConnectionHandler, closure: UnsafeMutableRawPointer?) {
        natsOptions_SetDisconnectedCB(ptr, cb, closure)
    }
    
    public func setReconnectedCallback(_ cb: @escaping NATSConnectionHandler, closure: UnsafeMutableRawPointer?) {
        natsOptions_SetReconnectedCB(ptr, cb, closure)
    }
    
    public func setErrorCallback(_ cb: @escaping NATSErrorHandler, closure: UnsafeMutableRawPointer?) {
        natsOptions_SetErrorHandler(ptr, cb, closure)
    }
    
    public func setUserInfo(user: String, password: String) {
        natsOptions_SetUserInfo(ptr, user, password)
    }
    
    public func setToken(_ token: String) {
        natsOptions_SetToken(ptr, token)
    }
    
    public func setUserCredentialsFile(_ file: String) {
        natsOptions_SetUserCredentialsFromFiles(ptr, file, nil)
    }

    public func setAllowReconnect(_ allow: Bool) {
        natsOptions_SetAllowReconnect(ptr, allow)
    }

    /// Sets the maximum reconnect count accepted by the native client.
    /// - Throws: `NATSError.connectionFailed` if the count is out of range or the native setter rejects it.
    public func setMaxReconnects(_ max: Int) throws {
        guard let count = Int32(exactly: max) else {
            throw NATSError.connectionFailed("Max reconnects must fit in a 32-bit signed integer")
        }
        let status = natsOptions_SetMaxReconnect(ptr, count)
        guard status == NATS_OK else {
            let reason = String(cString: natsStatus_GetText(status))
            throw NATSError.connectionFailed("Could not set max reconnects: \(reason)")
        }
    }

    /// Sets the delay between reconnect attempts, in seconds. Fractional milliseconds are truncated.
    /// - Throws: `NATSError.connectionFailed` if the delay is invalid or the native setter rejects it.
    public func setReconnectWait(_ seconds: TimeInterval) throws {
        let delay = try NATSReconnectDelay(seconds)
        let status = natsOptions_SetReconnectWait(ptr, delay.milliseconds)
        guard status == NATS_OK else {
            let reason = String(cString: natsStatus_GetText(status))
            throw NATSError.connectionFailed("Could not set reconnect wait: \(reason)")
        }
    }
}

private struct NATSReconnectDelay {
    let milliseconds: Int64

    init(_ seconds: TimeInterval) throws {
        guard seconds >= 0,
              let milliseconds = Int64(exactly: (seconds * 1_000).rounded(.towardZero)) else {
            throw NATSError.connectionFailed("Reconnect wait must be finite, nonnegative, and fit in Int64 milliseconds")
        }
        self.milliseconds = milliseconds
    }
}
