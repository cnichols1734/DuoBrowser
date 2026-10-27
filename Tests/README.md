# Scroll chrome checks

Run from the repo root:

```sh
mkdir -p work
swiftc DuoBrowser/ScrollChromeState.swift Tests/ScrollChromeStateTests.swift -o work/scroll-chrome-tests
work/scroll-chrome-tests
```

These portable checks exercise the scrolling policy without UIKit: sustained downward/upward movement, small reversals, programmatic scrolling, tap-to-reveal during momentum, short pages, keyboard/accessibility suppression, top/bottom bounce, and fast flings that overshoot the bottom before reporting an intermediate offset.

They do not prove touch behavior, animation quality, VoiceOver behavior, or scroll-indicator placement. Verify those in the running app.
