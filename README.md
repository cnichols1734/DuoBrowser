# DuoBrowser

A native iOS browser designed to make the iPhone Duo's closed outer display useful edge to edge, with the reliability and familiarity people expect from Safari.

**Working name. Created October 26, 2026.** Includes the approved product direction, research, and native Xcode application. Private GitHub repository: [cnichols1734/DuoBrowser](https://github.com/cnichols1734/DuoBrowser).

## Start here

- [Product brief](docs/PRODUCT_BRIEF.md): proposed experience and unresolved design decisions.
- [Architecture](docs/ARCHITECTURE.md): WebKit, reserved regions, reversible page adaptation, and optional on-device intelligence.
- [Build plan](docs/ROADMAP.md): ordered milestones and acceptance criteria.
- [Research](docs/RESEARCH.md): Brim, Apple documentation, verified SDK APIs, and limitations.
- [Validation](docs/VALIDATION.md): successful build/install/launch and remaining interaction checks.

## First build

Open `DuoBrowser.xcodeproj` in Xcode 27.1, select the **DuoBrowser** scheme and **DuoBrowser QA** simulator, then Run. The starter targets iOS 27.1 and uses SwiftUI with a UIKit-backed `WKWebView`.

The browser now includes normal and private tabs, local history/bookmarks, native sharing and find, downloads to Files, WebKit file/photo selection, guarded external links, JavaScript dialogs, opener-preserving new windows, and per-site original-layout and desktop preferences. The default page is a minimal Start Page. Diagnostic controls and the native test harness are Debug-only.

Normal browsing uses WebKit's persistent data store. Private tabs share a separate nonpersistent store until all private tabs close; their URLs, history, previews, and site preferences are never archived. Explicitly saved bookmarks and Files exports are deliberate exceptions. A native curtain covers app-switcher snapshots. Private browsing does not anonymize network traffic.

The centered native Liquid Glass toolbar collapses into a low domain pill; back/tab actions disappear in compact mode and return on reverse scrolling or a tap. Keyboard, VoiceOver and accessibility text sizes keep controls expanded. Reduce Motion disables the chrome transition. The native scrollbar stays at the full-width right edge. Public WebKit obscured-content insets keep compatible fixed/sticky website controls above the browser toolbar.

The tab grid uses the full display. Its bottom mode control switches between normal and private tabs. Normal tab order, selection, URLs and best-effort scroll position restore from a bounded atomic local archive with a recovery backup. Background restored tabs allocate a web view only when selected. Live forms and navigation stay in their original web views. Under memory pressure, previews are discarded and only eligible static reading pages may release their view; scripts, forms, media, frames, transfers and opener relationships are protected. Opaque interaction state stays in memory and is never written to disk. Cold restart does not restore form values or full back-forward history.

Page fitting has no host-specific rules or AI calls. A bounded detector removes verified safe-area gutter patterns, and a separate camera adapter uses actual reserved-region rectangles to relocate small obstructed controls only when geometry, containment and hit testing validate. Original Layout restores owned changes and persists per host in normal mode (private preferences remain in memory). Complex, transformed, occupied or ambiguous layouts fall back without alteration. This is not a promise that every website can be repaired.

Read the [pre-implementation production audit](docs/PRODUCTION_AUDIT_2026-10-27.md) and [implementation / release gates](docs/PRODUCTION_IMPLEMENTATION_2026-10-27.md). Password providers, arbitrary-site passkey eligibility, authenticated compatibility, physical permissions/media, accessibility and performance require the separate evidence listed there. WKWebView supplies the engine; it does not confer Safari parity.

The [accessibility and memory follow-up](docs/ACCESSIBILITY_MEMORY_2026-10-27.md) records large-text/VoiceOver coverage and the bounded preview cache. For device credentials, follow the [iPhone password/passkey checklist](docs/IPHONE_PASSWORD_PASSKEY_CHECKLIST.md).

Run the [browser behavior checks](Tests/README.md) when changing scrolling or restoration.

Build from the repo root:

```sh
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Synthetic fixtures cover gutter fitting, camera hit testing/rollback, privacy isolation, new-window POST/opener behavior, fixed footers and safe tab reclamation. Live-site and hardware coverage are recorded separately.

## Local environment verified

- Xcode 27.1, build 27A9275.
- iPhoneSimulator27.1 SDK with public reserved-region APIs.
- iOS 27.1 iPhone Duo simulator available; it was already booted when inspected.
- No new SDK, runtime, package manager, or dependency was installed.

See [the build plan](docs/ROADMAP.md) for the next implementation milestones. Development-team signing and a final bundle identifier can be selected when installing on a physical device.

## Add this repo as a local project

Choose this folder in the app's local-project folder picker:

```text
/Users/christophernichols/Documents/Codex/2026-10-26/i-x20/outputs/DuoBrowser
```

Name the project **DuoBrowser**, and move this planning chat into it. The repo is ready, but project registration and the chat move have not been completed: the available project tools cannot create local projects, and computer control of the Codex app was denied.

## Current boundaries

This is the foundation for planning and implementation, not a Safari replacement yet. Broader device and site compatibility, AI quality, animation performance, and App Store eligibility still require implementation or validation. The owner approved the proposed design direction in this chat. Product naming and later release decisions remain open.
