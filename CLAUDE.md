# CLAUDE.md — AtlasCommonSwift

Shared Swift SPM package providing the cross-product contract layer for all atlas iOS apps. Current version: v0.2.6.

## Build & Test

```bash
swift build                    # Build all targets
swift test                     # Run tests (AtlasCommonSwiftTests + OTelTests)
```

Xcode: open `Package.swift`, select any iOS simulator or macOS target to build/test.

## Architecture — Three Library Products

```
AtlasCommonSwift          ← zero dependencies, core types
AtlasCommonSwiftOTel      ← depends on opentelemetry-swift, adds tracing
AtlasCommonSwiftAnalytics ← depends on posthog-ios, adds analytics + flags
```

Consumers pick only what they need. All three are in one SPM package for atomic versioning.

### AtlasCommonSwift (Core)

| File | Type | Exports |
|------|------|---------|
| `Types/ApiResponse.swift` | `struct` | `ApiResponse<T: Decodable>` — matches Go `{code, message, data}` envelope |
| `Types/ApiError.swift` | `enum` | `.business(code, message)`, `.unauthorized`, `.network`, `.decoding`, `.unknown` |
| `HTTP/HTTPClient.swift` | `actor` | Generic async HTTP client, auto-unwraps `ApiResponse`, injects auth token |
| `HTTP/HTTPMethod.swift` | `enum` | `.get`, `.post`, `.put`, `.delete` |
| `Keychain/KeychainHelper.swift` | `enum` (namespace) | `saveString`, `loadString`, `delete` |
| `Logger/Logger.swift` | `enum` (namespace) | `Log.info/error/debug/warning(_, category:)` wrapping `os.Logger` |

### AtlasCommonSwiftOTel

| File | Type | Exports |
|------|------|---------|
| `OTelConfig.swift` | `struct: Sendable` | Config value object (endpoint, headers, serviceName) |
| `OTelSetup.swift` | `enum` (namespace) | `configure(_:)`, `tracer(name:)` — singleton OTel SDK bootstrap |
| `InstrumentedHTTPClient.swift` | `actor` | Wraps `HTTPClient` + auto-creates spans + injects `traceparent` header |
| `LogUploader.swift` | `enum` (namespace) | `configure(_:)`, `upload(entries:)` — batch OSLog → Loki via OTLP |

### AtlasCommonSwiftAnalytics

| File | Type | Exports |
|------|------|---------|
| `Analytics.swift` | `enum` (namespace) | `configure`, `capture`, `screen`, `identify`, `reset`, `isFeatureEnabled`, `reloadFeatureFlags` |

## Key Design Decisions

- **`HTTPClient` is an `actor`** — mutable token state, concurrent requests from any isolation domain
- **`InstrumentedHTTPClient` is an `actor`** — wraps HTTPClient, same reasoning
- **Consumers' API layer should be `final class: Sendable`** (not actor) — it only holds `let client`, no mutable state. See ios-app-blueprint.md §6 type rules.
- **`ApiResponse<T>` auto-unwrapping** — callers get `T` directly on success, `ApiError` on failure. No manual envelope handling.
- **Swift 6 strict concurrency** — `swiftLanguageModes: [.v6]`. All public types must be `Sendable`.
- **`nonisolated init(from:)`** on consumer Decodable types — required because `Decodable.init(from:)` is a nonisolated protocol requirement. Consumers must write explicit nonisolated decoders if their type is actor-isolated.

## Versioning & Release

```bash
git tag v0.2.7
git push origin v0.2.7
```

Consumers (Snag iOS, future apps) resolve by tag in Xcode SPM. Bump tag = new release.

**Breaking change rules:**
- Adding new public API = minor bump (0.2.x → 0.3.0)
- Changing existing public API signature = must bump + update all consumers
- Internal-only changes = patch bump (0.2.6 → 0.2.7)

## Consumers

| App | Version | Products Used |
|-----|---------|---------------|
| Snag iOS | v0.2.6 | All three |

## Testing Requirements

Per `architecture/standards/testing.md`: every exported public function must have a test. Current gaps:
- `AtlasCommonSwiftAnalytics` — no test target yet (PostHog SDK makes unit testing hard; consider protocol mock)

## Common Tasks

### Adding a new public type/function

1. Add to appropriate `Sources/AtlasCommonSwift*/` directory
2. Ensure it's `Sendable` (Swift 6 requirement)
3. Add test in corresponding `Tests/` target
4. `swift build && swift test`
5. Tag and push

### Updating dependencies

Edit `Package.swift` dependency versions, then `swift package resolve`. Test on both macOS (swift test) and iOS simulator (Xcode).
