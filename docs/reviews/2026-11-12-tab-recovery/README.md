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
