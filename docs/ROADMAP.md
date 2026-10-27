# Build plan

## Completed setup — October 26, 2026

- Local Git repository initialized on main.
- Brim's landing page and TestFlight listing checked; implementation details remain unverified.
- Apple Duo layout, WebKit, Foundation Models, and browser entitlement references researched.
- Xcode 27.1 and Duo simulator availability checked.
- Public reserved-region API declarations found in the installed SDK.
- Initial brief and architecture written. Design confirmation and app-project registration remain open.

## 1. Prove the available space

Create `DuoBrowser.xcodeproj` with a SwiftUI iOS app target, a shared scheme, UIKit/WebKit integration, and iOS 27.1 deployment target. Put app sources under `DuoBrowser/`, synthetic web fixtures under `Tests/Fixtures/`, and meaningful geometry tests under `DuoBrowserTests/`. Use no third-party dependencies initially. Keep the signing team unset for local simulator builds.

Build a diagnostic browser shell with URL entry, back/forward, reload/stop, and a full-width mode. Expose reserved-region and viewport overlays only in development UI. Make a dedicated DuoBrowser QA simulator so existing QA sessions are not disturbed.

Acceptance:

- Build with xcodebuild for iOS Simulator and launch on Duo.
- Compare Safari, ordinary WKWebView, and experimental full-width WKWebView on identical fixtures and zoom levels.
- Record actual web viewport width and height, occluded area, browser chrome area, and reachable actions in closed, open, rotated, and partially folded poses.
- Verify keyboard entry and pinch zoom before adding AI.
- No fixed camera coordinates, private API, unexplained blank rail, or inaccessible navigation.

Gate: prove a usable-space gain. SDK availability alone does not pass.

## 2. Fit around the camera

Implement bounded DOM collision detection, a reversible adjustment ledger, geometry conversion, and original-layout/site-disable controls. Add fixture cases for fixed and sticky headers, flex/grid menus, right-to-left layouts, forms, scrolling containers, transformed/clipped elements, safe-area-aware sites, and dynamic replacement of nodes. Include unsupported iframe/canvas cases that deliberately fall back.

Acceptance:

- Every fixture's essential action remains reachable and functional after adjustment and restoration.
- Navigation, zoom, focus, form state, and fold transitions remain intact.
- Repeated mutations converge or trigger fallback; there is no feedback loop.
- Motion looks intentional at normal speed and obeys Reduce Motion.
- On-device profiling targets smooth scrolling with no adaptation-created long main-thread stalls; record traces before declaring success.

## 3. Test whether AI helps

Add optional Foundation Models classification behind an experimental switch. Use typed outputs selecting existing actions. Benchmark against the deterministic engine on the same held-out layouts.

Acceptance: a measured improvement in successful repairs, bounded latency and energy impact, safe failure/timeout behavior, no inference during every scroll frame, and unchanged browsing when the model is unavailable. Test on an eligible physical device; a simulator is not evidence of real Apple Intelligence performance.

Retain AI only if it improves the experience. The product benefit is better browsing space.

## 4. Make it a daily browser

Add persistent tabs and crash recovery, bookmarks/history, private sessions, find in page, share, downloads, page zoom/text controls, permission handling, desktop-site preference, and content-blocking support. Cover JS dialogs, popups, file uploads, PDFs, media, WebRTC, and network failures.

Assess password/passkey/autofill behavior and relevant entitlements separately. Evaluate Reader and sync as later capabilities; do not promise Safari's integrations. Keep privacy deletion complete across web data, history, tabs, caches, and diagnostics.

Acceptance: routine browsing flows pass on the owner's frequent sites, a representative compatibility corpus, and a physical Duo. Restore sessions after process termination. Verify private-data isolation and deletion.

## 5. Release readiness

Test VoiceOver, Dynamic Type, Reduce Motion, keyboard accessibility, hardware touch targets, Live Activities/system occlusion changes, network transitions, memory pressure, energy, and long sessions. Compare the same tasks against Safari.

Request the default-browser capability and any other needed managed entitlements through Apple's process. Review adaptation behavior against default-browser requirements; preserve the site's intended content and navigation. Select final naming, bundle ID, icon, privacy disclosures, signing, and distribution route before TestFlight/App Store work.

## Measurement sheet

For each comparison, record device/runtime, pose, site/fixture version, zoom, browser mode, raw viewport size, exclusion area, chrome area, and usable area as the viewport minus the union of occlusions/chrome. Also record completed essential actions, layout regressions, adaptation latency, frame hitches, and fallback rate. Avoid double-counting overlapping regions. All performance budgets are proposed targets until measured on hardware.

## Next owner input

Review PRODUCT_BRIEF.md, particularly bottom floating controls and the initial opt-in adaptation experiment. Add this folder as a local project in the app, then move the planning chat into that project. Supply frequently visited sites when convenient; synthetic fixtures can proceed independently.
