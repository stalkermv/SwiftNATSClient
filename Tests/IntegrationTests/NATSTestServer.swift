import Foundation

final class NATSTestServer {
    let url: String

    private let process: Process

    init(authorization: String = "", port: Int = -1) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let process = Process()
        self.process = process

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            var arguments = [
                "nats-server", "-a", "127.0.0.1", "-p", String(port), "--ports_file_dir", directory.path
            ]
            if !authorization.isEmpty {
                let configuration = directory.appendingPathComponent("nats.conf")
                try authorization.write(to: configuration, atomically: true, encoding: .utf8)
                arguments += ["-c", configuration.path]
            }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            process.terminationHandler = { _ in
                try? FileManager.default.removeItem(at: directory)
            }
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        do {
            self.url = try await Self.waitForURL(process, in: directory)
        } catch {
            Self.terminate(process)
            throw error
        }
    }

    deinit {
        Self.terminate(process)
    }

    private static func waitForURL(_ process: Process, in directory: URL) async throws -> String {
        let portsFile = directory.appendingPathComponent("nats-server_\(process.processIdentifier).ports")
        for _ in 0..<100 {
            guard process.isRunning else {
                throw ServerError.exited(process.terminationStatus)
            }
            if let data = try? Data(contentsOf: portsFile),
               let ports = try? JSONDecoder().decode(Ports.self, from: data),
               let url = ports.nats.first {
                return url
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ServerError.startupTimedOut
    }

    func stop() async throws {
        Self.terminate(process)
        for _ in 0..<100 {
            if !process.isRunning { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ServerError.shutdownTimedOut
    }

    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }

    private struct Ports: Decodable {
        let nats: [String]
    }

    private enum ServerError: Error {
        case exited(Int32)
        case startupTimedOut
        case shutdownTimedOut
    }
}
