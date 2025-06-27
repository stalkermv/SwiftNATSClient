# Swift NATS Client

The Swift NATS Client library provides a modern, idiomatic, async/await-based API for [NATS](https://nats.io) messaging, inspired by swift-kafka-client and leveraging [Swift's concurrency features](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html). This package wraps the native [CNATS](https://github.com/nats-io/nats.c) C library.

## Adding SwiftNATSClient as a Dependency

To use the `NATS` library in a SwiftPM project, add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/YOUR_GITHUB_USERNAME/SwiftNATSClient", branch: "main")
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

## CNATS

This package depends on [the `nats.c` library](https://github.com/nats-io/nats.c), included as a submodule.

### Dependencies

`nats.c` depends on `openssl`, so `libssl-dev` must be present at build time. On macOS, you can install it via Homebrew:

```bash
brew install openssl@3
```

## Development Setup

You can use Docker or run tests locally. For Linux CI, see `.github/workflows/`.

## License

Licensed under Apache License v2.0. See [LICENSE](LICENSE).
