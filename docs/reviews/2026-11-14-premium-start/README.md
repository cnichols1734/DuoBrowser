# Premium start page — November 14, 2026

The start page is now a navigation canvas built around the current workspace, a direct search invitation, Favorites, and returning to already open normal tabs. It does not introduce Reader or Reading List surfaces.

## Behavior

- The workspace selector switches to an existing normal workspace through the existing session API. The open-tab section shows up to three recent, valid normal destinations in that workspace, excluding the current tab. Selecting one returns to the existing tab rather than creating a copy.
- A regular-text Favorites ribbon shows up to twelve sites without pushing continuation below multiple grid rows; accessibility text sizes use an adaptive grid. All Favorites remain available through Edit. The native editor supports adding/editing a favorite, changing order, and removing the favorite flag while retaining the Library bookmark. Reorders reject stale/partial ID sets and roll back on archive failure.
- Adding an address that is already bookmarked preserves its stable ID, folder, date, and other metadata. A supplied name updates the title; an omitted name retains the saved name.
- Customize independently shows/hides Favorites, Open Tabs, and Recent Sites. The defaults show Favorites and Open Tabs. Recent Sites is optional, deduplicates hosts, omits sites already in Favorites, and displays a host instead of a path/query. Its bounded lookup stops when enough unique sites are collected. A data-change projection subscribes only while the section is visible in normal mode, so scroll updates do not rescan history.
- Private starts have a separate heading, search invitation, and explanation. They never construct the normal Favorite icon views, show normal continuation/history surfaces, or offer normal start customization. Favorite mutation helpers reject private mode.
- Section clearance uses active runtime system occlusions, including system-provided margins, and updates when scrolling or geometry changes. Clearance applies to the affected section instead of a permanent whole-page camera rail. A useful horizontal lane keeps the actual content beside a region; remaining collisions move the section's content below the obstruction with top padding that expands native scroll content. The baseline excludes its own displacement to keep the layout stable. Physical UIKit left/right exclusions map explicitly to SwiftUI leading/trailing for the current layout direction.
- Search opens the existing keyboard-adjacent command overlay. Native SF typography, larger text, system appearance, and the existing wallpaper are retained.

## Verification

- **26 portable policy checks passed**, compiled with warnings as errors. Coverage includes private projection isolation, current-workspace scoping, unsafe/credential-bearing destination rejection, recent-site host deduplication, stale reorder rejection, metadata-preserving reorder, favorite URL validation, and promoting an existing folder bookmark without losing metadata. A counted 20,000-entry sequence verifies that the default recent-site lookup reads only four eligible unique entries; zero-limit and private lookups read none.
- All new Swift sources and native tests passed a Swift parser check.
- `NativePremiumStartChecks.swift` now defines **31 native assertions**: the original 18, five Recent Sites subscription/cache assertions, and eight additional rendered-clearance/scroll assertions. Six UIKit-hosted scenarios measure the actual interactive content rectangle, not only inset arithmetic: a low full-width obstruction, a wide interior obstruction, and physical left/right obstructions in both left-to-right and right-to-left layout. Each measured rectangle must avoid the obstruction and stay within its expanded section. The low-obstruction scenario also checks native scrolling and restoration of the rendered frame when the region disappears. **Execution of the revised native cases is pending the integrated run.**
- The first integrated revised run reached the rendered-clearance fixture and timed out before its first assertion. The fixture previously cached window frames in each probe's `layoutSubviews`; moving a fixed-size child through an ancestor can leave that cached frame stale. The fixture now registers native probe views and reads `convert(bounds, to: window)` afresh for every wait and assertion, retaining the exact expected bounds and nonintersection requirements. A failure records actual outer/content rectangles. This fixture change does not alter production clearance or establish that the pending rerun passes.
- Debug-only `premiumStartPreview()` seeds an isolated archive and nonpersistent profile for visual review. Launch with `--browser-checks --premium-start-preview`, optionally adding `--premium-private-preview`. Favorite `.example` hosts intentionally exercise the letter fallback; loopback destinations provide the synthetic open tabs.

## Remaining validation

Integrated Debug/Release builds, native execution, and screenshots across closed/open/partially folded, rotation, larger text and appearance belong to the parent integration receipt. Physical touch, spoken VoiceOver, endurance, and battery results are not established by these source/portable checks.

## PR review corrections

Three start-page findings from PR #26 were valid and addressed in the source and tests above:

- A stable bottom inset did not prove that lower/interior content had moved out of an obstruction. The revised policy moves the real content rectangle, and the new hosted fixtures check nonintersection and scroll reachability.
- Directly treating physical left/right as logical leading/trailing reversed avoidance in right-to-left layout. The modifier now maps these edges using the actual SwiftUI layout direction, with rendered tests for both physical sides in both directions.
- Eager filtering scanned the full history before taking its prefix. The query now stops at its bound; zero/private queries do no iteration, hidden sections have no subscription, and visible results update on data changes rather than scrolling.
