# Browser behavior checks

Run from the repo root:

```sh
mkdir -p work
swiftc DuoBrowser/ScrollChromeState.swift Tests/ScrollChromeStateTests.swift -o work/scroll-chrome-tests
work/scroll-chrome-tests
swiftc DuoBrowser/TabArchive.swift Tests/TabArchiveTests.swift -o work/tab-archive-tests
work/tab-archive-tests
```

The 21 scrolling checks cover continuous progress, settling, direction reversal, small jitter, programmatic movement, tap-to-reveal during momentum, short pages, keyboard/accessibility suppression, elastic bounce, and fast overshooting flings.

The 12 archive checks cover stable IDs and selection, ordered restoration, duplicate IDs, missing selections, invalid/unsafe destinations, and restoring 102 tab records without truncation.

These portable tests do not prove UI interaction, live tab lifecycle, animation frame rate, native accessibility, or glass appearance. Verify those in the running app; see `docs/VALIDATION.md` for results and gaps.

## Automatic layout regression fixtures

`PageLayoutTests.cjs` exports `runPageLayoutTests(page, source)` for a Playwright browser runner. Supply a fresh Playwright page and the exact bundled `DuoBrowser/PageLayout.js` source. All requests are intercepted and fulfilled with synthetic HTML. Desktop Chromium supplies zero safe-area env values, so only the probe's computed values are substituted. DOM layout, CSS cascade, observers, and rollback run in the real browser.

With Playwright and its Chromium binary already available in your test environment:

```sh
node Tests/PageLayoutTests.cjs
```

The app has no Playwright dependency. The suite has 25 cases covering unrelated origins, generic HTML and custom elements, body/root-wrapper padding, both header variants, restoration of newer author styles, ordinary article spacing, header movement, overflow, failed expansion, scan budgets, ambiguity, subframe isolation, editing/zoom deferral, hydration, SPA replacement, disable cancellation, side changes, convergence, header actions, and deferral during touch and momentum scrolling.

The original 16-case YouTube suite is retained in Git history; its regression scenarios are incorporated here. Native WebKit checks use the bundled viewport lab, which intentionally declares safe-area body padding and an independently padded fixed header without any site-specific markup. The lab reports actual content width and keeps its header action and input available for rollback/focus checks. Chromium fixtures do not establish native pinch, hardware, or universal website compatibility.

## Production data / policy checks

```sh
swiftc DuoBrowser/BrowserData.swift DuoBrowser/TabArchive.swift Tests/BrowserDataTests.swift -o work/browser-data-tests
work/browser-data-tests
```

These cover host/port/search parsing, unsafe schemes/credentials, bounded archives, unknown versions, corrupt-primary recovery, deletion of both history generations and invalid scroll positions. `CameraAvoidanceTests.cjs` supplies 14 real-layout checks via `runCameraTests(page, source)`: free destinations, hit testing, rollback, author styles/transforms, occupied space, editing, zoom, geometry conversion and mutation convergence. Its CommonJS export is the function itself, as is `PageLayoutTests.cjs`.

## Scroll settling and system occlusion

`CameraSettlingTests.cjs` adds 50 synthetic Chromium checks: horizontal animation positions, no added top gap or glyph scaling, stable line rectangles during scrolling, natural paragraph spacing, reading offset, live links, held touch/momentum, interruption, repeated settling, growing/removed regions, Reduce Motion, VoiceOver policy, editing/selection/zoom deferral, complex-layout fallback, cancellation, invalid geometry, observer convergence, author edits, privacy, grouped controls, hit testing, scan limits, left-side fitting, partially visible paragraphs, full-width-island fallback, removal of offscreen fitting, anchored animation frames, reverse scrolling, site smooth-scroll CSS and visible-word anchoring through width changes.

`NestedNewsTests.cjs` adds thirteen checks using `/nested-news`: compact sticky headers with closed offcanvas navigation, nested grid article shells, link behavior, repeated settling, restoration, and visible-word anchoring below sticky site chrome.

The native harness's `--browser-checks --settling-checks` mode runs 30 checks against the exact bundled script in WKWebView's isolated content world. It writes `Library/Caches/CameraSettlingChecks.txt`; the normal `scripts/native-checks.sh` run includes it. Its synthetic region updates and pointer events establish layout behavior, not physical touch or system geometry reporting.

For actual system occlusion, build the separate [Island Lab companion](IslandLab/README.md), start its Live Activity and return to the browser's loopback `/settling` fixture. The companion is intentionally outside the shipping app. Results and remaining manual/hardware coverage belong in the [settling validation report](../docs/SCROLL_SETTLING_2026-10-28.md).

## Native WebKit integration harness (Debug only)

`NativeBrowserChecks.swift` is compiled only in Debug. `--browser-checks` replaces the normal app view with a harness using synthetic loopback fixtures, isolated defaults and temporary archives. It does not read normal history or modify default-profile cookies. The persistent-cookie test uses a separate named WebKit data store and clears its data after verification.

1. Start `python3 Tests/native_fixture_server.py` (binds only `127.0.0.1:8765`). For the fail-closed TLS check, generate a temporary self-signed fixture certificate and start the second loopback server in another terminal:

   ```sh
   openssl req -x509 -newkey rsa:2048 -nodes -keyout work/fixture-key.pem -out work/fixture-cert.pem -days 1 -subj '/CN=localhost' -addext 'subjectAltName=IP:127.0.0.1'
   python3 Tests/native_fixture_server.py work/fixture-cert.pem work/fixture-key.pem
   ```

   Do not trust or install this certificate; rejection is the expected test result.
2. Build/install the Debug app on the **DuoBrowser QA** simulator (choose its identifier with `xcrun simctl list devices`).
3. Launch `xcrun simctl launch <your-test-simulator-id> dev.local.DuoBrowser --browser-checks` and inspect the rendered results. Its receipt is in the app data container at `Library/Caches/NativeBrowserChecks.txt`. A rerun requires terminating the running app first; check that the receipt has changed.
4. To verify disk persistence across actual process termination, launch with `--browser-checks --persistent-cookie-write`, wait for `Library/Caches/PersistentCookieChecks.txt`, terminate the app, then launch with `--browser-checks --persistent-cookie-read`. The read phase verifies cookie/localStorage retention and clears that test profile.
5. Optional live smoke pass: `--browser-checks --site-checks`. This visits only the eight owner-supplied public sites in an ephemeral profile and records viewport/overflow/scroll metrics plus navigation errors in `Library/Caches/LiveSiteChecks.txt`. It never logs in or submits forms. A “loaded” record is a navigation smoke result, not a functional or authenticated-site pass.
6. Relaunch without arguments to return to the normal browser. Stop the fixture server when finished.

Native checks cover private cookie/localStorage boundaries, private archive exclusion and teardown, live form preservation, supplied-configuration POST windows/opener/close, exactly-once dialog cancellation, fixed-footer obscuration, protected interactive tabs, static-page reclamation/scroll restoration, crash-recovery messaging, download filename sanitization and lazy cold restoration. The process-termination error callback is invoked directly for its message test; that assertion does not simulate an actual WebKit crash. UI tests of alerts, find, share, library, file export/import and fold/pose are recorded in the production implementation report.

The normal UI remains available in Debug without test arguments. The harness and developer menu cannot be invoked in Release. No test result substitutes for signed-device password/passkey, hardware permissions, assistive-technology or performance testing.

## Memory stress pass (Debug only)

With the loopback fixture server running, terminate the QA app and launch it with `--browser-checks --memory-checks`. The result is `Library/Caches/MemoryChecks.txt` in that app's data container. The run uses isolated temporary state: 16 static reading tabs plus four unsent forms, native snapshots, an injected memory-warning notification, a reclaimed-page revisit, closing 19 tabs, and cold restoration of 200 records. It asserts the 8 MiB raster budget, 640-pixel dimensions, preview clearing, protected forms, static recovery and one-live-view cold startup. The normal native suite also checks actual WKWebView deallocation, inline-event protection, DOM-query isolation and native control clearance for top/bottom/removed occlusion geometry.

Reported `previewBytes` counts CGImage decoded raster bytes. `appFootprint` is the app process's physical footprint, excluding WebKit child processes and some shared surfaces. Neither is a complete device/browser memory measurement. Simulated warnings are not actual jetsam. Compare equivalent simulator pose/content; do not treat these results as physical battery/thermal or total-memory claims. See `docs/ACCESSIBILITY_MEMORY_2026-10-27.md` for the before/after measurements and native accessibility checks.

## Reproducible community checks

Run `bash scripts/check.sh` for the portable Swift assertions, Swift parsing, JavaScript syntax and repository/dependency checks. Install the pinned development-only test dependency with `npm ci --ignore-scripts`, install Chromium with `npx --no-install playwright install chromium`, then run `npm test` for all three layout suites. Run SwiftLint 0.65.1 with `swiftlint lint --strict --config .swiftlint.yml`. No application dependency was added.

`bash scripts/native-checks.sh` builds Debug, creates an isolated Duo simulator, starts local fixtures, runs native/persistence/memory checks and checks fresh receipts before deleting the test simulator. It fails if the required runtime or ports are unavailable. `--skip-build` uses an already-built Debug app in `DerivedData`; `DUO_DERIVED_DATA` overrides that directory. For a deliberately selected existing test simulator, set `DUO_TEST_DEVICE`; the script leaves that device and its normal browsing data intact and returns to the normal app afterward. Do not point it at a personal device.

GitHub CI uses the public-preview `xcode-27` hosted runner and selects Xcode 27.1 explicitly. The published runner inventory currently includes the 27.1 Duo simulator. Runner availability can change; missing SDK/runtime support fails the native job and the required gate rather than silently skipping tests. Portable tests still help diagnose failures, but are not a substitute for the native build. Never fall back to a credential-bearing self-hosted runner.

CI validates workflows with actionlint, checks pinned tool digests, scans full Git history with redacted Gitleaks output, and audits the locked npm graph. No release credentials or browsing artifacts are uploaded. SwiftLint initially enables a narrow set of correctness rules; it does not impose a wholesale format rewrite. Patch whitespace is checked separately.

## Browser productivity checks

`npm test` includes the 18-check bounded Reader extraction suite. The native script also runs `--browser-checks --upgrade-checks` and requires 40 passing assertions in `Library/Caches/UpgradeChecks.txt`. This covers workspace/pin restoration, local search and private boundaries, Reader cancellation and untouched forms/scroll, Peek lifetime and same-view promotion, and actual WKContentRuleList blocking/exception/first-party behavior using loopback fixtures. A Debug-only host substitution makes the production rule flags testable without external ad requests. No normal browsing data is used.
