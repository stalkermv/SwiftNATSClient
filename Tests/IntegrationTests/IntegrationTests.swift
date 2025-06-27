import Testing
import Foundation
import ServiceLifecycle
import Logging
@testable import NATS

final class IntegrationTests {
    static let logger = Logger(label: "NATSClientTests")
    
    let client: NATSClient
    let group: ServiceGroup
    var runTask: Task<Void, Error>?
    
    init() async throws {
        self.client = NATSClient(
            configuration: .init(auth: .userPassword(user: "app", password: "app")),
            logger: Self.logger
        )
        
        self.group = ServiceGroup(configuration: .init(services: [client], logger: Self.logger))
        self.runTask = Task { try await self.group.run() }

        for _ in 0..<50 {
            if await client.connectionState == .connected {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    @Test
    func testNATSClientConnectAndShutdown() async throws {
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            
            if let runTask = self.runTask {
                taskGroup.addTask {
                    try await runTask.value
                }
            }
            // Test logic (just connect, wait, shutdown)
            taskGroup.addTask {
                try await Task.sleep(for: .seconds(1))
                await self.group.triggerGracefulShutdown()
            }
            // Wait for all
            try await taskGroup.next()
            try await taskGroup.next()
        }
    }

    @Test
    func testNATSClientPublishSubscribe() async throws {
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in

            if let runTask = self.runTask {
                taskGroup.addTask {
                    try await runTask.value
                }
            }
            
            // Publisher/Subscriber logic
            taskGroup.addTask {
                let subject = "test.natsclient.pubsub", data = "hello highlevel".data(using: .utf8)!
                let stream = self.client.subscribe(subject: subject)
                var received = false
                let subTask = Task {
                    for await msg in stream {
                        print("Received message on \(msg.subject): \(String(data: msg.data, encoding: .utf8) ?? "nil")")
                        #expect(msg.subject == subject)
                        #expect(msg.data == data)
                        received = true
                        break
                    }
                }
                try await self.client.publish(subject: subject, data: data)
                // Чекаємо завершення підписки (отримання повідомлення)
                while !received {
                    await Task.yield()
                }
                subTask.cancel()
            }
            try await taskGroup.next()
            await self.group.triggerGracefulShutdown()
        }
    }
}
