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
