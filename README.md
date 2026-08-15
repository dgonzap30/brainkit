# BrainKit

BrainKit is the Swift package boundary for Lodestar personal-app integration. It keeps shared contracts, client behavior, provisioning, and interface primitives versioned independently from any one host app.

## Products

- **BrainKit** — versioned data-transfer objects, clients, and contract fixtures.
- **LodestarPluginKit** — app-side integration, provisioning, capability, and configuration components.
- **LodestarUI** — shared design tokens and reusable interface primitives for Lodestar apps.

## Requirements

- Swift tools 5.9+
- iOS 17+
- macOS 14+

## Add the package

```swift
dependencies: [
    .package(
        url: "https://github.com/dgonzap30/brainkit.git",
        from: "0.5.0"
    )
]
```

Then add only the product your target needs:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "BrainKit", package: "brainkit")
    ]
)
```

## Repository layout

- `Sources/BrainKit` — shared contracts and service clients
- `Sources/LodestarPluginKit` — host-app integration components
- `Sources/LodestarUI` — shared UI system
- `Contract/fixtures` — golden fixtures for cross-repository conformance
- `Tests` — product and contract tests

## Versioning

Package releases follow semantic versioning. Wire contracts use explicit schema versions such as `temper.v1` and `rundown.v1`; additive contract changes are documented in the [changelog](CHANGELOG.md).

## Development

```bash
swift test
```

## License

Apache 2.0. See [LICENSE](LICENSE).
