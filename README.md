# AtlasCommonSwift

Common Swift building blocks for Atlas iOS projects.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/francislyj/AtlasCommonSwift.git", from: "1.0.0"),
]
```

## What's Included

| Module | Description |
|--------|-------------|
| Types | `ApiResponse<T>`, `ErrorCode`, `ApiError` — matches Go backend contract |
| HTTP | `HTTPClient` actor — async/await, auto auth injection |
| Keychain | `KeychainHelper` — token persistence via Security framework |
| Logger | `Log` — thin wrapper around `os.Logger` |

## Usage

### HTTP Client

```swift
import AtlasCommonSwift

let client = HTTPClient(
    baseURL: URL(string: "https://api.example.com")!,
    tokenProvider: { KeychainHelper.loadString(key: "access_token") }
)

let users: [User] = try await client.get("/api/users", query: ["page": "1"])
```

### Keychain

```swift
KeychainHelper.saveString(key: "access_token", value: token)
let token = KeychainHelper.loadString(key: "access_token")
KeychainHelper.delete(key: "access_token")
```

### Logger

```swift
Log.info("User logged in")
Log.error("Request failed")
```

## Requirements

- iOS 16+ / macOS 13+
- Swift 6.3+

## License

ISC
