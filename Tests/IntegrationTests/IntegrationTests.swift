import Testing
import Foundation
import ServiceLifecycle
import Logging
@testable import NATS

enum TestError: Error {
    case connectionFailed
}

let testLogger = Logger(label: "NATSClientTests")

func startServer() throws -> Process {
    let process = Process()
    let path = ProcessInfo.processInfo.environment["NATS_SERVER"] ?? "/usr/local/bin/nats-server"
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["-p", "4222"]
    process.standardOutput = nil
    process.standardError = nil
    try process.run()
    Thread.sleep(forTimeInterval: 0.5)
    return process
}

func waitForConnection(_ client: NATSClient) async throws {
    for _ in 0..<50 {
        if await client.connectionState == .connected {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw TestError.connectionFailed
}

@Test
func testNATSClientConnectAndShutdown() async throws {
    let server = try startServer()
    defer {
        server.terminate()
        try? server.waitUntilExit()
    }

    let client = NATSClient(configuration: .init(), logger: testLogger)
    let group = ServiceGroup(configuration: .init(services: [client], logger: testLogger))
    let runTask = Task { try await group.run() }
    try await waitForConnection(client)
    await group.triggerGracefulShutdown()
    try await runTask.value
}

@Test
func testNATSClientPublishSubscribe() async throws {
    let server = try startServer()
    defer {
        server.terminate()
        try? server.waitUntilExit()
    }

    let client = NATSClient(configuration: .init(), logger: testLogger)
    let group = ServiceGroup(configuration: .init(services: [client], logger: testLogger))
    let runTask = Task { try await group.run() }
    try await waitForConnection(client)

    let subject = "test.natsclient.pubsub"
    let data = "hello highlevel".data(using: .utf8)!
    let stream = client.subscribe(subject: subject)
    var received = false
    let subTask = Task {
        for await msg in stream {
            #expect(msg.subject == subject)
            #expect(msg.data == data)
            received = true
            break
        }
    }
    try await client.publish(subject: subject, data: data)
    while !received { await Task.yield() }
    subTask.cancel()

    await group.triggerGracefulShutdown()
    try await runTask.value
}

@Test
func testReconnectAfterServerRestart() async throws {
    var server = try startServer()
    defer {
        server.terminate()
        try? server.waitUntilExit()
    }

    let config = NATSClientConfiguration(reconnect: true, maxReconnects: 10, reconnectWait: 0.5)
    let client = NATSClient(configuration: config, logger: testLogger)
    let group = ServiceGroup(configuration: .init(services: [client], logger: testLogger))
    let runTask = Task { try await group.run() }
    try await waitForConnection(client)

    server.terminate()
    try? server.waitUntilExit()

    server = try startServer()

    for _ in 0..<100 {
        if await client.connectionState == .connected {
            break
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(await client.connectionState == .connected)

    await group.triggerGracefulShutdown()
    try await runTask.value
}
