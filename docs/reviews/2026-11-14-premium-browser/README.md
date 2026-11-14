# Daily browsing and native polish

Owner request: one PR combining tab interactions, Page options, a distinctive start page excluding Reader updates, simple recovery, extension feasibility and broad native polish. The owner authorized installation on the connected phone before TestFlight. This work does not authorize merging or uploading TestFlight.

## Design and implementation

- Preserve the existing content-first browser, SF typography and native Liquid Glass toolbar. Everyday page actions are grouped in an accessible native controls sheet; follow-up actions run after dismissal and validate their originating tab/document.
- Adjacent-tab drags preview a neighbor while retaining the current live web view. Commitment selects the existing neighbor; cancellation, interruption, folding, rotation and Reduce Motion clear or preserve presentation appropriately. Normal preview images remain memory-only. Private tabs do not acquire normal previews.
- The tab overview exposes search, workspace identity, Grid/List, reordering and multi-selection. Pins remain first. Scope validation rejects stale/private/other-workspace operations. Failed durable reorders/moves roll back without replacing pages.
- The start page prioritizes search, configurable Favorites and existing-tab continuation. Favorites editing preserves saved metadata; removal from Favorites retains the Library bookmark. Native runtime occlusion geometry provides local clearance without guessing device pose.
- Recovery shows fixed local copy for connection, timeout, certificate and process errors. A usable existing page remains visible. Retry is explicit, HTTP(S)-validated and GET/HEAD-only; no failed POST is replayed. Every navigation action is failure/document-scoped. Oversized notices scroll within available space, leaving browser controls reachable.
- Settings, Downloads, Website Data, Website Protection and Library receive consistent navigation, accessible targets, useful empty/loading/cancellation states and focus restoration.

## Extensions

The shared WebKit engine supports hosting compatible web extensions. It does not give a third-party browser access to every extension registered with Safari. Public loaders require an accessible app-extension bundle or package. The inspected SDK exposes no installed-Safari-extension picker or cross-app package/settings access.

The owner specifically named AdBlock Pro, Adblock Plus, AdGuard, 1Blocker and Wipr. Official provider guidance distinguishes Safari-only extensions from optional system-wide DNS, tracker filtering and URL filtering. Those system-level features may affect DuoBrowser independently of Safari transfer. The app links to official setup instructions and makes no runtime detection, purchase, compatibility-parity or automatic-import claim. See the [ten-product research matrix](../2026-11-14-premium-controls/extension-compatibility.md).

## Verification

Initial portable recovery policy checks pass (27). The existing 197 web assertions pass; no Reader or page-layout JavaScript was changed. The first integrated Debug build passed. The initial new native run exposed an ignored quick second swipe during snap-back; production interruption behavior was corrected and an explicit regression added. These are intermediate checkpoints, not final exact-source acceptance.

Final Debug/Release builds, full portable/strict-lint/native checks, simulator interaction/capture matrix, latest-head hosted CI/Copilot review and signed phone installation will be recorded here as they complete. Scratch logs, profiles, device identifiers and personal data remain under ignored `work/` and are not uploaded.

Physical touch/frame pacing, battery/endurance, full spoken VoiceOver, signed credentials/passkeys, third-party system-filter installations and real Safari transfer require separate hardware verification. Simulator geometry and synthetic callbacks do not prove those outcomes.
