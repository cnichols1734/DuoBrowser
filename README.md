# DuoBrowser

A native iOS browser designed to make the iPhone Duo's closed outer display useful edge to edge, with the reliability and familiarity people expect from Safari.

**Working name. Local repository, created October 26, 2026.** Includes the approved product direction, research, and a buildable native Xcode starter. No remote repository has been created.

## Start here

- [Product brief](docs/PRODUCT_BRIEF.md): proposed experience and unresolved design decisions.
- [Architecture](docs/ARCHITECTURE.md): WebKit, reserved regions, reversible page adaptation, and optional on-device intelligence.
- [Build plan](docs/ROADMAP.md): ordered milestones and acceptance criteria.
- [Research](docs/RESEARCH.md): Brim, Apple documentation, verified SDK APIs, and limitations.
- [Validation](docs/VALIDATION.md): successful build/install/launch and remaining interaction checks.

## First build

Open `DuoBrowser.xcodeproj` in Xcode 27.1, select the **DuoBrowser** scheme and **DuoBrowser QA** simulator, then Run. The starter targets iOS 27.1 and uses SwiftUI with a UIKit-backed `WKWebView`.

It includes URL/search entry (DuckDuckGo for searches), back/forward, reload/stop, a local viewport fixture, full-width mode, and reserved-region overlays. It starts in full-width mode with the status bar hidden. Turn off “Full-width page” in Browser options to compare the safe-area layout. Camera avoidance, tab management, and AI are not implemented yet.

Build from the repo root:

```sh
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The first demonstration should open a fixture with a menu button under the camera, move the button to a reachable position, preserve its action, and restore the original layout. Then repeat on live sites and through fold/unfold, rotation, and pinch zoom. A static mockup does not pass this milestone.

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

This is the foundation for planning and implementation, not a Safari replacement yet. Full-width behavior, site compatibility, AI quality, animation performance, and App Store eligibility require implementation and validation. The owner approved the proposed design direction in this chat. Product naming and later release decisions remain open.
