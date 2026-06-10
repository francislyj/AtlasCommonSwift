# CC-1 — Error → User-Message Mapping (both ends)

- **Date:** 2026-06-10
- **Repos:** AtlasCommonSwift (+ Snag), atlas-infra-mono (admin-web)
- **Status:** Design approved, pending spec review
- **Gap addressed:** CC-1 in [`architecture/client-infrastructure-gaps.md`](../../../../architecture/client-infrastructure-gaps.md)

## Problem

Both clients hand-roll the "API error → user-facing text" step, and both under-use the backend's already-i18n'd `message`:

- **iOS**: Snag adds a *retroactive* `LocalizedError` conformance to `ApiError` in `Snag/Snag/Data/SnagAPI.swift:148`. Its business-error arm already does the right thing (`case .business(_, let message): message` — uses the backend message), but the conformance lives in the app, so every new iOS app must re-add it. The non-business arms (network/decoding/unauthorized/unknown) are hardcoded Chinese shells.
- **Web**: every mutation page does `catch { toast.error(t("form.toast.createFailed")) }` — **discarding the caught error entirely** and showing a static i18n key. The backend message *is* available (both `unwrap()` and `createHttpClient` throw `new Error(<backend message>)`), but it's thrown away, so a specific server message like "role name already exists" never reaches the user.

Core insight: the backend `message` is already localized and specific; both ends should surface it, falling back to a generic string only when absent.

## Decision

Fix both ends; they land in different places because the right altitude differs.

### iOS — hoist `LocalizedError` into AtlasCommonSwift (mechanism, Snag uses it)
Add a (non-retroactive) `LocalizedError` conformance to `ApiError` in the library (`Sources/AtlasCommonSwift/Types/ApiError.swift`):
```swift
extension ApiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let e): "Network error: \(e.localizedDescription)"
        case .decoding(let e): "Failed to parse response: \(e.localizedDescription)"
        case .business(_, let message): message
        case .unauthorized: "Unauthorized"
        case .unknown: "Unknown error"
        }
    }
}
```
- Business errors use the backend `message` verbatim (already i18n'd) — the high-value, common case.
- Shell strings (network/decoding/unauthorized/unknown) are **English** neutral defaults. The library must not embed Chinese; a product that wants localized shells can override (Snag does not, by default — business errors dominate and already show the backend's Chinese message).
- Snag **deletes** its retroactive extension (`SnagAPI.swift:148–159`). The View-layer catch (`(error as? LocalizedError)?.errorDescription ?? error.localizedDescription`) is **unchanged** — it keeps working, now backed by the library's conformance.
- Released as a new AtlasCommonSwift tag (additive public API → minor bump: **v0.5.0**).

### Web — surface the backend message (app-local, not hoisted)
- Add a tiny local helper `messageFromError(err, fallback)` in admin-web `src/lib/`:
```typescript
export function messageFromError(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
```
- Change the 7 `catch` sites from `catch { toast.error(t("...")) }` to:
```typescript
catch (e) { toast.error(messageFromError(e, t("form.toast.createFailed"))) }
```
  (each keeps its own existing fallback key). The 7 sites: `permissions/create`, `permissions/[id]`, `roles/create`, `roles/[id]`, `users/create`, `users/[id]`, `components/resource-table.tsx` (delete).
- **Not hoisted to atlas-common-js**: it's a 2-line `err.message` extractor, and *how* to present an error (toast vs inline vs which i18n fallback) is an app UI decision. `unwrap()` already deposits the message into the Error; the library's job ends there. No second web consumer exists (Single-host rule). Pure admin-web change, no version coordination.

## Data flow (after)

**iOS:** backend non-0 code → `HTTPClient` throws `ApiError.business(code, backendMessage)` → View's existing `(error as? LocalizedError)?.errorDescription` resolves to `backendMessage` (library conformance) → shown. Behavior for business errors is identical to today; only the shell-case wording changes (Chinese → English) and the conformance source moves app → library.

**Web:** mutation throws `Error(backendMessage)` → `catch (e)` → `messageFromError(e, t(fallbackKey))` → `toast.error`. Backend message now reaches the user; the static key is only the fallback.

## Migration order (iOS — avoid duplicate conformance)

Two `LocalizedError` conformances on `ApiError` cannot coexist (compile conflict). So:
1. Ship AtlasCommonSwift with the library conformance → tag v0.5.0.
2. In Snag, **in one commit**: bump AtlasCommonSwift to v0.5.0 **and** delete the retroactive extension. Never an intermediate state where both the bumped library and Snag's extension are present.

Web has no such ordering concern (self-contained).

## Verification

- **AtlasCommonSwift**: `swift build` — conformance compiles.
- **Snag**: after bump + delete, `swift build` — confirms no duplicate-conformance conflict and the View catch still resolves via the library. (Behavior unchanged for business errors; manual spot-check optional since the mapping is mechanical.)
- **admin-web**: `pnpm lint && npx tsc --noEmit && pnpm build` — 7 sites compile; a green build confirms `messageFromError` typed correctly.
- No new test framework (Swift has a test target but this mapping is trivial/mechanical; admin-web has no runner — consistent with prior CW work). Verification is build-green on both ends.

## Out of scope

- Hoisting `messageFromError` to atlas-common-js (app-local UI concern; no second consumer).
- Changing iOS View-layer catch logic (unchanged — already LocalizedError-based).
- Unifying the two ends' presentation (iOS `@Published errorMessage` vs Web `toast` — each an app UI choice).
- Localized (Chinese) shell strings in the library (English neutral defaults; product overrides if needed — Snag does not by default).
