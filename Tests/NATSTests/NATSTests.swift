import Testing
import Foundation
import NATSCore
import NATS

struct NATSTests {
    @Test
    func reportsInvalidReconnectWaitWhenClientStarts() async {
        let client = NATSClient(configuration: .init(reconnectWait: .nan))

        await #expect {
            try await client.run()
        } throws: { error in
            guard case NATSError.connectionFailed(let reason) = error else { return false }
            return reason.hasPrefix("Reconnect wait")
        }
        #expect(await client.connectionState == .failed)
    }

    @Test(arguments: [-1.0, -0.0001, Double.nan, Double.infinity, -Double.infinity, Double(Int64.max) / 1_000])
    func rejectsInvalidReconnectWait(seconds: TimeInterval) {
        #expect(throws: NATSError.self) {
            try NATSOptionsHandle().setReconnectWait(seconds)
        }
    }

    @Test(arguments: [0.0, 0.0001, 0.5, 2.0])
    func acceptsValidReconnectWait(seconds: TimeInterval) throws {
        try NATSOptionsHandle().setReconnectWait(seconds)
    }
}
