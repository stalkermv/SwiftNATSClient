import Foundation
import NATS
import NATSCore
import Testing

struct OwnershipIntegrationTests {
    @Test
    func testConcurrentShutdownFinishesActiveSubscription() async throws {
        try await withinDeadline("close the connection and subscription under load") {
            try await NATSTestServer.withRunningServer { server in
                let client = makeClient(server)
                try await withThrowingTaskGroup(of: Void.self) { service in
                    service.addTask { try await client.run() }
                    try await waitForConnection(client)

                    let subject = "test.natsclient.shutdown.\(UUID().uuidString)"
                    let data = Data("shutdown".utf8)
                    let messages = client.subscribe(subject: subject)
                    try await server.waitForSubscription(to: subject)
                    try await client.publish(subject: subject, data: data)
                    var iterator = messages.makeAsyncIterator()
                    let initialMessage = try #require(await iterator.next())
                    #expect(initialMessage.data == data)

                    try await withThrowingTaskGroup(of: Void.self) { operations in
                        operations.addTask {
                            for _ in 0..<256 {
                                do {
                                    try await client.publish(subject: subject, data: data)
                                } catch is NATSError {
                                    return
                                }
                            }
                        }
                        operations.addTask { await client.shutdown() }
                        operations.addTask { await client.triggerGracefulShutdown() }
                        try await operations.waitForAll()
                    }

                    while await iterator.next() != nil {}
                    try await service.waitForAll()
                    #expect(await client.connectionState == .closed)
                }
            }
        }
    }

    @Test
    func testCancelledRunClosesTheConnection() async throws {
        try await withinDeadline("close the connection after canceling run") {
            try await NATSTestServer.withRunningServer { server in
                let client = makeClient(server)
                let run = Task { try await client.run() }
                defer { run.cancel() }

                try await waitForConnection(client)
                run.cancel()
                await #expect(throws: CancellationError.self) { try await run.value }
                #expect(await client.connectionState == .closed)
            }
        }
    }
}

private func makeClient(_ server: NATSTestServer) -> NATSClient {
    NATSClient(configuration: .init(
        url: server.clientURL.absoluteString,
        auth: .userPassword(user: NATSTestServer.user, password: NATSTestServer.password)
    ))
}

private func waitForConnection(_ client: NATSClient) async throws {
    try await waitFor("connect the NATS client") {
        let state = await client.connectionState
        if state == .failed || state == .closed { throw IntegrationTestError.clientConnectionFailed }
        return state == .connected
    }
}

private func withinDeadline(
    _ operationDescription: String,
    operation: @escaping @Sendable () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { tasks in
        tasks.addTask(operation: operation)
        tasks.addTask {
            try await Task.sleep(for: .seconds(10))
            throw IntegrationTestError.timedOut(operationDescription)
        }
        defer { tasks.cancelAll() }
        _ = try await tasks.next()
    }
}
