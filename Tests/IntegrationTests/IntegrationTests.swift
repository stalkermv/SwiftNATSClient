import Foundation
import Logging
import NATS
import ServiceLifecycle
import XCTest

final class IntegrationTests: XCTestCase {
    func testNATSClientConnectAndShutdown() async throws {
        try await withConnectedClient { client in
            let state = await client.connectionState
            XCTAssertEqual(state, .connected)
        }
    }

    func testNATSClientPublishSubscribe() async throws {
        try await withConnectedClient { client in
            let subject = "test.natsclient.pubsub"
            let data = Data("hello highlevel".utf8)
            let stream = client.subscribe(subject: subject)

            try await withThrowingTaskGroup(of: Void.self) { tasks in
                tasks.addTask {
                    for await message in stream {
                        XCTAssertEqual(message.subject, subject)
                        XCTAssertEqual(message.data, data)
                        return
                    }
                    throw TestError.subscriptionEnded
                }
                // Subscription registration is asynchronous. Retry until a message arrives.
                tasks.addTask {
                    for _ in 0..<50 {
                        try await client.publish(subject: subject, data: data)
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    throw TestError.messageTimedOut
                }
                defer { tasks.cancelAll() }
                try await tasks.next()
            }
        }
    }

    private func withConnectedClient(_ test: (NATSClient) async throws -> Void) async throws {
        let server = try await NATSTestServer(authorization: "authorization { user: app, password: app }")
        let logger = Logger(label: "NATSClientTests")
        let client = NATSClient(
            configuration: .init(url: server.url, auth: .userPassword(user: "app", password: "app")),
            logger: logger
        )
        let group = ServiceGroup(configuration: .init(services: [client], logger: logger))
        let runTask = Task { try await group.run() }
        defer { withExtendedLifetime(server) {} }

        do {
            for _ in 0..<50 {
                let state = await client.connectionState
                if state == .connected { break }
                if state == .failed { try await runTask.value }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard await client.connectionState == .connected else { throw TestError.connectionTimedOut }
            try await test(client)
        } catch {
            await group.triggerGracefulShutdown()
            runTask.cancel()
            _ = await runTask.result
            throw error
        }

        await group.triggerGracefulShutdown()
        try await runTask.value
        let state = await client.connectionState
        XCTAssertEqual(state, .closed)
    }

    private enum TestError: Error {
        case connectionTimedOut
        case subscriptionEnded
        case messageTimedOut
    }
}
