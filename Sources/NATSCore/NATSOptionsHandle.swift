//
//  NATSOptionsHandle.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

import CNATS
import Crypto

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

    /// Configure NKey authentication using an encoded seed.
    public func setNKey(seed: String) {
        guard let pub = NKeyUtilities.publicKey(fromSeed: seed) else { return }
        let seedPtr = strdup(seed)
        let cb: NATSSignatureHandler = { _, sigPtr, sigLenPtr, nonce, closure in
            guard let nonce, let closure else { return NATS_INVALID_ARG }
            let seed = closure.assumingMemoryBound(to: CChar.self)
            var sig: UnsafeMutablePointer<UInt8>? = nil
            var sigLen: Int32 = 0
            let s = nats_Sign(seed, nonce, &sig, &sigLen)
            if s == NATS_OK {
                sigPtr?.pointee = sig
                sigLenPtr?.pointee = sigLen
            }
            return s
        }
        natsOptions_SetNKey(ptr, pub, cb, UnsafeMutableRawPointer(seedPtr))
    }
}

// MARK: - NKey helpers

enum NKeyUtilities {
    static func publicKey(fromSeed seed: String) -> String? {
        let maxLen = Int(Double(seed.count) * 5.0 / 8.0) + 10
        var raw = [Int8](repeating: 0, count: maxLen)
        var rawLen: Int32 = 0
        seed.withCString { src in
            raw.withUnsafeMutableBufferPointer { ptr in
                _ = nats_Base32_DecodeString(src, ptr.baseAddress, Int32(maxLen), &rawLen)
            }
        }
        if rawLen < 36 { return nil }
        let seedBytes: [UInt8] = raw.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            return (0..<Int(rawLen)).map { UInt8(bitPattern: base[$0]) }
        }
        let prefix = seedBytes[1]
        let priv = Array(seedBytes[2..<(2+32)])
        guard let sk = try? Curve25519.Signing.PrivateKey(rawRepresentation: priv) else { return nil }
        var pubData = [UInt8]()
        pubData.append(prefix)
        pubData.append(contentsOf: sk.publicKey.rawRepresentation)
        let crc = pubData.withUnsafeMutableBufferPointer { ptr in
            nats_CRC16_Compute(ptr.baseAddress, Int32(ptr.count))
        }
        pubData.append(UInt8(crc & 0xff))
        pubData.append(UInt8((crc >> 8) & 0xff))
        return base32Encode(pubData)
    }

    private static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private static func base32Encode(_ bytes: [UInt8]) -> String {
        var output = ""
        var buffer: Int = 0
        var bitsLeft: Int = 0
        for b in bytes {
            buffer = (buffer << 8) | Int(b)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 0x1F
                output.append(alphabet[index])
                bitsLeft -= 5
            }
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            output.append(alphabet[index])
        }
        return output
    }
}

