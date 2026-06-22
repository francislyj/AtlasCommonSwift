# CLAUDE.md — AtlasCommonSwift

Shared Swift SPM package providing the cross-product contract layer for all atlas iOS apps. Current version: v0.5.0.

## Build & Test

```bash
swift build                    # Build all targets
swift test                     # Run tests (AtlasCommonSwiftTests + OTelTests)
```

Xcode: open `Package.swift`, select any iOS simulator or macOS target to build/test.

## Architecture — Six Library Products

```
AtlasCommonSwift              ← zero dependencies, core types
AtlasCommonSwiftOTel          ← depends on opentelemetry-swift, adds tracing
AtlasCommonSwiftAnalytics     ← depends on posthog-ios, adds analytics + flags
AuthCore                      ← central-auth client: AuthSession (token store + 401-refresh), AuthController (login-state VM base, email/password built in); zero provider deps
AtlasCommonSwiftAuthApple     ← Apple sign-in (AppleSignInController)
AtlasCommonSwiftAuthGoogle    ← Google sign-in (GoogleSignInController)
```

Consumers pick only what they need. All six are in one SPM package for atomic versioning.

### AtlasCommonSwift (Core)

| File | Type | Exports |
|------|------|---------|
| `Types/ApiResponse.swift` | `struct` | `ApiResponse<T: Decodable>` — matches Go `{code, message, data}` envelope |
| `Types/ApiError.swift` | `enum` | `.business(code, message)`, `.unauthorized`, `.network`, `.decoding`, `.unknown`; conforms to `LocalizedError` (`errorDescription`: business→backend message, shells→English) |
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

## Decoder Pitfalls

`HTTPClient` decodes with `keyDecodingStrategy = .convertFromSnakeCase` (`HTTP/HTTPClient.swift:19`). Two traps every consumer hits:

- **Abbreviations don't round-trip.** `.convertFromSnakeCase` capitalizes only the *first* letter of each underscore-delimited segment, so `base_url` becomes `baseUrl` (lowercase "rl"), **not** `baseURL`. A property named `baseURL` silently fails to decode. Fix: give the type an explicit `CodingKeys` whose raw value is the **post-conversion** camelCase form — `case baseURL = "baseUrl"`, NOT `"base_url"`. (Verified empirically; bit both Snag and Parrot before being documented here.)
- **A `CodingKeys` raw value must be the converted key, not the wire key.** Because the strategy runs *before* key matching, every custom `CodingKeys` raw value you write is matched against the already-camelCased key, not the original snake_case JSON.

## Versioning & Release

```bash
git tag v0.5.2
git push origin v0.5.2
```

Consumers (Snag iOS, future apps) resolve by tag in Xcode SPM. Bump tag = new release.

**Breaking change rules:**
- Adding new public API = minor bump (0.3.x → 0.4.0)
- Changing existing public API signature = must bump + update all consumers
- Internal-only changes = patch bump (0.3.1 → 0.3.2)

## Consumers

| App | Version | Products Used |
|-----|---------|---------------|
| Snag iOS | v0.5.0 | All six |

## Testing Requirements

Per `architecture/standards/testing.md`: every exported public function must have a test.

`AuthCore` is covered by `AuthCoreTests` (AuthSession flows, withRetry 401-refresh, AuthController state). Tests inject a `TokenStoring` double (`InMemoryTokenStore`) instead of the Keychain, and a per-session `MockURLProtocol` instead of the network — so the suite is hermetic and parallel-safe.

Current gaps:
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
