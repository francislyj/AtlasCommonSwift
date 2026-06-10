# AtlasCommonSwift

Common Swift building blocks for Atlas iOS projects. Six library products in one SPM package.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/francislyj/AtlasCommonSwift.git", from: "0.4.0"),
]
```

Then add the products you need to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "AtlasCommonSwift", package: "AtlasCommonSwift"),
        .product(name: "AtlasCommonSwiftOTel", package: "AtlasCommonSwift"),
        .product(name: "AtlasCommonSwiftAnalytics", package: "AtlasCommonSwift"),
    ]
)
```

## Library Products

| Product | Dependencies | What it provides |
|---------|--------------|------------------|
| `AtlasCommonSwift` | None | Core types, HTTP client, Keychain, Logger |
| `AtlasCommonSwiftOTel` | opentelemetry-swift | OTel setup, instrumented HTTP client, log upload |
| `AtlasCommonSwiftAnalytics` | posthog-ios | PostHog analytics + feature flags |
| `AuthCore` | None | Central-auth client: `AuthSession` (token store + 401-refresh `withRetry`), `AuthController` (login-state VM base, email/password built in) |
| `AtlasCommonSwiftAuthApple` | AuthenticationServices | Apple sign-in (`AppleSignInController`) |
| `AtlasCommonSwiftAuthGoogle` | GoogleSignIn | Google sign-in (`GoogleSignInController`) |

---

## AtlasCommonSwift (Core)

### Types

| Type | Description |
|------|-------------|
| `ApiResponse<T>` | Matches Go backend envelope: `{ "code": 0, "message": "success", "data": T }` |
| `ApiError` | `.business(code, message)`, `.unauthorized`, `.network(Error)`, `.decoding(Error)`, `.unknown` |
| `ErrorCode` | Constants: `.success` (0), `.internalError` (10000), `.unauthorized` (10001), `.invalidParams` (10002), `.rateLimited` (10003) |

### HTTPClient

Actor-isolated async HTTP client with auto JSON encoding/decoding and auth token injection.

```swift
import AtlasCommonSwift

let client = HTTPClient(
    baseURL: URL(string: "https://api.example.com")!,
    tokenProvider: { KeychainHelper.loadString(key: "access_token") }
)

let users: [User] = try await client.get("/api/users", query: ["page": "1"])
try await client.post("/api/users", body: newUser)
```

The client automatically unwraps the `ApiResponse<T>` envelope — callers receive `T` directly on success or `ApiError` on failure.

### KeychainHelper

```swift
KeychainHelper.saveString(key: "access_token", value: token)
let token = KeychainHelper.loadString(key: "access_token")
KeychainHelper.delete(key: "access_token")
```

### Log

Thin wrapper around `os.Logger` with category support.

```swift
Log.info("User logged in", category: "Auth")
Log.error("Request failed", category: "Network")
```

---

## AtlasCommonSwiftOTel

OpenTelemetry integration for iOS apps. Exports traces to Grafana Cloud via OTLP HTTP.

### OTelConfig & OTelSetup

```swift
import AtlasCommonSwiftOTel

let config = OTelConfig(
    endpoint: URL(string: "https://otlp-gateway.grafana.net/otlp")!,
    headers: ["Authorization": "Basic ..."],
    serviceName: "my-ios-app"
)

OTelSetup.configure(config)
```

### InstrumentedHTTPClient

Wraps `HTTPClient` with automatic OTel span creation and W3C `traceparent` header injection. Every request creates a span and links to the backend trace.

```swift
import AtlasCommonSwiftOTel

let client = InstrumentedHTTPClient(
    baseURL: URL(string: "https://api.example.com")!,
    tokenProvider: { KeychainHelper.loadString(key: "token") }
)

// Automatically creates span: "GET /v1/moments"
// Injects traceparent header for trace continuity with Go backend
let moments: [Moment] = try await client.get("/v1/moments")
```

Use `InstrumentedHTTPClient` instead of plain `HTTPClient` in all instrumented apps.

### LogUploader

Batch-uploads `OSLog` entries to Grafana Loki via the OTel endpoint.

```swift
LogUploader.configure(otelConfig)

// Later, from a diagnostics/settings screen:
let entries = collectLogEntries()
try await LogUploader.upload(entries: entries)
```

---

## AtlasCommonSwiftAnalytics

PostHog wrapper for analytics events and feature flags.

### Analytics.configure

```swift
import AtlasCommonSwiftAnalytics

Analytics.configure(Analytics.Config(
    enabled: true,
    projectToken: "phc_xxx",
    host: "https://us.i.posthog.com"
))
```

### Event Tracking

```swift
Analytics.capture("button_tapped", properties: ["screen": "home"])
Analytics.screen("SettingsView")
Analytics.identify("user_123", properties: ["plan": "pro"])
Analytics.reset()  // on logout
```

### Feature Flags

```swift
let showFeature = Analytics.isFeatureEnabled("new_onboarding")

// Force reload from server (async, fires callback when done)
Analytics.reloadFeatureFlags {
    let updated = Analytics.isFeatureEnabled("new_onboarding")
}
```

Flags are preloaded automatically on `configure()`. On first launch, flags may not be available immediately — use `reloadFeatureFlags` with a callback if you need guaranteed freshness.

---

## Canonical Initialization Sequence

iOS apps built on atlas infrastructure follow this boot order:

1. Fetch server config from `/v1/app-config` (credentials come from server, not bundled)
2. `OTelSetup.configure(config)` — start trace export
3. `LogUploader.configure(config)` — store config for later log upload
4. `Analytics.configure(config)` — start PostHog
5. `Analytics.reloadFeatureFlags { ... }` — hydrate flag cache, trigger UI update

See Snag iOS `FeatureFlagService.swift` for the reference implementation.

---

## Requirements

- iOS 16+ / macOS 13+
- Swift 6.0+ (strict concurrency)

## License

ISC
