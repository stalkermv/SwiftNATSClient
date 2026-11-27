#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd -P)
revision=$(git -C "$repository" rev-parse HEAD)
consumer_directory=$(mktemp -d)
trap 'rm -rf "$consumer_directory"' EXIT
consumer_repository="$consumer_directory/SwiftNATSClient.git"
# SwiftPM expects a repository layout it can clone, including when invoked from a linked worktree.
git clone --quiet --bare "$repository" "$consumer_repository"
mkdir "$consumer_directory/Sources"

cat > "$consumer_directory/Package.swift" <<'SWIFT'
// swift-tools-version: 6.4
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
guard let repository = environment["SWIFTNATS_SMOKE_REPOSITORY"],
      let revision = environment["SWIFTNATS_SMOKE_REVISION"] else {
    fatalError("Run this package through Scripts/smoke-consumer.sh")
}
let directoryName = URL(fileURLWithPath: repository).lastPathComponent
let packageIdentity = directoryName.hasSuffix(".git") ? String(directoryName.dropLast(4)) : directoryName

let package = Package(
    name: "NATSConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: repository, revision: revision)],
    targets: [
        .executableTarget(
            name: "NATSConsumer",
            dependencies: [.product(name: "NATS", package: packageIdentity)],
            path: "Sources"
        )
    ]
)
SWIFT

cat > "$consumer_directory/Sources/main.swift" <<'SWIFT'
import NATS

let client = NATSClient(configuration: .init())
let state = await client.connectionState
precondition(state == .idle)
print("NATS consumer linked and initialized successfully")
SWIFT

SWIFTNATS_SMOKE_REPOSITORY="$consumer_repository" SWIFTNATS_SMOKE_REVISION="$revision" \
    swift run --package-path "$consumer_directory" --configuration release NATSConsumer
