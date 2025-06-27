//
//  CallbackTypealiases.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS

public typealias NATSConnectionHandler = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void
public typealias NATSErrorHandler = @convention(c) (OpaquePointer?, OpaquePointer?, natsStatus, UnsafeMutableRawPointer?) -> Void
public typealias NATSMsgHandler = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void
