// NATS.swift
// High-level async/await API for NATS (to be implemented)

import Foundation
import ServiceLifecycle
import NATSCore
import Logging

public final class NATSClient: Service, @unchecked Sendable {
    
    public let configuration: NATSClientConfiguration
    
    private let logger: Logger?
    private var conn: NATSConnectionHandle? = nil
    private let stateHolder = StateHolder()
    private var shutdownRequested = false
    
    public init(configuration: NATSClientConfiguration, logger: Logger? = nil) {
        self.configuration = configuration
        self.logger = logger
    }
    
    /// ServiceLifecycle entrypoint. Runs until shutdown is triggered.
    public func run() async throws {
        try await withGracefulShutdownHandler {
            try await self._run()
        } onGracefulShutdown: {
            Task { await self.triggerGracefulShutdown() }
        }
    }
    
    private func makeOptions() -> NATSOptionsHandle {
        let opts = NATSOptionsHandle()
        opts.setURL(configuration.url)
        // Reconnect options
        // opts.setReconnect(configuration.reconnect)
        // opts.setMaxReconnects(configuration.maxReconnects)
        // opts.setReconnectWait(configuration.reconnectWait)
        // Auth
        switch configuration.auth {
        case .none:
            break
        case .userPassword(let user, let password):
            opts.setUserInfo(user: user, password: password)
        case .token(let token):
            opts.setToken(token)
        case .nkey:
            // NKey підтримується лише через creds-файл (JWT+NKey)
            break // Для простоти, не підтримуємо окремо seed
        case .jwtCredsFile(let file):
            opts.setUserCredentialsFile(file)
        }
        return opts
    }
    
    private func _run() async throws {
        let state = await stateHolder.getState()
        switch state {
        case .idle, .closed:
            await stateHolder.setState(.connecting)
            do {
                let opts = makeOptions()
                let conn = NATSConnectionHandle()
                try conn.connect(options: opts)
                self.conn = conn
                await stateHolder.setState(.connected)
                logger?.info("NATSClient connected to \(configuration.url)")
                // Wait until shutdown is requested
                while await stateHolder.getState() == .connected && !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
            } catch {
                await stateHolder.setState(.failed(error))
                logger?.error("NATSClient failed to connect: \(error)")
                throw error
            }
        case .connecting, .connected:
            return
        case .closing:
            throw NATSError.connectionFailed("Client is closing")
        case .failed(let error):
            throw error
        }
    }
    
    /// Triggers graceful shutdown (ServiceLifecycle compatible)
    public func triggerGracefulShutdown() async {
        let state = await stateHolder.getState()
        if case .connected = state {
            await stateHolder.setState(.closing)
            conn?.close()
            conn = nil
            await stateHolder.setState(.closed)
            logger?.info("NATSClient disconnected (graceful shutdown)")
        } else {
            await stateHolder.setState(.closed)
        }
    }
    
    /// Legacy shutdown for compatibility
    public func shutdown() async {
        await triggerGracefulShutdown()
    }
    
    /// Async publish
    public func publish(subject: String, data: Data) async throws {
        let state = await stateHolder.getState()
        guard case .connected = state, let conn else {
            throw NATSError.connectionFailed("Not connected")
        }
        try conn.publish(subject: subject, data: data)
    }
    
    /// Async request/reply
    public func request(subject: String, data: Data, timeout: TimeInterval = 2.0) async throws -> NATSMessage {
        let state = await stateHolder.getState()
        guard case .connected = state, let conn else {
            throw NATSError.connectionFailed("Not connected")
        }
        let msg = try conn.request(subject: subject, data: data, timeout: Int64(timeout * 1000))
        return NATSMessage(subject: msg.subject ?? subject, data: msg.data ?? Data(), replyTo: nil)
    }
    
    /// Type-erased AsyncSequence для підписки, автоматично завершується при graceful shutdown
    public func subscribe(subject: String) -> AsyncCancelOnGracefulShutdownSequence<AsyncStream<NATSMessage>> {
        let baseStream = AsyncStream<NATSMessage> { continuation in
            Task {
                let state = await stateHolder.getState()
                guard case .connected = state, let conn else {
                    logger?.warning("[NATSClient] Attempt to subscribe to \(subject) when not connected.")
                    continuation.finish()
                    return
                }
                let box = MutableBox(continuation)
                let unmanaged = Unmanaged.passRetained(box).toOpaque()
                let handler: NATSMsgHandler = { _, _, msgPtr, closure in
                    guard let msgPtr = msgPtr, let closure = closure else { return }
                    typealias Box = MutableBox<AsyncStream<NATSMessage>.Continuation>
                    let box = Unmanaged<Box>.fromOpaque(closure).takeUnretainedValue()
                    let msg = NATSMsgHandle(ptr: msgPtr)
                    if let subject = msg.subject, let data = msg.data {
                        box.value.yield(NATSMessage(subject: subject, data: data, replyTo: nil))
                    }
                }
                let sub = try? conn.subscribe(subject: subject, callback: handler, closure: unmanaged)
                logger?.debug("[NATSClient] Subscribing to subject: \(subject)")
                if sub == nil {
                    logger?.error("[NATSClient] Failed to subscribe to subject: \(subject)")
                    continuation.finish()
                    Unmanaged<MutableBox<AsyncStream<NATSMessage>.Continuation>>.fromOpaque(unmanaged).release()
                    return
                }
                logger?.info("[NATSClient] Subscribed to subject: \(subject)")
                let releaseUnmanaged = { Unmanaged<MutableBox<AsyncStream<NATSMessage>.Continuation>>.fromOpaque(unmanaged).release() }
                continuation.onTermination = { [weak self] _ in
                    try? sub?.unsubscribe()
                    self?.logger?.info("[NATSClient] Subscription terminated for subject: \(subject)")
                    releaseUnmanaged()
                }
            }
        }
        return baseStream.cancelOnGracefulShutdown()
    }
    
    public enum ClientState: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case closing
        case closed
        case failed
    }
    public var connectionState: ClientState {
        get async {
            let state = await stateHolder.getState()
            switch state {
            case .idle: return .idle
            case .connecting: return .connecting
            case .connected: return .connected
            case .closing: return .closing
            case .closed: return .closed
            case .failed: return .failed
            }
        }
    }
}

