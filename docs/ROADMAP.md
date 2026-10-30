# Build plan

## Completed setup — October 26, 2026

- Local Git repository initialized on main.
- Brim's landing page and TestFlight listing checked; implementation details remain unverified.
- Apple Duo layout, WebKit, Foundation Models, and browser entitlement references researched.
- Xcode 27.1 and Duo simulator availability checked.
- Public reserved-region API declarations found in the installed SDK.
- Initial brief direction approved by the owner. App-project registration remains open.
- Native Xcode project created with a shared DuoBrowser scheme, iOS 27.1 app target, local fixture, URL/search navigation, full-width toggle, and reserved-region overlay.
- Debug build passed for both simulator architectures. A dedicated DuoBrowser QA simulator was created; installation and launch succeeded. Interaction testing remains open; see VALIDATION.md.
- Follow-up: removed the default right-hand blank strip by enabling full-width rendering and hiding the status bar. Rebuilt and installed on DuoBrowser QA; visually confirmed Apple's website spans the closed display. See VALIDATION.md for remaining checks.
- Scrolling follow-up: moved the native indicator to the right edge and added a compact URL pill on downward scrolling, with upward-scroll/tap restoration. Build and 16 policy checks passed; native closed-display collapse, restoration, and keyboard interactions passed. Other poses, accessibility settings, and hardware remain to verify; see VALIDATION.md.

## Glass controls and tabs — October 26, 2026

- Centered bottom controls across the full display, using native Liquid Glass without a forced material tint or appearance.
- Added a continuous domain-capsule collapse, with separate compact/expanded vertical positions. Side controls fade near the outer edges and are absent when compact; tap or reverse scrolling restores them.
- Added multiple tabs with stable web views, page previews, close/new/select, tab search, and basic URL/order/selection restoration. Background restored tabs load when selected. Private browsing, tab groups, full session recovery, and memory-pressure eviction remain later work.
- Build and 33 portable behavior checks passed. Closed-Duo native creation, URL entry, selection, closing, relaunch restoration, full-width overview, and compact/restored controls were exercised. See VALIDATION.md for detailed evidence and remaining checks.

## YouTube feed compatibility — October 26, 2026

- Implemented a bounded, reversible mobile YouTube body-padding correction. Feed previews and search results now span 466 CSS pixels on the closed QA display, reclaiming the measured 84px gutter. The independently inset header stays unchanged.
- Added an “Original YouTube layout” switch for the current live tab; full-width off also restores the original page. No AI, page text collection, or general bridge is involved.
- Enabled inline media playback for sites that request it, avoiding forced fullscreen feed previews.
- Simulator build, 16 synthetic browser layout checks, 21 scroll checks, and 12 archive checks passed. Native feed/search, scrolling, menu reachability, restore/reapply, and playback checks are recorded in VALIDATION.md.
- The watch-page player's separate inset, general camera avoidance, native pinch/accessibility, broad pose coverage, and hardware profiling remain open.

## Automatic gutter fitting — October 27, 2026

- Replaced the YouTube-specific module with `PageLayout`: no host or site-element rules remain. Detect one matching body/root-wrapper gutter with a responsive child and protected fixed/sticky top bar. Validate header descendants and horizontal overflow; roll back failures.
- Added the universal “Original page layout” control. Generalized the regression suite to 24 real-browser synthetic scenarios, including unrelated origins and standard HTML containers; all passed.
- Updated the native viewport lab to exercise the same safe-area pattern without YouTube markup. See VALIDATION.md for actual native results.
- Confirmed current Apple Foundation Models APIs and documented the bounded on-device selection experiment in ARCHITECTURE.md. No AI runtime integration or universal camera avoidance is claimed. Native pinch/collision validation, additional safe operations, held-out evaluation, and eligible physical hardware precede AI enablement.

## 1. Prove the available space

### Owner's eight-site smoke test — October 27, 2026

All eight supplied sites were exercised in the native QA simulator; [results and coverage limits](SITE_QA_2026-10-27.md). Prioritize general camera-control protection and browser/site bottom-UI collision handling, then diagnose Google/Meta gutters and the native Open Link path that launched Safari. Logged-in flows, complete sticky/infinite-scroll coverage, and the broader device/accessibility matrix remain open. No runtime fix or AI integration was added in this test pass.

The starter `DuoBrowser.xcodeproj` now has a SwiftUI iOS app target, shared scheme, UIKit/WebKit integration, and iOS 27.1 deployment target. Put app sources under `DuoBrowser/`, synthetic web fixtures under `Tests/Fixtures/`, and meaningful geometry tests under `DuoBrowserTests/`. Use no third-party dependencies initially. Keep the signing team unset for local simulator builds.

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

The owner approved PRODUCT_BRIEF.md's direction, including bottom floating controls and the initial opt-in adaptation experiment. Add this folder as a local project in the app, then move the planning chat into that project. Supply frequently visited sites when convenient; synthetic fixtures can proceed independently.

## Production audit and implementation — October 27, 2026

The requested P0/P1/Duo gap analysis was completed before code changes: [frozen audit and dependency plan](PRODUCTION_AUDIT_2026-10-27.md). Subsequent profile/privacy, durable-state, navigation, transfer, library and geometry work is described in [implementation and release gates](PRODUCTION_IMPLEMENTATION_2026-10-27.md). That report supersedes earlier “future work” descriptions for those features, without converting unverified credential/hardware behavior into a pass.

The immediate next release dependencies are signed credential/passkey eligibility, physical permissions and accessibility, hostile/complex layout fallback, and low-memory/endurance validation. There is still no on-device AI implementation or reason to require it for basic browsing.


## Accessibility and memory follow-up — October 27, 2026

Added adaptive large-text browser/tab/library controls, constrained address editing, explicit accessibility traits/order, dynamic bottom obscuration and error announcements. Preview images now have a 640-pixel dimension ceiling and 8 MiB cache budget with recent-tab priority. Reclamation uses isolated, bounded DOM checks and protects inline-event pages as well as forms/scripts. See [measured results and remaining gates](ACCESSIBILITY_MEMORY_2026-10-27.md) and [the owner device credential checklist](IPHONE_PASSWORD_PASSKEY_CHECKLIST.md). Physical spoken/gesture coverage, WebKit-inclusive memory/energy endurance and correctly provisioned arbitrary-site passkeys remain separate release work.

- Rotated native controls now use active system occlusion geometry to avoid the bottom camera without narrowing the page; final Debug/Release builds and 30 native checks passed. See the accessibility/memory follow-up for limits.

## App icon — October 27, 2026

The owner selected and supplied a blue-globe/open-book icon after the earlier compass and two-panel D concepts, then requested removal of its exterior white border. The navy background now fills the square asset, with iOS applying the final corner mask. The 28-second product demo closing card also uses the selected artwork. See [asset provenance and verification](APP_ICON.md). The 1024-pixel opaque raster is wired into Debug and Release; custom dark/tinted layers and hardware appearance remain unverified.

## Open-source preparation — October 27, 2026

Prepared MIT licensing, contribution/security/release guidance, issue/PR templates, owner review policy, pinned development tools and hosted CI on `chore/open-source-preparation`. The pre-change exposure assessment found no committed secrets; the owner approved the public reporting email and icon licensing. Application behavior and project configuration are unchanged. Local and hosted build/test checks passed. See [verified settings, limitations and publication checklist](OPEN_SOURCE_PREPARATION.md). The repository remains private, PR review is required, and public visibility and App Store publication each require separate explicit authorization.


## Sideways scroll settling — October 28, 2026

Camera fitting now waits for touch release and a 240 ms quiet period, then settles horizontally over 420 ms. Reading paragraphs retain their top position and font size. Supported full-width paragraphs narrow inward from the camera side only after scrolling stops; there is no vertical text-avoidance fallback. New gestures freeze fitting, and Original Layout restores the author layout. A separate simulator-only ActivityKit companion and Debug system-status switch allow review with a real Dynamic Island activity.

Debug/Release builds, 102 browser-layout checks, portable checks and lint passed. The synthetic page was reviewed with the compact island, Original Layout, keyboard/form editing, closed/partial/open poses and rotation. See [verification and remaining limits](SCROLL_SETTLING_2026-10-28.md) for native regression results, screenshots and the exact review matrix. Physical touch/frame-rate/energy profiling, spoken VoiceOver, manual pinch/larger-text coverage and the broader website corpus remain open; simulator success does not close those release gates.

- Reading-position follow-up: reproduced a 24 px upward jump when restoring an offscreen paragraph. Fitting now anchors visible text across reflow and excludes internal scroll corrections from animation interruption. Added browser and native regressions for the paragraph's screen position and partially visible words; see the same validation report for results.

The live news-layout follow-up now handles compact sticky control rows (including closed offcanvas drawers) and local paragraph flow inside deeply nested grid shells. The same live article was inspected with the compact system activity: header controls and paragraph text fitted sideways. A synthetic fixture adds thirteen regressions for links, restoration, repeated settling and visible-word anchoring below sticky page bars. Native verification and CI status are recorded in the [settling report](SCROLL_SETTLING_2026-10-28.md). Clipped scrolling tickers and other unsupported structures may still remain behind the system region.


## Browser productivity upgrades — October 29, 2026

Implemented local unified search, normal-tab workspaces and pins, interactive Peek with same-web-view promotion, native text Reader, and a conservative bundled third-party ad/tracker blocker. Existing glass controls and camera-layout engines are preserved. The feature branch is stacked on PR #4 for owner review; no merge or release is performed.

Debug/Release builds, 62 portable assertions, 118 browser/DOM assertions and the 106-assertion native suite passed. See [feature usage, privacy boundaries, UI evidence and remaining validation](BROWSER_UPGRADES_2026-10-29.md). Full manual pose/accessibility coverage and hardware acceptance remain open; the blocker is a 19-domain baseline and Reader is text-only.


## UX and review follow-up — October 29, 2026

Reworked URL search into a compact keyboard-adjacent palette, replaced the Peek sheet with native context-menu preview/commit animation, and added a clear Website Protection panel with scoped exceptions. Polished tab/library empty states and preserved the existing glass controls. Reviewed all eleven Copilot findings across PRs #4/#5 and fixed the inherited camera-layout CI regression. See [design changes, comment disposition and verification](UX_POLISH_2026-10-29.md). No merge or release is authorized by this work.

## Status bar setting — October 29, 2026

- Page options exposes a persistent **Time, Signal & Battery** toggle in Debug and Release. It controls the system status indicators independently of full-width page mode and also applies in the tab overview.
- Debug and Release simulator builds and 34 native browser checks passed. Closed-display simulator interaction verified the earlier longer label toggled the indicators on and off; the final shorter label could not be visually rechecked after the Mac locked. Hardware, VoiceOver, and the full pose/accessibility matrix remain to be verified.

## Start page and tab appearance — October 29, 2026

Added a native start page with bookmarks, recent visits, a search shortcut and a private-browsing state, plus a locally saved tab-switcher background color and reset. The page uses existing local library data and does not show normal browsing history in private mode. Debug and Release simulator builds, 36 native browser checks, 62 portable checks and 126 layout checks passed. On a closed Duo simulator the start page and color picker were displayed and a color was applied. Physical-device, VoiceOver and full pose/accessibility coverage remain to be verified.

## Tab stack — October 29, 2026

The overview uses a native UICollectionView stack with reusable page previews, continuous depth compression to the left, UIKit momentum and snapping, and upward swipe dismissal. The same layout drives displayed positions and hit testing. Closing follows the finger without a travel cap, projects release velocity, and uses a critically damped animation; reversing downward cancels, and a returning card can be caught again. Cards fit the available height. Existing glass controls, background color, search, workspaces and privacy separation remain. VoiceOver and accessibility text sizes retain the non-overlapping list; Reduce Motion removes depth/parallax and fades committed closes.

The motion follows Apple's public [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/) guidance on momentum, interruption and non-overshooting springs, using public [UICollectionViewLayout snapping](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/targetcontentoffset(forproposedcontentoffset:withscrollingvelocity:)). The depth curve is our implementation, not Apple's unpublished app-switcher formula.

Verification: final Debug/Release simulator and signed-device builds passed, along with 62 portable checks, 126 browser/DOM checks and SwiftLint. Eight motion-policy assertions passed (continuous speed, order, bounds, momentum, cancellation and Reduce Motion). Seven focused native stack checks passed on the final build: selected-tab entry, fractional scrolling, bounded layout work, animated close, successor placement, reduced motion and resize focus. These checks exercise UIKit layout and close animations programmatically, not synthesized touch gestures.

The full native suite did not pass in this run: one attempt timed out in the upgrade/WebKit checks after reenabling content blocking; a second passed the new stack assertions but timed out waiting for the synthetic TLS error. No test expectations or security behavior were weakened. The overview and multiple preview cards were displayed on the closed Duo simulator; the computer-use drag tool returned `noWindowsAvailable`, so touch-driven horizontal scrolling and swipe-up recognition remain unverified. Final development build installation on the owner's iPhone is recorded in the PR. Physical smoothness/frame pacing, spoken VoiceOver, larger-text/keyboard and the complete open/partial/rotated pose matrix remain acceptance work.


## Tab motion correction — October 29, 2026

Removed all tab-preview outlines, including the selected-tab blue border. Card dismissal now animates an app-owned container instead of UIKit's managed cell content view, preserving the finger offset across collection layout. Committed closes travel upward with a non-reversing exit; canceled gestures retain a catchable return animation. Horizontal depth scaling now eases continuously at the foreground boundary while UIKit continues to handle momentum and snapping.

Debug and Release simulator builds, portable checks, browser/DOM tests and strict SwiftLint passed. The focused native stack harness verifies retained drag offset, monotonic upward presentation during repeated layout, one-time removal, successor focus, fractional scrolling, bounded layout work, Reduce Motion and resize focus. Computer Use could not access Simulator in this session, so synthesized touch gestures and physical frame pacing remain unverified. No Safari-parity or full hardware/accessibility acceptance claim is made.

## Start-page review corrections — October 29, 2026

The native start page now has a dedicated bundled blank document. Visibility changes at navigation commit, preserving the start page on failed or canceled provisional requests and recognizing Back/Forward without covering site-owned about:blank content. The underlying web view is hidden from accessibility while the native page is visible. Scroll clearance observes the actual toolbar height and runtime camera lift instead of reserving a fixed 120 points.
## Reader and article fitting follow-up — October 29, 2026

- Replaced Reader’s inset SwiftUI column with a full-screen WebKit viewport using runtime camera geometry. Ordered photos/captions, article-header images and visible headlines are extracted with bounded native validation; private image loading stays in the source profile.
- Body text can fit inside non-scrolling horizontal-overflow shells and normal column-flex article layouts. Actual scrollers, clipped content and unsafe flow changes still fall back.
- Verification and remaining live-site/hardware gaps: [Reader layout report](READER_LAYOUT_2026-10-29.md).
