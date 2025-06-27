import Foundation // Needed for NSLock, Date, usleep
import Testing
@testable import NATSCore

struct NATSCoreLowLevelTests {
    @Test
    func testConnectionLifecycle() throws {
        let opts = NATSOptionsHandle()
        opts.setURL("nats://localhost:4222")
        let conn = NATSConnectionHandle()
        try conn.connect(options: opts)
        #expect(conn.isConnected)
        conn.close()
        #expect(!conn.isConnected)
    }

    @Test
    func testPublishAndSubscribe() throws {
        let opts = NATSOptionsHandle()
        opts.setURL("nats://localhost:4222")
        let conn = NATSConnectionHandle()
        try conn.connect(options: opts)
        let subject = "test.natscore.lowlevel"
        var received: (String, Data)? = nil
        let handler: @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, _, msgPtr, closure in
            guard let msgPtr = msgPtr, let closure = closure else { return }
            let box = Unmanaged<MutableBox<(String, Data)?>>.fromOpaque(closure).takeUnretainedValue()
            let msg = NATSMsgHandle(ptr: msgPtr)
            if let subject = msg.subject, let data = msg.data {
                box.value = (subject, data)
            }
        }
        let box = MutableBox<(String, Data)?>(nil)
        let unmanaged = Unmanaged.passUnretained(box).toOpaque()
        let sub = try conn.subscribe(subject: subject, callback: handler, closure: unmanaged)
        let payload = "hello lowlevel".data(using: .utf8)!
        try conn.publish(subject: subject, data: payload)
        // Wait for message (not ideal, but works for low-level test)
        let deadline = Date().addingTimeInterval(2)
        while box.value == nil && Date() < deadline { usleep(10_000) }
        #expect(box.value != nil)
        if let (recvSubject, recvData) = box.value {
            #expect(recvSubject == subject)
            #expect(String(data: recvData, encoding: .utf8) == "hello lowlevel")
        }
        try sub.unsubscribe()
        conn.close()
    }

//    @Test
//    func testQueueSubscribeLoadBalancing() throws {
//        let opts = NATSOptionsHandle()
//        opts.setURL("nats://localhost:4222")
//        let conn = NATSConnectionHandle()
//        try conn.connect(options: opts)
//        let subject = "test.natscore.queue"
//        let queue = "workers"
//        let messageCount = 10
//        let subscriberCount = 3
//        var deliveries = Array(repeating: 0, count: subscriberCount)
//        var receivedTotal = 0
//        let lock = NSLock()
//        var subs: [NATSSubscriptionHandle] = []
//        var boxes: [MutableBox<Int>] = []
//        for i in 0..<subscriberCount {
//            let box = MutableBox<Int>(i)
//            boxes.append(box)
//            let handler: @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, _, _, closure in
//                guard let closure = closure else { return }
//                let box = Unmanaged<MutableBox<Int>>.fromOpaque(closure).takeUnretainedValue()
//                lock.lock()
//                deliveries[box.value] += 1
//                receivedTotal += 1
//                lock.unlock()
//            }
//            let unmanaged = Unmanaged.passUnretained(box).toOpaque()
//            let sub = try conn.queueSubscribe(subject: subject, queue: queue, callback: handler, closure: unmanaged)
//            subs.append(sub)
//        }
//        // Publish messages
//        let payload = "queue test".data(using: .utf8)!
//        for _ in 0..<messageCount {
//            try conn.publish(subject: subject, data: payload)
//        }
//        // Wait for all messages to be delivered
//        let deadline = Date().addingTimeInterval(2)
//        while receivedTotal < messageCount && Date() < deadline { usleep(10_000) }
//        #expect(receivedTotal == messageCount)
//        // Each message should be delivered to only one subscriber
//        let minDeliveries = deliveries.min() ?? 0
//        let maxDeliveries = deliveries.max() ?? 0
//        #expect(maxDeliveries - minDeliveries <= 1) // Load should be balanced
//        #expect(deliveries.reduce(0, +) == messageCount)
//        for sub in subs { try? sub.unsubscribe() }
//        conn.close()
//    }
}

/// Helper for passing mutable state into C callback
final class MutableBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
