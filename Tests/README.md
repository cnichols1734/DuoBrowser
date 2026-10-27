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

The 12 archive checks cover stable IDs and selection, ordered restoration, duplicate IDs, missing selections, invalid/unsafe destinations, and restoring 100 tab records without truncation.

These portable tests do not prove UI interaction, live tab lifecycle, animation frame rate, native accessibility, or glass appearance. Verify those in the running app; see `docs/VALIDATION.md` for results and gaps.

## Automatic layout regression fixtures

`PageLayoutTests.cjs` exports `runPageLayoutTests(page, source)` for a Playwright browser runner. Supply a fresh Playwright page and the exact bundled `DuoBrowser/PageLayout.js` source. All requests are intercepted and fulfilled with synthetic HTML. Desktop Chromium supplies zero safe-area env values, so only the probe's computed values are substituted. DOM layout, CSS cascade, observers, and rollback run in the real browser.

With Playwright and its Chromium binary already available in your test environment:

```sh
node Tests/PageLayoutTests.cjs
```

The app has no Playwright dependency. The same exported suite ran through the available browser tool. All 24 cases passed, covering unrelated origins, generic HTML and custom elements, body/root-wrapper padding, both header variants, restoration of newer author styles, ordinary article spacing, header movement, overflow, failed expansion, scan budgets, ambiguity, subframe isolation, editing/zoom deferral, hydration, SPA replacement, disable cancellation, side changes, convergence, and header actions.

The original 16-case YouTube suite is retained in Git history; its regression scenarios are incorporated here. Native WebKit checks use the bundled viewport lab, which intentionally declares safe-area body padding and an independently padded fixed header without any site-specific markup. The lab reports actual content width and keeps its header action and input available for rollback/focus checks. Chromium fixtures do not establish native pinch, hardware, or universal website compatibility.
