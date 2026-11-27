import Foundation
import Logging
import NATS
import NATSCore
import ServiceLifecycle
import Testing

struct IntegrationTests {
    @Test
    func testNATSClientConnectAndShutdown() async throws {
        try await withClient { client, _ in
            let state = await client.connectionState
            #expect(state == .connected)
        }
    }

    @Test
    func testNATSClientPublishSubscribe() async throws {
        try await withClient { client, server in
            let subject = "test.natsclient.pubsub.\(UUID().uuidString)"
            let messages = client.subscribe(subject: subject)
            try await expectRoundTrip(on: client, through: server, subject: subject, messages: messages)
        }
    }

    @Test
    func testReconnectAfterServerRestart() async throws {
        try await withClient(reconnectWait: 0.25) { client, server in
            let subject = "test.natsclient.reconnect.\(UUID().uuidString)"
            let messages = client.subscribe(subject: subject)
            try await server.waitForSubscription(to: subject)
            try await server.restart()
            try await expectRoundTrip(on: client, through: server, subject: subject, messages: messages)
        }
    }

    @Test
    func testReconnectDisabledAfterServerRestart() async throws {
        try await withClient(reconnect: false) { client, server in
            try await server.restart()
            try await waitFor("close the NATS connection with reconnect disabled") {
                do {
                    // A reconnecting connection buffers publishes. A closed connection rejects them.
                    try await client.publish(subject: "test.natsclient.closed", data: Data())
                    return false
                } catch NATSError.publishFailed {
                    return true
                }
            }
        }
    }

    private func expectRoundTrip(
        on client: NATSClient,
        through server: NATSTestServer,
        subject: String,
        messages: AsyncCancelOnGracefulShutdownSequence<AsyncStream<NATSMessage>>
    ) async throws {
        let payload = Data("hello highlevel".utf8)
        try await server.waitForSubscription(to: subject)
        try await client.publish(subject: subject, data: payload)

        let message = try await withDeadline("receive message on \(subject)") {
            var iterator = messages.makeAsyncIterator()
            return await iterator.next()
        }
        let received = try #require(message)
        #expect(received.subject == subject)
        #expect(received.data == payload)
    }

    private func withClient(
        reconnect: Bool = true,
        reconnectWait: TimeInterval = 2,
        _ body: (NATSClient, NATSTestServer) async throws -> Void
    ) async throws {
        try await NATSTestServer.withRunningServer { server in
            let logger = Logger(label: "NATSClientTests")
            let client = NATSClient(
                configuration: .init(
                    url: server.clientURL.absoluteString,
                    reconnect: reconnect,
                    reconnectWait: reconnectWait,
                    auth: .userPassword(user: NATSTestServer.user, password: NATSTestServer.password)
                ),
                logger: logger
            )
            var configuration = ServiceGroupConfiguration(services: [client], logger: logger)
            configuration.maximumGracefulShutdownDuration = .seconds(5)
            configuration.maximumCancellationDuration = .seconds(5)
            let serviceGroup = ServiceGroup(configuration: configuration)

            try await withThrowingTaskGroup(of: Void.self) { tasks in
                tasks.addTask { try await serviceGroup.run() }

                try await waitFor("connect to the NATS test server") {
                    let state = await client.connectionState
                    if state == .failed || state == .closed {
                        throw IntegrationTestError.clientConnectionFailed
                    }
                    return state == .connected
                }

                try await body(client, server)

                await serviceGroup.triggerGracefulShutdown()
                try await tasks.waitForAll()
                // The graceful shutdown handler closes the connection in a separate task.
                try await waitFor("finish the NATS client shutdown") {
                    await client.connectionState == .closed
                }
            }
        }
    }
}

private func withDeadline<Value: Sendable>(
    _ description: String,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { tasks in
        tasks.addTask(operation: operation)
        tasks.addTask {
            try await Task.sleep(for: .seconds(5))
            throw IntegrationTestError.timedOut(description)
        }
        defer { tasks.cancelAll() }
        let result = try await tasks.next()
        return try #require(result)
    }
}
