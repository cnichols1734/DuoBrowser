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

## YouTube layout regression fixtures

`YouTubeLayoutTests.cjs` exports `runYouTubeLayoutTests(page, source)` for a Playwright browser runner. Supply a fresh Playwright page and the exact bundled `DuoBrowser/YouTubeLayout.js` source. All requests are intercepted and fulfilled with synthetic HTML; these tests send no traffic to YouTube. Desktop Chromium supplies zero safe-area env values, so only the probe's computed values are substituted in the fixture. DOM layout, CSS cascade, observers, and rollback run in the real browser.

With Playwright and its Chromium binary already available in your test environment:

```sh
node Tests/YouTubeLayoutTests.cjs
```

The app has no Playwright dependency. In this pass, the same exported suite ran through the available Playwright browser tool. All 16 cases passed: width gain/header preservation, both header variants, restoration of newer author styles, ordinary padding, unsafe header fallback, failed expansion rollback, origin/frame isolation, contenteditable, disable cancellation, late hydration, SPA replacement, input preservation, zoom deferral, side/pose changes, and convergence. Native WebKit testing remains necessary for actual CSS env geometry and media behavior.
