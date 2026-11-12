# Downloads review — November 12, 2026

Review scope: session-owned downloads, native list, file preview/export, authenticated retry and retention. No merge or release is implied.

## Behavior

Page options → Downloads provides named transfers, real byte progress, individual Cancel/Retry, Quick Look, Save to Files and explicit removal. Successful transfers no longer interrupt the current page with an exporter. Dismissing export retains the app copy. Normal files survive relaunch; private files stay isolated and are removed on final private-tab closure. Requests and resume tokens stay in memory and inside the original WebKit profile.

The list uses system typography, separators and navigation, with 44-point controls and a simpler layout at accessibility text sizes. A small Page options indicator announces active or unseen downloads. File errors explain the recovery action; failed deletion never silently hides the retained file. Changed files or files recovered from damaged metadata are explicitly unverified, and actual on-disk bytes count toward admission and completion limits.

## Automated evidence

- Portable checks: 220 assertions passed, including 28 download-store assertions covering path/bidi/UTF-8 safety, manifest bounds, symlinks, persistence, deletion failure, orphan recovery and sparse-file quota accounting.
- Browser/DOM checks: all 186 assertions passed.
- SwiftLint strict: zero violations.
- Debug simulator build: passed with Xcode 27.2 / iOS 27.1. Integrated Debug and Release simulator builds passed before the final scoped policy-error suppression. The final 37-check native receipt and build confirmation for that small follow-up are delegated to the combined Settings branch validation.

The first native run exposed a source-tab closure failure. The corrected implementation retains the source WKWebView, avoids stopping its active download when the normal tab closes, cancels further navigation and suspends that retained page's media. The corrected native suite passed all 34 checks, including the separate last-normal-tab case with no loaded replacement WKWebView. A second real finding was that a fresh retry web view lost cookie context: GET restart now uses the unchanged original page, with native resume tokens preferred. Authenticated retry passed after that correction.

- Native Downloads: all 34 assertions passed on the existing iOS 27.1 Duo QA simulator. The complete standalone regression run passed: Setup 24, Reddit 29, Tabs 19, Core 93, Upgrade 71, Settling 34, cookie persistence 4 and Memory 13. After stacking on tabs/library/blocking, the expanded 36-check download suite passed, including direct attachment and inline-document navigation. Integrated portable checks passed 277 assertions; strict lint reported zero violations.

## Interaction evidence

`before-menu.png` records the prior page-options download experience on the shared QA simulator (the Library feature was also installed on that baseline). Manual Device Hub interaction confirmed:

- Direct attachment becomes a named file; native Quick Look displays its exact synthetic text.
- Save to Files opens the native destination picker. Invoking its Cancel accessibility action dismisses it; the retained row remains available for preview/export.
- The slow fixture shows actual percentage and bytes. Individual Cancel changes only that row to Canceled; Retry restarts progress and reaches completed status. A same-named prior file remains intact.
- Downloads stays usable through open, partial-fold, closed and rotated layouts. Maximum accessibility text hides decorative icons and keeps controls reachable in the scrollable native list. Dark appearance and Reduce Motion were exercised; accessibility exposes filenames, progress, cancel, retry and per-file actions.
- Simulator restored to closed portrait, Light appearance, Text Size 3, Reduce Motion off, Capture Keyboard off. No transfer was active at handoff.

Screenshots: [completed files](completed-closed.png), [retried progress](retry-progress.png), [open/dark/maximum text](open-dark-large-text.png).

Manual testing also found two policy issues: displayable server attachments previously rendered as pages, and successful conversion showed a misleading “Frame load interrupted” banner. The attachment correction passed two new native checks (36 total). The follow-up scopes suppression of the observed NSError domain/code to a download policy this model actually requested; its 37th assertion also verifies an unrelated same-code error still surfaces. That final assertion awaits the combined-stack run.

## Remaining device checks

Physical touch/energy/endurance, iOS suspension/background behavior, signed-device Files providers, full spoken VoiceOver and arbitrary authenticated sites remain unverified. There is no claim of universal resume support, Safari parity or App Store approval.


## Final source review follow-up

Combined-stack review found that GET retry attached its replacement download without the originating tab ID. Closing that tab could therefore stop its web view; pending retries had the same gap. The fix retains the pending web view and owner until WebKit returns a download, carries ownership into the active transfer, and clears retry context when the source closes. Resume-token transfers remain owned by the dedicated session web view. Generation checks still discard canceled/removed/private-session callbacks before consuming pending state.

Four new native assertions exercise authenticated GET restart followed by immediate source closure and closure after progress begins. Both explicitly expire Undo so its eight-second retention cannot hide lifecycle failure. The suite now requires 41 download checks; the combined validation run owns execution. Portable checks and strict lint were rerun for this follow-up.


## Copilot review follow-up

- GET restart now binds the weak originating BrowserModel and its document generation as well as the web view and URL. A new provisional document proactively clears old GET eligibility; reload and away/back cannot recover it merely by returning to the same address. Opaque WebKit resume remains available independently when supplied. Two native regressions perform a real reload and away/back navigation, force the no-token GET path and verify that it starts no work. The combined suite now requires 43 Downloads assertions; execution belongs to final combined validation.
- Removal checks the UUID directory entry itself for a symbolic link before the existence check that follows links. Four added portable checks cover a dangling link's quota block, actual unlink/recovery removal, restored admission and preserving a live link's external target. All 32 download-store assertions pass, alongside strict lint and source parsing.

Reviewed threads: [document-generation binding](https://github.com/cnichols1734/DuoBrowser/pull/21#discussion_r4557087538), [dangling-link removal](https://github.com/cnichols1734/DuoBrowser/pull/21#discussion_r4557087587).
