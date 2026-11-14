# Premium page controls — November 14, 2026

## Implemented

- Replaced the long mixed Page options menu with a native, scrollable controls sheet. Share, Save, Find and the existing Reader entry are first; website layout/protection state is followed by tab actions and browser destinations.
- Page identity and Private Browsing are explicit. Protection status comes from the existing live model; no blocked-request counts or external-provider activation claims are invented.
- Native medium/large sheet presentation expands to large at accessibility sizes. Quick-action rows become full-width labeled controls at accessibility sizes; the content remains scrollable in short/rotated/folded layouts.
- Actions queue until the controls sheet finishes dismissing, avoiding overlapping Share/Find/Save/Reader/settings presentation. Queued page actions capture tab, privacy and document identity; navigation to the same address still invalidates them. Browser/tab organization actions are not unnecessarily invalidated by same-tab navigation.
- Retained the existing Reader source and behavior. Returning from follow-up SwiftUI surfaces restores accessibility focus to Page options.
- Attached the tabs workstream's interactive swipe modifier to the address capsule while retaining accessible Next/Previous actions.
- Website Protection now stays scoped to the original host/tab and dismisses after a host or selected-tab change. Library's section selector has its own native spacing; workspace counts use singular/plural copy.
- Website Protection links to Other Blocking Apps, a concise native help page with official setup links for AdGuard DNS, Adblock Plus DNS, Wipr 2 Filtr and 1Blocker's in-app tracker filter. It explicitly distinguishes Safari-only extensions and limits, without enable switches or active-state claims.
- Consistent inline Settings/Privacy titles and navigation-style Appearance selection. Settings exposes Other Blocking Apps without requiring an open website; Privacy and Website Protection return accessibility focus to the launching row.
- Website Data distinguishes loading from removal, presents a useful search-empty state, and makes the whole domain row tappable. Filter Update Now has a full 44-point target and combined accessibility status.
- Downloads uses a 44-point preview target, plain readable filenames while a file cannot be previewed, explicit cancellation progress, cleared stale removal confirmations, and private empty-state guidance. Transfer/storage behavior is unchanged.

## Verification at workstream handoff

- `swiftc -frontend -parse` passed for BrowserToolbar, PageControlsView, WorkspaceView, BrowserLibrary and NativePageControlsChecks.
- Targeted `git diff --check` passed for this workstream's files.
- Added `premiumControlsChecks()` with nine native assertions: original scope, replacement normal/private rejection, live WebKit/document retention, draft retention, no action merely from viewing/dismissing, real same-address navigation invalidation, continued validity of tab/browser actions, and fresh-document acceptance.
- The root workstream owns Xcode project registration, the integrated Debug/Release builds, native execution, simulator screenshots and final verification. These assertions are added but are not claimed passing until that integrated receipt exists.

## Remaining checks

Exercise the actual controls → Share/Save/Find/Reader/Website Settings/Protection/Library/Downloads/Workspaces/Settings actions after integrated build, including cancellation and stale navigation. Inspect regular iPhone and Duo closed/open/partially folded/rotated layouts, large text, Reduce Motion and VoiceOver focus. Pinch/fold/web-form continuity, physical touch/energy and fully spoken VoiceOver remain separate acceptance checks.

[Installed blocker compatibility research](extension-compatibility.md) records ten representative products, public SDK boundaries, and real system-level filtering alternatives. No arbitrary installed Safari extension support is claimed or implemented.

## Protection presentation-scope review follow-up

Copilot correctly identified that a plain stored `WebsiteSettingsScope` in `BrowserProtectionView` could be recaptured when SwiftUI rebuilt sheet content after navigation. The scope now lives in `@State`, initialized once per presentation identity. Its toggle, reload and exception mutations also guard the retained host/tab before acting.

Four native regressions extend `premiumControlsChecks()` from nine to thirteen assertions. They mount the actual protection view, use its rendered toggle binding, navigate the underlying WebKit document from the loopback IP to `localhost`, and replace the hosting controller's root value with a newly initialized view while preserving presentation identity. The replacement must retain the original scope, stay stale/disabled and reject writes to the new host. A Debug-only render probe observes the view's installed state and binding; it is excluded from Release. Swift parsing and targeted patch checks passed at handoff; the coordinating workstream records the integrated native result.
