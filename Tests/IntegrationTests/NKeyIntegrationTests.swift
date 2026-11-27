import Foundation
import NATS
import NATSCore
import XCTest

final class NKeyIntegrationTests: XCTestCase {
    // Public test vector from RFC 8032, section 7.1, encoded in NKey format.
    private let seed = "SUAJ2YNRTXX72WTAXKCEV5ES5QWMIRCJYVUXWMTJDFYDXLADDSXH6YALCA"
    private let publicKey = "UDLVVGABQKYQVN6VJP7NHSLEA45A5YLS6PNKMIZFV4BBU2HXA5IRUVAL"

    func testUserSeedAuthenticatesAndSurvivesReconnect() async throws {
        let authorization = "authorization { users: [{ nkey: \(publicKey) }] }"
        let server = try await NATSTestServer(authorization: authorization)
        let url = server.url
        let port = try XCTUnwrap(URL(string: url)?.port)

        let anonymousOptions = NATSOptionsHandle()
        anonymousOptions.setURL(url)
        XCTAssertThrowsError(try NATSConnectionHandle().connect(options: anonymousOptions))

        let connection = NATSConnectionHandle()
        do {
            let options = NATSOptionsHandle()
            options.setURL(url)
            try options.setNKey(seed: seed)
            try connection.connect(options: options)
        }
        XCTAssertTrue(connection.isConnected)

        try await server.stop()
        for _ in 0..<100 where connection.isConnected {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(connection.isConnected)

        let restartedServer = try await NATSTestServer(authorization: authorization, port: port)
        defer { withExtendedLifetime(restartedServer) {} }
        for _ in 0..<100 where !connection.isConnected {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(connection.isConnected)
    }

    func testInvalidSeedFailsBeforeConnectingToAnonymousServer() async throws {
        let server = try await NATSTestServer()
        defer { withExtendedLifetime(server) {} }
        let corruptedSeed = String(seed.dropLast()) + "E"
        let accountSeed = "SAAJ2YNRTXX72WTAXKCEV5ES5QWMIRCJYVUXWMTJDFYDXLADDSXH6YHY3Q"

        for invalidSeed in ["", corruptedSeed, accountSeed, seed + "\0suffix"] {
            let client = NATSClient(configuration: .init(url: server.url, auth: .nkey(seed: invalidSeed)))
            let task = Task { try await client.run() }
            defer { task.cancel() }
            for _ in 0..<50 {
                let state = await client.connectionState
                if state == .failed || state == .connected { break }
                try await Task.sleep(for: .milliseconds(50))
            }

            let state = await client.connectionState
            guard state == .failed else {
                await client.shutdown()
                XCTFail("Invalid seed must fail before connecting")
                continue
            }
            do {
                try await task.value
                XCTFail("Invalid seed must propagate an error")
            } catch NATSError.connectionFailed(let message) {
                XCTAssertEqual(message, "Invalid NKey user seed")
            }
        }
    }
}
