# Premium start page — November 14, 2026

The start page is now a navigation canvas built around the current workspace, a direct search invitation, Favorites, and returning to already open normal tabs. It does not introduce Reader or Reading List surfaces.

## Behavior

- The workspace selector switches to an existing normal workspace through the existing session API. The open-tab section shows up to three recent, valid normal destinations in that workspace, excluding the current tab. Selecting one returns to the existing tab rather than creating a copy.
- A regular-text Favorites ribbon shows up to twelve sites without pushing continuation below multiple grid rows; accessibility text sizes use an adaptive grid. All Favorites remain available through Edit. The native editor supports adding/editing a favorite, changing order, and removing the favorite flag while retaining the Library bookmark. Reorders reject stale/partial ID sets and roll back on archive failure.
- Adding an address that is already bookmarked preserves its stable ID, folder, date, and other metadata. A supplied name updates the title; an omitted name retains the saved name.
- Customize independently shows/hides Favorites, Open Tabs, and Recent Sites. The defaults show Favorites and Open Tabs. Recent Sites is optional, deduplicates hosts, omits sites already in Favorites, and displays a host instead of a path/query.
- Private starts have a separate heading, search invitation, and explanation. They never construct the normal Favorite icon views, show normal continuation/history surfaces, or offer normal start customization. Favorite mutation helpers reject private mode.
- Section clearance uses active runtime system occlusions, including system-provided margins, and updates when scrolling or geometry changes. Clearance applies to the affected section instead of a permanent whole-page camera rail. The baseline measurement excludes its own vertical padding to prevent repeated bottom-clearance growth.
- Search opens the existing keyboard-adjacent command overlay. Native SF typography, larger text, system appearance, and the existing wallpaper are retained.

## Verification

- **23 portable policy checks passed**, compiled with warnings as errors. Coverage includes private projection isolation, current-workspace scoping, unsafe/credential-bearing destination rejection, recent-site host deduplication, stale reorder rejection, metadata-preserving reorder, favorite URL validation, and promoting an existing folder bookmark without losing metadata.
- All new Swift sources and native tests passed a Swift parser check.
- `NativePremiumStartChecks.swift` adds 18 native checks for durable favorite mutation, failure rollback, private mutation guards, existing folder-bookmark promotion, stable/reversible reserved-region clearance, and rendered normal/private section presence. **Execution is pending the integrated native run.**
- Debug-only `premiumStartPreview()` seeds an isolated archive and nonpersistent profile for visual review. Launch with `--browser-checks --premium-start-preview`, optionally adding `--premium-private-preview`. Favorite `.example` hosts intentionally exercise the letter fallback; loopback destinations provide the synthetic open tabs.

## Remaining validation

Integrated Debug/Release builds, native execution, and screenshots across closed/open/partially folded, rotation, larger text and appearance belong to the parent integration receipt. Physical touch, spoken VoiceOver, endurance, and battery results are not established by these source/portable checks.
