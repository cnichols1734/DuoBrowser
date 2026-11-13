# Tab recovery and navigation

## Behavior

- Closing a normal HTTP(S) tab offers Undo and saves its address, title, reading position, workspace and pin in a 20-entry Recently Closed list. The list survives relaunch. It is available in Tab options and by holding the Tabs button.
- Immediate Undo retains one normal tab in memory for up to eight seconds, preserving its live page and unsent input. Closing another normal tab, backgrounding, memory pressure, or clearing its recovery record releases it. Pages still loading, capturing camera/microphone, or linked to another window use URL recovery immediately. Retained media playback is suspended until Undo. After release, recovery reopens the saved address; it does not restore submitted requests, unsent form values or the closed tab's back/forward list. The Recently Closed screen explains this limitation. Blank start pages and local developer fixtures are not saved.
- Closing the selected tab chooses the next visible tab, then the preceding tab when the closed tab was last. Reopening uses the original workspace, or Personal if that workspace was deleted. A stale Undo cannot reopen an entry twice, and the 200-open-tab limit is respected.
- Private tabs never enter Recently Closed, and normal recovery is unavailable in private mode. Clearing history removes corresponding closed-page records; clearing all history or Recently Closed writes both archive generations so the backup cannot resurrect removed entries.
- Swipe horizontally across the address capsule to select the next/previous tab within the current workspace and browsing mode. The gesture is confined to browser chrome, rejects vertical drags, and is disabled while editing, while the keyboard is up, or with expanded accessibility controls. The Tabs context menu and named accessibility actions provide equivalent commands. Switching uses existing live web views.
- Hold Back to choose from the current tab's last 30 previous pages. Stale menu actions validate the web view and history item before navigating.
- The Undo notice lasts eight seconds; it stays until dismissed for VoiceOver or accessibility text sizes. Recently Closed remains available after the notice disappears.

## Verification

Portable recovery checks cover address validation, credential rejection, duplicate IDs, metadata limits and the 20-entry bound. Native integration coverage exercises normal persistence, stale Undo, private exclusion, adjacent selection, quick navigation, original/deleted workspaces, pins and deletion semantics. Debug and Release simulator builds passed with Xcode 27.2 / iOS 27.2 SDK, retaining the iOS 27.1 deployment target. All 202 portable assertions, 186 browser assertions, SwiftLint 0.65.1 strict checks and repository checks passed. Native iOS 27.1 checks passed: Setup 24, Reddit 29, TabStack 24, core 93, upgrades/recovery 90, settling 34, cookie write/read 2 each and memory 13.

Manual native interactions on the isolated DuoBrowser-TabRecovery-QA simulator verified closing a tab, pressing Undo, restoring its live page/input, invoking the Next Tab accessibility action, and opening Recently Closed. Inspected the recovery sheet closed, open, partially folded, rotated, dark and at maximum accessibility text size. The dark-text pass caught inherited button tint; recovery rows now use the same plain button style as Library. Screenshots use synthetic pages only.

CUA coordinate dragging reported `noWindowsAvailable`, while native accessibility actions worked. Actual horizontal swipe recognition and Back long-press selection are still unverified; native switch policy, stale identity checks and accessible equivalents are implemented. Keyboard/pinch interaction, a full spoken VoiceOver pass, Reduce Motion with the new notice, and live occlusion changes remain gaps for the new controls.

Physical touch, full spoken VoiceOver, battery/endurance, and hardware folding remain unverified. URL-based recovery does not promise form-state or full session recovery.

## Follow-up review

Clear Recently Closed now checks the durable replacement result, preserves rows for retry after a failed write, and displays a failure alert. Pages that requested camera/microphone/location permission use URL recovery immediately, avoiding retention during an unresolved system permission prompt. A retained Undo page now rejects new navigation and permission prompts; detached pages already have no native presenter for JavaScript dialogs. Additional native assertions cover the missing presenter, canceled confirm dialog/navigation, storage failure and retry. Debug build, portable checks, SwiftLint and repository checks passed for this follow-up; focused native revalidation is pending the coordinated simulator slot.

## Copilot follow-up — November 12

Undo's rendered height and the stack's 8-point gap now contribute to WebKit's
obscured-content inset and camera-aware control lifting. Dismissal removes the
reservation. Its ordinary eight-second lifetime is computed from `closedAt`, so
profile switches and view recreation do not restart it. VoiceOver and accessibility
text sizes retain the notice until explicit dismissal. Closed-record validation
and close capture use the same `WebAddress` contract as reopening.

Eight added portable URL-boundary/elapsed-time checks pass (239 portable checks
before merging the current blocker update), as do strict SwiftLint and Debug.
Three added native checks measure maximum-text notice height, verify a synthetic
fixed footer clears it, and verify dismissal restores the original inset. These
runtime checks are pending coordinated simulator access; no new hardware or
spoken VoiceOver evidence is claimed.


## Undo overview card follow-up

The owner reproduced a real-device defect: close a tab, tap Undo, then reopen the
overview; its page returns but its card is missing and cannot be closed again.
`BrowserSession` restores the original model and WKWebView correctly. The card's
completed exit transform (or zero opacity under Reduce Motion) survived because
its UUID was unchanged. An offscreen overview can also coalesce close and Undo
into the same ID array and selection, bypassing the old update path entirely.

`TabStackController` now restores idle card motion before that unchanged-ID return
and when configuring the same ID again. It preserves the card currently being
dragged, committed exits and active return animations. No page/session restoration
logic changed.

The new native regression uses the real session close/Undo operations, both motion
modes and both coalesced/applied removal snapshots. Before the fix, model/view
identity and draft checks passed but card visibility/hit testing failed. With the
fix, all 16 checks passed, including a usable zoom source and closing the restored
tab again exactly once. Existing TabStack checks bring the batch to 40. Local
receipts: `work/undo-overview-baseline.log`, `work/undo-overview-corrected.txt` and
`work/tabstack-undo-corrected.txt` in the complete setup worktree. The regression
undoes immediately after the removal snapshot, keeping decorative animation waits
outside the live Undo window.

The owner separately requested removal of the unstable download authentication
retry/source-closure CI scenarios after device testing. Four assertions and their
authentication-specific diagnostics were removed; Downloads49 remains, and
production download behavior is unchanged. Authenticated retry after source
closure is no longer established by CI. Full-stack validation and device
installation are recorded separately; the simulator checks are not a hardware
motion or spoken VoiceOver claim.
