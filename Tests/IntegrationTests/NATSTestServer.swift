import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

actor NATSTestServer {
    static let user = "app"
    static let password = "app"

    enum Authorization: Sendable {
        case userPassword
        case anonymous
        case nkey(String)
    }

    nonisolated let clientURL: URL
    private let clientPort: Int
    private let authorization: Authorization
    private var broker: Broker?

    private init(broker: Broker, authorization: Authorization) {
        self.clientURL = broker.clientURL
        self.clientPort = broker.clientPort
        self.authorization = authorization
        self.broker = broker
    }

    static func withRunningServer(
        authorization: Authorization = .userPassword,
        _ body: (NATSTestServer) async throws -> Void
    ) async throws {
        let server = Self(broker: try await launch(authorization: authorization), authorization: authorization)
        do {
            try await body(server)
        } catch {
            try? await server.stop()
            throw error
        }
        try await server.stop()
    }

    func restart() async throws {
        try await stop()
        broker = try await Self.launch(port: clientPort, authorization: authorization)
    }

    func waitForSubscription(to subject: String) async throws {
        guard let broker else { throw IntegrationTestError.serverNotRunning }
        let url = broker.monitoringURL.appendingPathComponent("connz").appending(queryItems: [
            URLQueryItem(name: "subs", value: "1"),
        ])

        try await waitFor("register the NATS subscription to \(subject)") {
            let data = try await Self.fetch(url)
            let state = try JSONDecoder().decode(Connections.self, from: data)
            return state.connections.contains { $0.subscriptions?.contains(subject) == true }
        }
    }

    private static func launch(port: Int = -1, authorization: Authorization) async throws -> Broker {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("nats-test-\(UUID())")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        var ready = false
        defer {
            if !ready { try? fileManager.removeItem(at: directory) }
        }

        let logURL = directory.appendingPathComponent("nats-server.log")
        try Data().write(to: logURL)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }

        let environment = ProcessInfo.processInfo.environment
        let executable = environment["NATS_SERVER_PATH"] ?? environment["NATS_SERVER"] ?? "nats-server"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = [
            executable, "-a", "127.0.0.1", "-p", String(port), "-m", "-1",
            "--ports_file_dir", directory.path,
        ]
        switch authorization {
        case .userPassword:
            arguments += ["--user", user, "--pass", password]
        case .anonymous:
            break
        case .nkey(let publicIdentifier):
            let config = directory.appendingPathComponent("nats.conf")
            let encodedIdentifier = String(decoding: try JSONEncoder().encode(publicIdentifier), as: UTF8.self)
            try "authorization { users: [{ nkey: \(encodedIdentifier) }] }".write(
                to: config, atomically: true, encoding: .utf8
            )
            arguments += ["-c", config.path]
        }
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
            let broker = try await waitForBroker(process, directory: directory, requestedPort: port)
            ready = true
            return broker
        } catch {
            try? await stopProcess(process)
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw IntegrationTestError.serverStartupFailed(String(describing: error), log)
        }
    }

    private static func waitForBroker(_ process: Process, directory: URL, requestedPort: Int) async throws -> Broker {
        let fileManager = FileManager.default

        return try await pollFor("start the NATS test server") {
            guard process.isRunning else {
                throw IntegrationTestError.serverExited(process.terminationStatus)
            }
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let portsFile = files.first(where: { $0.pathExtension == "ports" }),
                let data = try? Data(contentsOf: portsFile),
                let ports = try? JSONDecoder().decode(Ports.self, from: data),
                let clientURL = ports.nats.first,
                let clientPort = clientURL.port,
                let monitoringURL = ports.monitoring.first,
                (try? await fetch(monitoringURL.appendingPathComponent("healthz"))) != nil
            else { return nil }

            guard requestedPort < 0 || clientPort == requestedPort else {
                throw IntegrationTestError.unexpectedClientPort(clientPort, expected: requestedPort)
            }
            return Broker(
                process: process, directory: directory, clientURL: clientURL,
                clientPort: clientPort, monitoringURL: monitoringURL
            )
        }
    }

    func stop() async throws {
        guard let broker else { return }
        try await Self.stopProcess(broker.process)
        self.broker = nil
        try? FileManager.default.removeItem(at: broker.directory)
    }

    private static func stopProcess(_ process: Process) async throws {
        // Cleanup also has to finish when Swift Testing cancels a test.
        try await Task {
            guard process.isRunning else { return }
            process.terminate()

            do {
                try await waitFor("stop the NATS test server", timeout: .seconds(2)) { !process.isRunning }
            } catch {
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                try await waitFor("kill the NATS test server", timeout: .seconds(1)) { !process.isRunning }
            }
        }.value
    }

    private static func fetch(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw IntegrationTestError.monitorRequestFailed(url)
        }
        return data
    }

    private struct Ports: Decodable {
        let nats: [URL]
        let monitoring: [URL]
    }

    private struct Broker {
        let process: Process
        let directory: URL
        let clientURL: URL
        let clientPort: Int
        let monitoringURL: URL
    }

    private struct Connections: Decodable {
        let connections: [Connection]

        struct Connection: Decodable {
            let subscriptions: [String]?

            enum CodingKeys: String, CodingKey {
                case subscriptions = "subscriptions_list"
            }
        }
    }
}

func waitFor(
    _ description: String,
    timeout: Duration = .seconds(5),
    condition: () async throws -> Bool
) async throws {
    let _: Void = try await pollFor(description, timeout: timeout) {
        try await condition() ? () : nil
    }
}

private func pollFor<Value>(
    _ description: String,
    timeout: Duration = .seconds(5),
    probe: () async throws -> Value?
) async throws -> Value {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if let value = try await probe() { return value }
        try await clock.sleep(for: .milliseconds(20))
    }
    throw IntegrationTestError.timedOut(description)
}

enum IntegrationTestError: Error, CustomStringConvertible {
    case timedOut(String)
    case serverExited(Int32)
    case serverStartupFailed(String, String)
    case serverNotRunning
    case unexpectedClientPort(Int, expected: Int)
    case monitorRequestFailed(URL)
    case clientConnectionFailed

    var description: String {
        switch self {
        case .timedOut(let operation):
            return "Timed out waiting to \(operation)."
        case .serverExited(let status):
            return "nats-server exited with status \(status)."
        case .serverStartupFailed(let error, let log):
            return "Could not start nats-server. Put it on PATH or set NATS_SERVER_PATH. \(error)\n\(log)"
        case .serverNotRunning:
            return "The NATS test server is not running."
        case .unexpectedClientPort(let port, let expected):
            return "The NATS test server bound client port \(port), expected \(expected)."
        case .monitorRequestFailed(let url):
            return "NATS test server monitoring request failed for \(url)."
        case .clientConnectionFailed:
            return "The NATS client failed to connect to the test server."
        }
    }
}
