import Foundation
import Logging
import NATSCore
import ServiceLifecycle

extension NATSClient {
    actor Lifecycle {
        private enum Phase {
            case idle
            case connecting(UUID)
            case connected(UUID, NativeConnection)
            case closing(UUID)
            case closed
            case failed(any Error)

            var generation: UUID? {
                switch self {
                case .connecting(let generation), .connected(let generation, _), .closing(let generation):
                    return generation
                case .idle, .closed, .failed:
                    return nil
                }
            }
        }

        private enum Subscription {
            case registering
            case registered(NativeSubscription)
        }

        private let configuration: NATSClientConfiguration
        private let logger: Logger?
        private var phase: Phase = .idle
        private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
        private var subscriptions: [UInt: Subscription] = [:]

        init(configuration: NATSClientConfiguration, logger: Logger?) {
            self.configuration = configuration
            self.logger = logger
        }

        var connectionState: ClientState {
            switch phase {
            case .idle: return .idle
            case .connecting: return .connecting
            case .connected: return .connected
            case .closing: return .closing
            case .closed: return .closed
            case .failed: return .failed
            }
        }

        func run(until stop: AsyncStream<Void>) async throws {
            if Task.isCancelled || Task.isShuttingDownGracefully {
                if case .idle = phase { completeShutdown() }
                try Task.checkCancellation()
                return
            }

            switch phase {
            case .idle, .closed:
                break
            case .connecting, .connected:
                return
            case .closing:
                throw NATSError.connectionFailed("Client is closing")
            case .failed(let error):
                throw error
            }

            let generation = UUID()
            phase = .connecting(generation)
            async let _: Void = stopOnSignal(stop, generation: generation)

            let connection: NativeConnection
            do {
                connection = try await NativeConnection.connect(configuration: configuration)
            } catch {
                if case .connecting = phase, !Task.isCancelled, !Task.isShuttingDownGracefully {
                    phase = .failed(error)
                    logger?.error("NATSClient failed to connect: \(error)")
                    throw error
                }
                completeShutdown()
                try Task.checkCancellation()
                return
            }

            if case .connecting = phase, !Task.isCancelled, !Task.isShuttingDownGracefully {
                phase = .connected(generation, connection)
                logger?.info("NATSClient connected to \(configuration.url)")
                await waitForShutdown(generation: generation)
            } else {
                phase = .closing(generation)
                await connection.close()
                completeShutdown()
            }

            try Task.checkCancellation()
        }

        private func stopOnSignal(_ stop: AsyncStream<Void>, generation: UUID) async {
            var iterator = stop.makeAsyncIterator()
            _ = await iterator.next()
            await shutdown(generation: generation)
        }

        func shutdown(generation: UUID? = nil) async {
            if let generation, phase.generation != generation { return }

            switch phase {
            case .idle, .failed:
                completeShutdown()
            case .connecting(let generation):
                phase = .closing(generation)
                await waitForShutdown(generation: generation)
            case .connected(let generation, let connection):
                phase = .closing(generation)
                let subscriptions = self.subscriptions
                self.subscriptions.removeAll()
                for id in subscriptions.keys {
                    SubscriptionRegistry.shared.finish(id)
                }
                await connection.close()
                withExtendedLifetime(subscriptions) {}
                completeShutdown()
                logger?.info("NATSClient disconnected (graceful shutdown)")
            case .closing(let generation):
                await waitForShutdown(generation: generation)
            case .closed:
                break
            }
        }

        private func waitForShutdown(generation: UUID) async {
            await withCheckedContinuation { continuation in
                if phase.generation == generation {
                    shutdownWaiters.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }

        private func completeShutdown() {
            phase = .closed
            let waiters = shutdownWaiters
            shutdownWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        func connection() throws -> NativeConnection {
            guard case .connected(_, let connection) = phase else {
                throw NATSError.connectionFailed("Not connected")
            }
            return connection
        }

        func subscribe(subject: String, id: UInt) async {
            guard SubscriptionRegistry.shared.contains(id) else { return }
            guard case .connected(let generation, let connection) = phase else {
                logger?.warning("Attempt to subscribe to \(subject) when not connected")
                SubscriptionRegistry.shared.finish(id)
                return
            }

            subscriptions[id] = .registering
            do {
                let subscription = try await connection.subscribe(subject: subject, id: id)
                guard case .connected(generation, _) = phase,
                      subscriptions[id] != nil,
                      SubscriptionRegistry.shared.contains(id) else {
                    subscriptions.removeValue(forKey: id)
                    await subscription.unsubscribe()
                    return
                }

                subscriptions[id] = .registered(subscription)
                logger?.info("Subscribed to subject: \(subject)")
            } catch {
                subscriptions.removeValue(forKey: id)
                SubscriptionRegistry.shared.finish(id)
                logger?.debug("Failed to subscribe to subject \(subject): \(error)")
            }
        }

        func unsubscribe(_ id: UInt) async {
            if case .registered(let subscription) = subscriptions.removeValue(forKey: id) {
                await subscription.unsubscribe()
            }
        }
    }
}
