# Daily browsing and native polish

[PR #26](https://github.com/cnichols1734/DuoBrowser/pull/26) combines tab interactions, Page options, a redesigned start page, simple recovery, extension compatibility guidance, and native polish. The owner authorized an in-place installation on the connected phone before any TestFlight decision. No merge or TestFlight upload is included.

## Delivered behavior

- **Tabs:** finger-following adjacent-tab previews retain the current live page. Commitment selects the existing neighbor; cancellation, a second/opposite drag, interruption, folding, rotation and Reduce Motion restore a valid presentation. Search, workspace identity, Grid/List, pinned-first reordering, multi-select Move/Close and durable-write rollback are included. Scope guards keep private and other-workspace selections separate.
- **Page options:** a native controls sheet groups Share, Save, Find and Reader, website controls, tab actions and browser destinations. Follow-up presentation waits for dismissal and validates the originating tab/document. SF typography and the existing Liquid Glass toolbar remain.
- **Start page:** workspace switching, direct search, an editable Favorites ribbon and existing-tab continuation replace the previous repeated grids. Sections are configurable; Recent Sites is optional and cached on data changes. Favorites preserve bookmark identity, folder and date, and removal retains the Library bookmark. Private starts omit normal browsing surfaces and icon requests. A single-child layout measures full and wrapped widths independently to clear runtime occlusions, with bounded retries, RTL placement and a reversible fallback.
- **Recovery:** concise local messages keep usable pages visible and offer explicit failure-scoped actions. Retry validates the original HTTP(S) address and permits GET/HEAD only; no failed POST is replayed and TLS checks remain intact. Opening a saved copy preserves the source failure for return. Generic notices, including scheduled/background archive-write errors, retain typed recovery and appear as secondary text; a successful save removes only its warning. Explicit dismissal and navigation still clear recovery. Oversized notices scroll while browser controls remain reachable.
- **Secondary surfaces:** Settings, Downloads, Website Data, Website Protection and Library receive consistent navigation, accessible targets, loading/empty/cancellation states and focus restoration. Website Data uses the public callback enumeration API and preserves the original deletion-type selections and privacy boundaries.

Reader extraction/rendering and page-layout JavaScript are unchanged. This change adds no two-page mode, separate-login profiles or private-tab lock.

## Extension compatibility

This change does not install or host Safari extensions. Public WebKit APIs can host compatible accessible packages, but the inspected SDK provides no supported way to enumerate/extract arbitrary installed Safari extension bundles or their private settings. Safari transfer and default-browser approval do not supply those packages.

Other Blocking Apps links to official setup instructions for the owner's named products: AdBlock Pro, Adblock Plus, AdGuard, 1Blocker and Wipr. Some vendors separately offer DNS, network-tracker or system URL filtering that may affect ordinary DuoBrowser traffic after the user enables it. Those routes are distinct from loading a Safari extension and do not imply equivalent cosmetic filtering, automatic detection/import or verified device compatibility. The [ten-product evidence matrix](../2026-11-14-premium-controls/extension-compatibility.md) records each route and its limits. Built-in maintained EasyList/EasyPrivacy protection remains available independently.

## Verification and delivery status

| Check | Completed result |
| --- | --- |
| Full synthetic iOS 27.1 Duo native suite | **644 assertions passed** |
| Expanded premium regressions | **149 assertions passed**, including address editing, mid-drag layout and ten persistence-warning/recovery checks |
| Portable policies and persistence | **392 checks passed** |
| Web/layout fixtures | **197 assertions passed** |
| SwiftLint 0.65.1 | Strict lint passed |
| Builds | Debug simulator and signed-device Release rebuilds passed |
| Hosted CI and Copilot review | Clean at [`1bbc6fa`](https://github.com/cnichols1734/DuoBrowser/commit/1bbc6faa4e9c537b8ab56b645d13e769c46fa6fe) |

The full suite covers live page/draft preservation, interrupted swipes, stale actions, durable-write rollback, private isolation, recovery/copy return, actual rendered occlusion nonintersection, wrapping convergence and RTL/intrinsic alignment. The expanded **149-assertion premium run** also verifies scheduled and background write failures, successful warning cleanup, unchanged ordinary save-error reporting, and visible warning/retry coexistence on full and inline surfaces. Debug and signed Release builds and strict lint passed. Save-error wording no longer blames a valid address for storage failure. The full 644-check run belongs to the earlier checkpoint; the final complete rerun, hosted CI, review and exact-source delivery receipts are tracked on the PR.

Closed-display simulator captures below use synthetic sites; Favorites deliberately show letter fallbacks. Maximum text, dark appearance, Reduce Motion and the VoiceOver-enabled partially folded interface also received simulator accessibility inspection. Scratch receipts, signing profiles and device identifiers remain under ignored `work/`.

Interactive simulator inspection exercised navigation recovery, address editing, Page options, native Find (nine matches), Share presentation/dismissal, tab search, Grid/List, accessible reordering, batch workspace movement, bulk-close cancellation and start-page customization. Display transitions included closed, open, partially folded and rotation. VoiceOver's system onboarding required dismissal; this was an interface inspection, not full spoken navigation acceptance.

For comparison, the repository retains the [previous mixed Page menu](../2026-11-12-downloads/before-menu.png) and [previous tab overview](../../images/tab-overview-2026-11-08.png). Those are historical synthetic captures with different display poses/fixtures, not controlled pixel comparisons.

| Start page | Page options |
| --- | --- |
| ![Closed-display start page](start-closed.png) | ![Closed-display Page options](page-options-closed.png) |

| Tab grid | Tab list |
| --- | --- |
| ![Closed-display tab grid](tabs-grid-closed.png) | ![Closed-display tab list](tabs-list-closed.png) |

![Open-display start page](start-open.png)

The signed development build **1.0.1 (13)** is installed in place on the connected Duo as `dev.cnichols.duobrowser`, with no uninstall. The signature, team, target-device profile, version, minimum OS, Photos purpose string and disabled default-browser entitlement passed preflight. Installation and installed-app inventory receipts confirm delivery. iOS refused the launch attempt while the device was locked; exact final source, the requested unlock and final launch receipt are tracked on the PR.

Physical touch/frame pacing, battery/endurance, full spoken VoiceOver, signed credentials/passkeys, third-party system filters and actual Safari transfer remain separate hardware checks. Simulator results do not establish those outcomes. Merge and TestFlight remain owner-controlled later steps.
