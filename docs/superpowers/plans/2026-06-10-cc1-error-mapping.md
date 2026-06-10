# CC-1 Error → User-Message Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the backend's already-i18n'd error `message` to users on both clients — by hoisting iOS's `LocalizedError` into AtlasCommonSwift, and by making admin-web's catch blocks use the thrown error's message instead of a static key.

**Architecture:** iOS half = library `LocalizedError` conformance (business → backend message, shells → English defaults), Snag deletes its retroactive copy. Web half = a local `messageFromError` helper + 7 catch-site edits. Different altitudes: iOS hoists (real mechanism, Snag consumes); Web stays app-local (2-line UI helper).

**Tech Stack:** Swift 6 (AtlasCommonSwift SPM), TypeScript/Next.js (admin-web), sonner toasts.

**Spec:** `docs/superpowers/specs/2026-06-10-cc1-error-mapping-design.md`

---

## Reality notes (read first)

- **AtlasCommonSwift** is buildable from CLI (`swift build`) — its half is fully scriptable + verifiable.
- **Snag** is an `.xcodeproj` app; its `Package.resolved` is currently pinned at AtlasCommonSwift **0.3.1** (it hasn't even pulled v0.4.0/DEF-8). Updating Snag's pin is an **Xcode operation** (File → Packages → Update to Latest, which rewrites `Package.resolved`), not a clean CLI edit. So the Snag-side step (bump + delete extension) is a **guided manual step for the user**, like DEF-3's browser verification. The plan makes the library change land + release first; the Snag migration is documented precisely but executed in Xcode by the user.
- **admin-web** half is fully scriptable (lint + tsc + build).

The two halves are independent — Web can ship without waiting on the Snag Xcode step.

---

### Task 1: AtlasCommonSwift — add LocalizedError to ApiError

**Repo:** AtlasCommonSwift. **Files:** `Sources/AtlasCommonSwift/Types/ApiError.swift`.

- [ ] **Step 1: Append the conformance**

The file currently ends at the `ApiError` enum (line 9). Append after it:
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
Business errors use the backend `message`; the four shell cases are English neutral defaults (the library must not embed Chinese).

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!` (the GoogleSignIn umbrella-header warning is pre-existing, ignore it).

- [ ] **Step 3: Commit**

```bash
git add Sources/AtlasCommonSwift/Types/ApiError.swift
git commit -m "feat(ApiError): LocalizedError conformance (business→backend message, English shells)"
```

---

### Task 2: AtlasCommonSwift — release v0.5.0 + docs

**Repo:** AtlasCommonSwift. **Files:** `CLAUDE.md`, `README.md` (version refs).

Additive public API (new conformance) → minor bump. Current tag v0.4.0 → **v0.5.0**.

- [ ] **Step 1: Bump version refs in docs**

In `CLAUDE.md`: change `Current version: v0.4.0` → `v0.5.0`; in the Consumers table `Snag iOS | v0.4.0` → `v0.5.0`; in the release example `git tag v0.4.1` → `git tag v0.5.1`.
In `README.md`: change SPM snippet `from: "0.4.0"` → `from: "0.5.0"`.
In the `ApiError` row of CLAUDE.md's AtlasCommonSwift table, append `; conforms to LocalizedError (errorDescription)`.

- [ ] **Step 2: Commit docs**

```bash
git add CLAUDE.md README.md
git commit -m "docs: AtlasCommonSwift v0.5.0 (ApiError LocalizedError)"
```

- [ ] **Step 3: Tag + verify + push**

```bash
git tag v0.5.0
git show v0.5.0:Sources/AtlasCommonSwift/Types/ApiError.swift | grep -c LocalizedError   # MUST be ≥1 (empty-tag guard)
git push origin v0.5.0 main
```
Expected: grep ≥1. Report the tag.

---

### Task 3: Snag — bump + delete retroactive extension (GUIDED MANUAL — user runs Xcode)

**Repo:** Snag. **Files:** `Snag/Snag/Data/SnagAPI.swift` (delete extension), `Package.resolved` (via Xcode).

> This task needs Xcode (SPM update rewrites Package.resolved). The controller hands these exact steps to the user; the agent does NOT attempt a CLI build of the .xcodeproj. **Bump and delete happen together** — never leave both the bumped library and Snag's extension present (duplicate `LocalizedError` conformance = compile error).

- [ ] **Step 1: Delete Snag's retroactive extension**

In `Snag/Snag/Data/SnagAPI.swift`, delete lines 148–158 (the entire block):
```swift
extension ApiError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let err): "网络错误：\(err.localizedDescription)"
        case .decoding(let err): "解析失败：\(err.localizedDescription)"
        case .business(_, let message): message
        case .unauthorized: "未授权"
        case .unknown: "未知错误"
        }
    }
}
```
(This edit IS scriptable — the agent can make it. Only the SPM update + build need Xcode.)

- [ ] **Step 2 (USER, in Xcode): Update the package + build**

In Xcode with `Snag.xcodeproj` open:
1. File → Packages → Update to Latest Package Versions (rewrites `Package.resolved`: AtlasCommonSwift 0.3.1 → 0.5.0).
2. Cmd+B.
Expected: builds clean. The View-layer catch `(error as? LocalizedError)?.errorDescription` now resolves via the **library's** conformance (business errors still show the backend message; network/decoding/unauthorized/unknown shells are now English).

If build fails with "redundant conformance of 'ApiError' to 'LocalizedError'": the Step 1 deletion didn't take — confirm the extension block is gone.

- [ ] **Step 3 (USER): Commit in Snag repo**

```bash
cd Snag
git add Snag/Data/SnagAPI.swift Snag.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "refactor(Snag): use AtlasCommonSwift LocalizedError; drop retroactive extension (CC-1)"
git push origin main
```
(Adjust the Package.resolved path to where `git status` shows it changed.)

> **Note for the controller:** make the Step 1 deletion via Edit, commit nothing for Snag yourself, and surface Steps 2–3 to the user as a manual checklist. Snag is not "done" until the user confirms the Xcode build is green.

---

### Task 4: admin-web — messageFromError helper

**Repo:** atlas-infra-mono, app `apps/atlas-admin-web`. **Files:** Create `src/lib/error-message.ts`.

- [ ] **Step 1: Create the helper**

`apps/atlas-admin-web/src/lib/error-message.ts`:
```typescript
/**
 * Extracts a user-facing message from a caught error, preferring the backend
 * message (which the API envelope already localizes) and falling back to a
 * caller-supplied generic string.
 */
export function messageFromError(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
```

- [ ] **Step 2: Typecheck**

Run from `apps/atlas-admin-web`: `npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add apps/atlas-admin-web/src/lib/error-message.ts
git commit -m "feat(admin-web): messageFromError helper (surface backend error message)"
```

---

### Task 5: admin-web — wire messageFromError into the 7 catch sites

**Repo:** atlas-infra-mono. **Files (7):**
- `src/app/dashboard/permissions/create/page.tsx`
- `src/app/dashboard/permissions/[id]/page.tsx`
- `src/app/dashboard/roles/create/page.tsx`
- `src/app/dashboard/roles/[id]/page.tsx`
- `src/app/dashboard/users/create/page.tsx`
- `src/app/dashboard/users/[id]/page.tsx`
- `src/components/resource-table.tsx`

- [ ] **Step 1: Edit each file — add import + change catch**

In each file, add the import (near the other `@/lib` imports):
```typescript
import { messageFromError } from "@/lib/error-message";
```
Then change the catch block. The pattern in each:

`permissions/create/page.tsx` (lines 22–23):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("form.toast.createFailed")))
```
`permissions/[id]/page.tsx` (lines 30–31):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("form.toast.updateFailed")))
```
`roles/create/page.tsx` (lines 26–27):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("form.toast.createFailed")))
```
`roles/[id]/page.tsx` (lines 31–32):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("form.toast.updateFailed")))
```
`users/create/page.tsx` (lines 23–24):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("form.toast.createFailed")))
```
`users/[id]/page.tsx` (lines 28–29):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("form.toast.updateFailed")))
```
`components/resource-table.tsx` (lines 49–50, note the trailing semicolon style in this file):
```typescript
    } catch (e) {
      toast.error(messageFromError(e, t("table.deleteFailed")));
```
(Only the `catch {` → `catch (e) {` and the `toast.error(...)` line change. Keep each file's existing fallback key and semicolon style.)

- [ ] **Step 2: Lint + typecheck + build**

Run:
```bash
pnpm --filter atlas-admin-web lint
cd apps/atlas-admin-web && npx tsc --noEmit && cd -
pnpm --filter atlas-admin-web build
```
Expected: lint clean (no unused-var on `e` — it's used), tsc exit 0, build succeeds.

- [ ] **Step 3: Commit + push**

```bash
git add apps/atlas-admin-web/src/app/dashboard/permissions/create/page.tsx apps/atlas-admin-web/src/app/dashboard/permissions/'[id]'/page.tsx apps/atlas-admin-web/src/app/dashboard/roles/create/page.tsx apps/atlas-admin-web/src/app/dashboard/roles/'[id]'/page.tsx apps/atlas-admin-web/src/app/dashboard/users/create/page.tsx apps/atlas-admin-web/src/app/dashboard/users/'[id]'/page.tsx apps/atlas-admin-web/src/components/resource-table.tsx
git commit -m "feat(admin-web): show backend error message in toasts, generic key as fallback (CC-1)"
git push origin main
```

---

### Task 6: Mark CC-1 resolved

**Repo:** workspace root (tracks `architecture/`). **File:** `architecture/client-infrastructure-gaps.md`.

- [ ] **Step 1:** Strike through the CC-1 block, mark resolved (2026-06-10): iOS `LocalizedError` hoisted to AtlasCommonSwift v0.5.0 (business→backend message, English shells; Snag dropped its retroactive copy); admin-web now surfaces backend message via `messageFromError` across 7 catch sites, generic key as fallback. Update the 优先级建议 list (CC-1 was item 4). If the Snag Xcode bump is still pending user confirmation, note CC-1 as "Web done + library shipped; Snag pickup pending Xcode update" rather than fully resolved.

- [ ] **Step 2: Commit + push**

```bash
cd /Users/user/Documents/workspace/freelancer
git add architecture/client-infrastructure-gaps.md
git commit -m "docs: mark CC-1 (error→message mapping) resolved"
git push origin main
```

---

## Notes for the implementer

- **Repos**: Tasks 1-2 AtlasCommonSwift; Task 3 Snag (manual Xcode for the user); Tasks 4-5 atlas-infra-mono; Task 6 workspace root. Never mix repos in one commit.
- **Task 3 is the manual one** — agent makes the SnagAPI.swift deletion edit, but the SPM update + build + commit are the user's Xcode steps. Don't claim Snag done until the user confirms a green build.
- **Web is independent of Snag** — Tasks 4-5 can complete and ship regardless of the Snag Xcode step.
- **No test framework** added (Swift mapping is mechanical; admin-web has no runner) — verification is build-green on both ends.
- **iOS shells are English** — do not write Chinese in the library.
