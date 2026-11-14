# Compact browsing surfaces

The owner's phone feedback identified wasted upper space and insufficient room for useful content. This pass changes layout density while retaining the existing native typography, wallpaper, tab/session behavior and public reserved-region geometry.

## Changes

- The normal-text tab overview has one search/Select row. Workspace identity and the visible tab count remain in the footer; batch Close shows its selected count. Accessibility text retains a stacked search/selection header and separates the footer's workspace selector from its action buttons.
- Header clearance now measures the actual header rectangle through the existing bounded single-child avoidance layout. A side occlusion does not create a matching inset on the opposite side, and a region below the header does not reserve an empty top band. Grid geometry, tab previews and the existing TabStack close-button avoidance remain unchanged. List clearance maps physical exclusions asymmetrically into the current layout direction.
- The start page keeps its direct search invitation, with a regular 50-point minimum height, title2 brand text, 20-point section spacing and a single 16-point top baseline. The native host owns safe-area positioning; active reserved-region collisions receive local measured clearance. Larger text continues to expand naturally and use the accessibility layout.
- Page options opens at the large detent. Regular group spacing is 16 points, quick actions have a 60-point minimum, website destination rows use a 56-point minimum plus small vertical spacing, and header padding is reduced. Accessible text rows remain generous and all action targets retain at least 44 points.

## Verification

All three changed SwiftUI sources and the new native test file pass a Swift parser check; patch whitespace checks pass. No build, simulator launch or phone installation was run for this pass by the layout agent.

`NativePremiumDensityChecks.swift` defines fifteen actual rendered assertions: seven baseline checks cover compact tab-header position/height, a below-header region producing no top gap, asymmetric side clearance/nonintersection, removal restoring the original row, compact start heading, compact direct-search size/spacing, and an embedded ten-tab grid scrolled down/back and into negative overscroll/back. The scrolling check requires a header at least 44 points high, body allocation below it, and a header hit area not intercepted by the collection. It uses isolated synthetic session data and live UIKit frame conversions. All fifteen checks pass in the final integrated run below.

## Grid overscroll follow-up

Manual pan screenshots could temporarily omit the search header while the footer remained visible; a later settled screenshot showed the header again. The synthetic-preview geometry probe recorded 42 samples across offsets from −557 to 162.67 points. Header height/position, body allocation and header hit coverage remained valid throughout: the header was at y=12 with height 44 and the grid viewport at y=68 with height 546. Ancestors remained visible at full alpha. This evidence does not establish a VStack compression bug or a universal framework defect.

`TabStackController` now has a stationary transparent UIView viewport with the collection pinned on all four edges. Both views clip; collection scrolling no longer changes the representable root's bounds origin. Existing cell/gesture/zoom-source ownership and occlusion handling are retained. No fixed-size header, layout-priority or z-order workaround was added. This is bounded structural isolation, not an established causal repair for the earlier capture discrepancy.

The live simulator surface subsequently showed the header fully visible immediately after repeated pull/bounce gestures. New Tab → Tabs showed the correct five-tab count; maximum accessibility text and open/closed start layouts were also inspected successfully. Some native captures could still omit the header while the live simulator surface showed it. A capture/compositing artifact is plausible; the precise cause is not established, and neither a universal framework defect nor a proven persistent-overlap repair is claimed. Normal text and closed portrait were restored after inspection.

The temporary opt-in geometry/hit/visibility recorder used for the comparison has been removed from the app sources, along with its scroll callbacks. It recorded no page strings or images; scratch receipts remain under ignored `work/`. The native header test probe remains Debug-only; the final integrated suite covers all fifteen rendered density assertions.

This density pass preserves Reader and navigation behavior. The final integrated result, captures and authorized release status are recorded below and in the combined review.

## Final integrated validation

The final build 14 Debug and signed Release builds pass, along with all **706 native assertions across 12 batches**, including **Premium 188 and all 15 density checks**. Strict lint and 392 portable checks pass. The reviewed build 13 was verified installed/running after unlock. The owner authorized merge and TestFlight build 14 for all existing testers; final CI/review and distribution states are tracked on PR #26.

## Vertical List exclusions

The native List now occupies a useful clear rectangle calculated from its actual unchanged body allocation. The bounded search retains at most 64 candidates while processing every intersecting system exclusion; physical coordinates map through RTL placement. A single retained List keeps its identity as the clear lane changes. Fully covered bodies hide their List’s pixels, hit targets and accessibility without moving the header.

Eight additional rendered checks inspect actual accessibility-size native row-cell rectangles under a below-header full-width exclusion, scroll, moved/outside/removed exclusions, combined RTL exclusions and complete coverage/recovery. A one-point hidden native canvas rounds outward by one physical pixel on the 3x simulator; the test permits that measured pixel-alignment bound and still verifies actual hit exclusion, unchanged header and restored List identity. All fifteen density assertions pass.
