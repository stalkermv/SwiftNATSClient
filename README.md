# ⚠️ Disclaimer

**This project is in an early stage of development and is not ready for production use. APIs and behavior may change without notice. Use at your own risk.**

# Swift NATS Client

The Swift NATS Client library provides a modern, idiomatic, async/await-based API for [NATS](https://nats.io) messaging, inspired by swift-kafka-client and leveraging [Swift's concurrency features](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html). This package wraps the native [CNATS](https://github.com/nats-io/nats.c) C library.

## Adding SwiftNATSClient as a Dependency

To use the `NATS` library in a SwiftPM project, add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/stalkermv/SwiftNATSClient", branch: "main")
```

Include `"NATS"` as a dependency for your executable target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "NATS", package: "SwiftNATSClient"),
]),
```

Finally, add `import NATS` to your source code.

## Usage

`NATSClient` should be used within a [`Swift Service Lifecycle`](https://github.com/swift-server/swift-service-lifecycle)
[`ServiceGroup`](https://swiftpackageindex.com/swift-server/swift-service-lifecycle/main/documentation/servicelifecycle/servicegroup) for proper startup and shutdown handling. `NATSClient` implements the [`Service`](https://swiftpackageindex.com/swift-server/swift-service-lifecycle/main/documentation/servicelifecycle/service) protocol.

### Connect, Publish, Subscribe

```swift
import NATS
import ServiceLifecycle
import Logging

let logger = Logger(label: "NATSClientDemo")
let client = NATSClient(
    configuration: .init(auth: .userPassword(user: "app", password: "app")),
    logger: logger
)
let group = ServiceGroup(configuration: .init(services: [client], logger: logger))

await withThrowingTaskGroup(of: Void.self) { group in
    // Run ServiceGroup
    group.addTask {
        try await group.run()
    }
    // Publisher/Subscriber logic
    group.addTask {
        let subject = "demo.subject"
        let data = "hello NATS".data(using: .utf8)!
        let stream = client.subscribe(subject: subject)
        let subTask = Task {
            for await msg in stream {
                print("Received message on \(msg.subject): \(String(data: msg.data, encoding: .utf8) ?? "nil")")
                break
            }
        }
        try await client.publish(subject: subject, data: data)
        subTask.cancel()
    }
    try await group.next()
    try await group.next()
    await group.triggerGracefulShutdown()
}
```

### Authentication

NATS supports several authentication mechanisms. You can configure them via `NATSClientConfiguration`:

```swift
// Username/Password
let config = NATSClientConfiguration(auth: .userPassword(user: "app", password: "app"))

// Token
let config = NATSClientConfiguration(auth: .token("mytoken"))

// NKey/JWT credentials file
let config = NATSClientConfiguration(auth: .jwtCredsFile(file: "/path/to/user.creds"))
```

For a standalone NKey user seed, use `.nkey(seed:)`.

## CNATS

This package depends on [the `nats.c` library](https://github.com/nats-io/nats.c), included as a submodule.

### Dependencies

The build uses OpenSSL 3 and discovers it through `pkg-config`.

```bash
# Debian and Ubuntu
sudo apt-get install libssl-dev pkg-config

# macOS
brew install openssl@3 pkgconf
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
```

## Development Setup

Use the Swift toolchain pinned in `.swift-version`. If you use Swiftly, install it with `swiftly install 6.4.1`.

```bash
git submodule update --init --recursive
swift test
swift test -c release
```

The integration tests launch their own broker. They look for `nats-server` on `PATH` or use the binary specified by `NATS_SERVER_PATH`. CI uses NATS Server 2.11.8. On macOS, `brew install nats-server` provides a broker for local testing.

Run `bash Scripts/smoke-consumer.sh` to build and run a temporary SwiftPM executable that imports `NATS` from the current Git revision.

## License

Licensed under Apache License v2.0. See [LICENSE](LICENSE).
