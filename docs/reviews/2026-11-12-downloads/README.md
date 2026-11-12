# Downloads review — November 12, 2026

Review scope: session-owned downloads, native list, file preview/export, authenticated retry and retention. No merge or release is implied.

## Behavior

Page options → Downloads provides named transfers, real byte progress, individual Cancel/Retry, Quick Look, Save to Files and explicit removal. Successful transfers no longer interrupt the current page with an exporter. Dismissing export retains the app copy. Normal files survive relaunch; private files stay isolated and are removed on final private-tab closure. Requests and resume tokens stay in memory and inside the original WebKit profile.

The list uses system typography, separators and navigation, with 44-point controls and a simpler layout at accessibility text sizes. A small Page options indicator announces active or unseen downloads. File errors explain the recovery action; failed deletion never silently hides the retained file. Changed files or files recovered from damaged metadata are explicitly unverified, and actual on-disk bytes count toward admission and completion limits.

## Automated evidence

- Portable checks: 220 assertions passed, including 28 download-store assertions covering path/bidi/UTF-8 safety, manifest bounds, symlinks, persistence, deletion failure, orphan recovery and sparse-file quota accounting.
- Browser/DOM checks: all 186 assertions passed.
- SwiftLint strict: zero violations.
- Debug simulator build: passed with Xcode 27.2 / iOS 27.1. Final Release and manual UI verification are still pending.

The first native run exposed a source-tab closure failure. The corrected implementation retains the source WKWebView, avoids stopping its active download when the normal tab closes, cancels further navigation and suspends that retained page's media. The corrected native suite passed all 34 checks, including the separate last-normal-tab case with no loaded replacement WKWebView. A second real finding was that a fresh retry web view lost cookie context: GET restart now uses the unchanged original page, with native resume tokens preferred. Authenticated retry passed after that correction.

- Native Downloads: all 34 assertions passed on the existing iOS 27.1 Duo QA simulator. The complete native regression run is in progress.

## Interaction evidence

`before-menu.png` records the prior page-options download experience on the shared QA simulator (the Library feature was also installed on that baseline). Final feature screenshots and exercised interactions are recorded below after execution.

## Remaining device checks

Physical touch/energy/endurance, iOS suspension/background behavior, signed-device Files providers, full spoken VoiceOver and arbitrary authenticated sites remain unverified. There is no claim of universal resume support, Safari parity or App Store approval.
