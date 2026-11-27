import Foundation
import Logging
import NATSCore
import ServiceLifecycle

public final class NATSClient: Service, Sendable {
    public let configuration: NATSClientConfiguration
    private let lifecycle: Lifecycle

    public init(configuration: NATSClientConfiguration, logger: Logger? = nil) {
        self.configuration = configuration
        self.lifecycle = Lifecycle(configuration: configuration, logger: logger)
    }

    /// Runs the client until graceful shutdown or cancellation.
    public func run() async throws {
        let (stop, signalStop) = AsyncStream<Void>.makeStream()
        try await withTaskCancellationOrGracefulShutdownHandler {
            try await lifecycle.run(until: stop)
        } onCancelOrGracefulShutdown: {
            signalStop.finish()
        }
    }

    /// Triggers graceful shutdown and waits until the connection is closed.
    public func triggerGracefulShutdown() async {
        await lifecycle.shutdown()
    }

    public func shutdown() async {
        await triggerGracefulShutdown()
    }

    public func publish(subject: String, data: Data) async throws {
        let connection = try await lifecycle.connection()
        try await connection.publish(subject: subject, data: data)
    }

    /// Sends a request. A submitted native request runs until a reply, timeout, or connection closure.
    public func request(subject: String, data: Data, timeout: TimeInterval = 2.0) async throws -> NATSMessage {
        let connection = try await lifecycle.connection()
        guard let milliseconds = Int64(exactly: (timeout * 1_000).rounded(.towardZero)), milliseconds >= 0 else {
            throw NATSError.publishFailed("Request timeout must be finite, nonnegative, and fit in Int64 milliseconds")
        }
        try Task.checkCancellation()
        let result = await connection.request(subject: subject, data: data, timeout: milliseconds)
        try Task.checkCancellation()
        return try result.get()
    }

    public func subscribe(subject: String) -> AsyncCancelOnGracefulShutdownSequence<AsyncStream<NATSMessage>> {
        let lifecycle = self.lifecycle
        let messages = AsyncStream<NATSMessage> { continuation in
            let id = SubscriptionRegistry.shared.insert(continuation)
            continuation.onTermination = { [weak lifecycle] _ in
                SubscriptionRegistry.shared.remove(id)
                Task { await lifecycle?.unsubscribe(id) }
            }
            Task { await lifecycle.subscribe(subject: subject, id: id) }
        }

        return messages.cancelOnGracefulShutdown()
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
        get async { await lifecycle.connectionState }
    }
}
