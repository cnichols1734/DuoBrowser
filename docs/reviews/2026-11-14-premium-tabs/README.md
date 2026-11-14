# Tabs interaction refinement — November 14, 2026

## Implemented behavior

- Search Tabs is visible at the top of the overview. Workspace/private identity and the tab count remain explicit.
- The existing native thumbnail grid is preserved. A remembered List option provides a compact alternative; VoiceOver and accessibility text sizes continue to use a list.
- Select mode supports multi-selection, filtered Select/Deselect All, confirmed batch closure and normal-workspace moves. Selection is cleared on profile/workspace changes and pruned when tabs disappear. Grid close swipes are disabled while selecting.
- List selection mode exposes native drag reordering. Grid/list context menus provide Move Earlier/Later. Reordering preserves pinned-first order, model identity, live WKWebViews and selection; stale, incomplete and duplicate order snapshots are rejected.
- Failed normal-session writes roll reordering and batch moves back before reporting failure. The overview shows a short save error and keeps a failed move's selection available for retry. Synthetic primary-write failure injection verifies rollback and the unchanged durable archive.
- Swiping the address capsule follows the finger with an adjacent tab preview. A validated release selects the existing neighbor in the same workspace/private profile. Cancellation returns the same live page. Profile/selection changes, backgrounding, presentation and changed view bounds cancel temporary presentation. No background page is activated merely to display a preview.
- A new swipe can catch an active snap-back at its current presentation position rather than being ignored or snapping to a new origin. The first native integration run exposed this boundary: model transforms already held their final values while the cancellation animator was still active. The production gesture now interrupts that animator and carries its current offset into the next release decision; an explicit native regression checks interruption, continuity and commitment.
- Reduce Motion uses opacity rather than a moving page. Existing accessible Previous/Next Tab actions remain available. List mode uses a cross-dissolve when entering/leaving the overview because it has no thumbnail zoom source.

## Verification

Swift parsing passed for the modified tab/session/presenter sources and the new native test extension. Integration builds, simulator interaction and native execution are recorded by the coordinating review after the combined source is ready.

`Tests/NativePremiumTabsChecks.swift` adds synthetic native checks for model order, stale/duplicate updates, pin grouping, layout persistence, source identity/draft retention, interactive swipe cancel/commit, pose-size cancellation, Reduce Motion, workspace moves, batch closure and private archive/scope isolation. It uses an isolated profile/archive and the existing loopback form fixture.

## Remaining acceptance

The native check drives production gesture events and UIKit presentation directly; actual finger recognition and the visual feel of swiping require simulator interaction and owner device testing. Physical touch, energy, long-running many-tab behavior and spoken VoiceOver acceptance are not established by source parsing or synthetic assertions. Cold restoration still restores addresses and best-effort reading positions, not arbitrary page forms or full navigation histories. Explicitly closing multiple tabs discards their unsaved website input after confirmation; Recently Closed remains address-based recovery.
