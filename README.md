# DuoBrowser

A native iOS browser designed to make the iPhone Duo's closed outer display useful edge to edge, with the reliability and familiarity people expect from Safari.

**Working name. Local planning repository, created October 26, 2026.** No browser implementation or runnable Xcode target exists yet. No remote repository has been created.

## Start here

- [Product brief](docs/PRODUCT_BRIEF.md): proposed experience and unresolved design decisions.
- [Architecture](docs/ARCHITECTURE.md): WebKit, reserved regions, reversible page adaptation, and optional on-device intelligence.
- [Build plan](docs/ROADMAP.md): ordered milestones and acceptance criteria.
- [Research](docs/RESEARCH.md): Brim, Apple documentation, verified SDK APIs, and limitations.

## First build

Create a small SwiftUI iOS app in Xcode 27.1 using a UIKit-backed `WKWebView`. Target iOS 27.1 for the first Duo experiment. Prove full-width rendering and camera avoidance before expanding into a daily browser.

The first demonstration should open a fixture with a menu button under the camera, move the button to a reachable position, preserve its action, and restore the original layout. Then repeat on live sites and through fold/unfold, rotation, and pinch zoom. A static mockup does not pass this milestone.

## Local environment verified

- Xcode 27.1, build 27A9275.
- iPhoneSimulator27.1 SDK with public reserved-region APIs.
- iOS 27.1 iPhone Duo simulator available; it was already booted when inspected.
- No new SDK, runtime, package manager, or dependency was installed.

See [the build plan](docs/ROADMAP.md) for Xcode project setup. Development-team signing and a final bundle identifier can be selected when installing on a physical device.

## Add this repo as a local project

Choose this folder in the app's local-project folder picker:

```text
/Users/christophernichols/Documents/Codex/2026-10-26/i-x20/outputs/DuoBrowser
```

Name the project **DuoBrowser**, and move this planning chat into it. The repo is ready, but project registration and the chat move have not been completed: the available project tools cannot create local projects, and computer control of the Codex app was denied.

## Current boundaries

This is the foundation for planning and implementation, not a Safari replacement yet. Full-width behavior, site compatibility, AI quality, animation performance, and App Store eligibility require implementation and validation. The proposed design is recorded as a draft, not as owner-approved.
