import Dispatch
import Foundation
import NATSCore

// The handle is initialized before publication and never reconnected manually.
// While work is in flight its closure retains this wrapper. nats.c serializes
// operations on a connected handle, including close versus a blocking request.
final class NativeConnection: @unchecked Sendable {
    private static let connectQueue = DispatchQueue(label: "SwiftNATSClient.connect", attributes: .concurrent)
    private static let requestQueue = DispatchQueue(label: "SwiftNATSClient.request", attributes: .concurrent)
    private let controlQueue = DispatchQueue(label: "SwiftNATSClient.connection")
    private let handle: NATSConnectionHandle

    private init(_ handle: NATSConnectionHandle) {
        self.handle = handle
    }

    static func connect(configuration: NATSClientConfiguration) async throws -> NativeConnection {
        try await connectQueue.submit {
            Result {
                let options = NATSOptionsHandle()
                options.setURL(configuration.url)
                options.setAllowReconnect(configuration.reconnect)
                if configuration.reconnect {
                    try options.setMaxReconnects(configuration.maxReconnects)
                    try options.setReconnectWait(configuration.reconnectWait)
                }

                switch configuration.auth {
                case .none:
                    break
                case .userPassword(let user, let password):
                    options.setUserInfo(user: user, password: password)
                case .token(let token):
                    options.setToken(token)
                case .nkey(let seed):
                    try options.setNKey(seed: seed)
                case .jwtCredsFile(let file):
                    options.setUserCredentialsFile(file)
                }

                let handle = NATSConnectionHandle()
                try handle.connect(options: options)
                return NativeConnection(handle)
            }
        }.get()
    }

    func close() async {
        await controlQueue.submit { self.handle.close() }
    }

    func publish(subject: String, data: Data) async throws {
        try await controlQueue.submit {
            Result { try self.handle.publish(subject: subject, data: data) }
        }.get()
    }

    func request(subject: String, data: Data, timeout: Int64) async -> Result<NATSMessage, any Error> {
        await Self.requestQueue.submit {
            Result {
                let message = try self.handle.request(subject: subject, data: data, timeout: timeout)
                return NATSMessage(subject: message.subject ?? subject, data: message.data ?? Data())
            }
        }
    }

    func subscribe(subject: String, id: UInt) async throws -> NativeSubscription {
        try await controlQueue.submit {
            Result {
                let opaqueID = UnsafeMutableRawPointer(bitPattern: id)
                let subscription = try self.handle.subscribe(
                    subject: subject,
                    callback: SubscriptionRegistry.receiveMessage,
                    closure: opaqueID
                )
                try subscription.setCompletionCallback(SubscriptionRegistry.subscriptionCompleted, closure: opaqueID)
                return NativeSubscription(subscription, queue: self.controlQueue)
            }
        }.get()
    }
}

final class NativeSubscription: @unchecked Sendable {
    private let subscription: NATSSubscriptionHandle
    private let queue: DispatchQueue

    init(_ subscription: NATSSubscriptionHandle, queue: DispatchQueue) {
        self.subscription = subscription
        self.queue = queue
    }

    func unsubscribe() async {
        _ = await queue.submit { try? self.subscription.unsubscribe() }
    }
}

private extension DispatchQueue {
    func submit<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            async { continuation.resume(returning: work()) }
        }
    }
}
