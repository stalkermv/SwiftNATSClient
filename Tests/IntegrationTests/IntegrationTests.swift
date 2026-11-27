import Foundation
import Testing
import NATS
import NATSCore
import ServiceLifecycle
import Logging

private enum TestError: Error {
    case serverExited(Int32)
    case serverStartupTimedOut
    case connectionFailed
    case messageTimedOut
    case connectionDidNotClose
}

private struct TestNATSServer {
    private struct Ports: Decodable {
        let nats: [URL]
    }

    private let process: Process
    private let directory: URL
    let port: Int
    var url: String { "nats://127.0.0.1:\(port)" }

    static func start(port: Int = -1) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        let process = Process()
        var ready = false
        defer {
            if !ready {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                try? FileManager.default.removeItem(at: directory)
            }
        }

        let path = ProcessInfo.processInfo.environment["NATS_SERVER"] ?? "/usr/local/bin/nats-server"
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-a", "127.0.0.1", "-p", String(port), "--ports_file_dir", directory.path]
        try process.run()

        for _ in 0..<100 {
            guard process.isRunning else { throw TestError.serverExited(process.terminationStatus) }

            // Only this process writes a ports file in this directory, after binding its listener.
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            if let file = files.first(where: { $0.pathExtension == "ports" }),
               let data = try? Data(contentsOf: file),
               let ports = try? JSONDecoder().decode(Ports.self, from: data),
               let listenPort = ports.nats.first?.port {
                ready = true
                return Self(process: process, directory: directory, port: listenPort)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TestError.serverStartupTimedOut
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

private func waitForConnection(_ client: NATSClient) async throws {
    for _ in 0..<50 {
        switch await client.connectionState {
        case .connected: return
        case .failed, .closed: throw TestError.connectionFailed
        default: try await Task.sleep(for: .milliseconds(50))
        }
    }
    throw TestError.connectionFailed
}

private func withConnectedClient(
    configuration: NATSClientConfiguration,
    operation: (NATSClient) async throws -> Void
) async throws {
    let logger = Logger(label: "NATSClientTests")
    let client = NATSClient(configuration: configuration, logger: logger)
    let group = ServiceGroup(configuration: .init(services: [client], logger: logger))

    try await withThrowingTaskGroup(of: Void.self) { tasks in
        tasks.addTask { try await group.run() }
        do {
            try await waitForConnection(client)
            try await operation(client)
        } catch {
            await group.triggerGracefulShutdown()
            throw error
        }
        await group.triggerGracefulShutdown()
        try await tasks.waitForAll()
    }
    #expect(await client.connectionState == .closed)
}

private func expectRoundTrip(on client: NATSClient, subject: String) async throws {
    let payload = Data("hello NATS".utf8)
    let stream = client.subscribe(subject: subject)

    try await withThrowingTaskGroup(of: NATSMessage?.self) { tasks in
        tasks.addTask {
            for await message in stream { return message }
            return nil
        }
        tasks.addTask {
            // Subscription registration and server reconnect happen asynchronously.
            for _ in 0..<100 {
                try await client.publish(subject: subject, data: payload)
                try await Task.sleep(for: .milliseconds(50))
            }
            throw TestError.messageTimedOut
        }
        defer { tasks.cancelAll() }

        let result = try await tasks.next() ?? nil
        let message = try #require(result)
        #expect(message.subject == subject)
        #expect(message.data == payload)
    }
}

@Test
func testNATSClientConnectAndShutdown() async throws {
    let server = try await TestNATSServer.start()
    defer { server.stop() }

    try await withConnectedClient(configuration: .init(url: server.url)) { _ in }
}

@Test
func testNATSClientPublishSubscribe() async throws {
    let server = try await TestNATSServer.start()
    defer { server.stop() }

    try await withConnectedClient(configuration: .init(url: server.url)) { client in
        try await expectRoundTrip(on: client, subject: "test.natsclient.pubsub")
    }
}

@Test
func testReconnectAfterServerRestart() async throws {
    let server = try await TestNATSServer.start()
    defer { server.stop() }

    let configuration = NATSClientConfiguration(url: server.url, reconnect: true, reconnectWait: 0.25)
    try await withConnectedClient(configuration: configuration) { client in
        server.stop()
        let replacement = try await TestNATSServer.start(port: server.port)
        defer { replacement.stop() }

        try await expectRoundTrip(on: client, subject: "test.natsclient.reconnect")
    }
}

@Test
func testReconnectDisabledAfterServerRestart() async throws {
    let server = try await TestNATSServer.start()
    defer { server.stop() }

    let configuration = NATSClientConfiguration(url: server.url, reconnect: false)
    try await withConnectedClient(configuration: configuration) { client in
        server.stop()
        let replacement = try await TestNATSServer.start(port: server.port)
        defer { replacement.stop() }

        for _ in 0..<50 {
            do {
                // A reconnecting native connection buffers publishes; a closed one rejects them.
                try await client.publish(subject: "test.natsclient.closed", data: Data())
            } catch NATSError.publishFailed(_) {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TestError.connectionDidNotClose
    }
}
