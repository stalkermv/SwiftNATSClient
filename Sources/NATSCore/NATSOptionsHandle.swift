//
//  NATSOptionsHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS

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
}
