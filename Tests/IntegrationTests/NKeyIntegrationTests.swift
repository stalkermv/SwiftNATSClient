import NATS
import NATSCore
import Testing

struct NKeyIntegrationTests {
    // Public test vector from RFC 8032, section 7.1, encoded in NKey format.
    private let seed = "SUAJ2YNRTXX72WTAXKCEV5ES5QWMIRCJYVUXWMTJDFYDXLADDSXH6YALCA"
    private let publicKey = "UDLVVGABQKYQVN6VJP7NHSLEA45A5YLS6PNKMIZFV4BBU2HXA5IRUVAL"

    @Test
    func testUserSeedAuthenticatesAndSurvivesReconnect() async throws {
        try await NATSTestServer.withRunningServer(authorization: .nkey(publicKey)) { server in
            let url = server.clientURL.absoluteString
            let anonymousOptions = NATSOptionsHandle()
            anonymousOptions.setURL(url)
            #expect(throws: NATSError.self) {
                try NATSConnectionHandle().connect(options: anonymousOptions)
            }

            let connection = NATSConnectionHandle()
            do {
                let options = NATSOptionsHandle()
                options.setURL(url)
                try options.setNKey(seed: seed)
                try connection.connect(options: options)
            }
            #expect(connection.isConnected)

            try await server.stop()
            try await waitFor("observe NKey connection loss") { !connection.isConnected }
            try await server.restart()
            try await waitFor("reconnect with the retained NKey seed") { connection.isConnected }
        }
    }

    @Test
    func testPublicClientAuthenticatesWithUserSeed() async throws {
        try await NATSTestServer.withRunningServer(authorization: .nkey(publicKey)) { server in
            let url = server.clientURL.absoluteString
            let client = NATSClient(configuration: .init(url: url, auth: .nkey(seed: seed)))

            try await withThrowingTaskGroup(of: Void.self) { tasks in
                tasks.addTask { try await client.run() }
                try await waitFor("authenticate the NATS client using its NKey seed") {
                    let state = await client.connectionState
                    if state == .failed { throw IntegrationTestError.clientConnectionFailed }
                    return state == .connected
                }
                await client.shutdown()
                try await tasks.waitForAll()
            }
            #expect(await client.connectionState == .closed)
        }
    }

    @Test
    func testInvalidSeedFailsBeforeConnectingToAnonymousServer() async throws {
        try await NATSTestServer.withRunningServer(authorization: .anonymous) { server in
            let url = server.clientURL.absoluteString
            let corruptedSeed = String(seed.dropLast()) + "E"
            let accountSeed = "SAAJ2YNRTXX72WTAXKCEV5ES5QWMIRCJYVUXWMTJDFYDXLADDSXH6YHY3Q"

            for invalidSeed in ["", corruptedSeed, accountSeed, seed + "\0suffix"] {
                let client = NATSClient(configuration: .init(url: url, auth: .nkey(seed: invalidSeed)))

                await #expect {
                    try await withThrowingTaskGroup(of: Void.self) { tasks in
                        tasks.addTask { try await client.run() }
                        try await waitFor("resolve invalid NKey authorization") {
                            let state = await client.connectionState
                            return state == .failed || state == .connected
                        }
                        if await client.connectionState == .connected { await client.shutdown() }
                        try await tasks.waitForAll()
                    }
                } throws: { error in
                    guard case NATSError.connectionFailed(let reason) = error else { return false }
                    return reason == "Invalid NKey user seed"
                }
                #expect(await client.connectionState == .failed)
            }
        }
    }
}
