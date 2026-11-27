import Foundation
import NATSCore

// The C closure carries an integer ID as an opaque value, never a Swift object
// address. Late callbacks can safely look up an ID after it has been removed.
final class SubscriptionRegistry: @unchecked Sendable {
    static let shared = SubscriptionRegistry()
    private let lock = NSLock()
    private var nextID: UInt = 1
    private var continuations: [UInt: AsyncStream<NATSMessage>.Continuation] = [:]

    private init() {}

    func insert(_ continuation: AsyncStream<NATSMessage>.Continuation) -> UInt {
        lock.withLock {
            let id = nextID
            nextID += 1
            continuations[id] = continuation
            return id
        }
    }

    func contains(_ id: UInt) -> Bool {
        lock.withLock { continuations[id] != nil }
    }

    @discardableResult
    func remove(_ id: UInt) -> AsyncStream<NATSMessage>.Continuation? {
        lock.withLock { continuations.removeValue(forKey: id) }
    }

    func finish(_ id: UInt) {
        remove(id)?.finish()
    }

    static let receiveMessage: NATSMsgHandler = { _, _, pointer, context in
        guard let pointer else { return }
        let message = NATSMsgHandle(takingOwnershipOf: pointer)
        guard let context,
              let continuation = shared.continuation(for: UInt(bitPattern: context)),
              let subject = message.subject, let data = message.data else { return }
        continuation.yield(NATSMessage(subject: subject, data: data))
    }

    static let subscriptionCompleted: NATSSubscriptionCompletionHandler = { context in
        guard let context else { return }
        shared.finish(UInt(bitPattern: context))
    }

    private func continuation(for id: UInt) -> AsyncStream<NATSMessage>.Continuation? {
        lock.withLock { continuations[id] }
    }
}
