# Build plan

## Undo card visibility — November 12, 2026

- Fixed the owner-reported close → Undo → tab-switcher failure. Live Undo correctly retained the tab and page, but the same UUID's card could retain its offscreen close transform or Reduce Motion opacity. Idle card motion is now restored even when close/reopen updates coalesce to unchanged IDs, with active gestures and animations preserved.
- A native regression reproduced the original bug: live model/view identity and draft survived, but the restored overview card was not visible/hittable. The corrected implementation passed 16 Undo checks across normal/Reduce Motion and coalesced/removal snapshots, including a second close. The combined TabStack40, retained Downloads49, 339 portable checks and pinned strict lint also passed. [Evidence](reviews/2026-11-12-tab-recovery/README.md#undo-overview-card-follow-up).
- At the owner's explicit request after device testing, removed the two unstable authenticated GET retry/source-closure scenarios (four assertions) and their authentication-only diagnostics from native CI. Other download progress, source closure, retry, cancellation, private cleanup and storage checks remain; production download code is unchanged.
- The complete corrected source `ba78f5b30a918367069eb52b9fd26d8c01f1bf98` passed **517 native assertions across all 11 batches** on a fresh iOS 27.1 Duo simulator, including Downloads49 and TabStack40. Debug, 339 portable checks and pinned strict lint passed; the 197 passing web assertions have unchanged JavaScript/test/package sources. [Receipt](reviews/2026-11-12-setup-centering/undo-native-receipts.txt).
- The owner superseded the earlier installation gate and requested a developer build while CI work continued. Source `47e02da` was installed in place on the connected Duo and verified running; the new Undo-corrected build follows separately. The owner also authorized merging after CI/review checks pass. TestFlight remains on hold for device review. Signing and installation evidence stays under ignored `work/final-device/`, and the unapproved default-browser entitlement remains off.

## Handoff validation — November 12, 2026

- Closed the observed native/DOM geometry readiness gap in the Reddit handoff fixture and propagated the correction from PR #23 into PR #24 with an ordinary merge. Production browser behavior and all existing handoff assertions are unchanged. The hosted timeout itself was not reproduced locally; diagnostic runs established stale native dimensions after DOM readiness. [Diagnosis](reviews/2026-11-12-camera-settling/README.md#november-12-handoff-reddit-scroll-readiness).
- The complete combined native source `41a8431f539e11fb02817d5c7870e677207da691` passed **505 assertions across all 11 batches** on a fresh iOS 27.1 Duo simulator with Xcode 27.2. Combined Debug/Release simulator builds, 339 portable checks and pinned strict lint passed. All 197 web assertions passed on the identical JavaScript/test sources in PR #23. [Fresh receipt and limits](reviews/2026-11-12-setup-centering/README.md#handoff-validation).
- Latest-head hosted CI/review is tracked in PRs #18–24. Final signing, in-place installation and launch receipts belong under ignored `work/final-device/`. The owner subsequently changed the installation/merge instructions as recorded above; TestFlight remains on hold. The default-browser entitlement remains disabled; hardware touch/energy and full spoken VoiceOver remain separate checks.

## Final integrated feature validation — November 12, 2026

- The final source `9f07d1ae3773c650a5b3d2f391e5f484756228d1` combines maintained filters, tab recovery, saved pages/offline reading, downloads, Browser/Website Settings, camera settling and full-display setup. All **494 native assertions across 11 batches passed**: Downloads47, Settings48, Setup37, Reddit29, TabStack21, Core93, Upgrades160, Camera42, cookie write2/read2 and Memory13. Debug, 339 portable checks and pinned strict SwiftLint passed. Product Release passed at `b394999`; later changes affect only test readiness, fixtures and evidence.
- This integrated result supersedes earlier feature reports’ pending-native statements below; those reports retain their historical checkpoints and manual interaction limits. The final setup screenshots cover closed/open/partially folded poses, rotation and maximum text. A Website Settings harness race was fixed by waiting for the actual new-host document, preserving the stale-scope assertions.
- Latest-head hosted CI, final exact-commit signing and device installation are still pending in the PRs. Hardware touch/energy, real Safari transfer and full spoken VoiceOver remain unverified; no merge or release is implied. [Combined receipts, screenshots and limits](reviews/2026-11-12-setup-centering/README.md).

## Full-display setup alignment — November 12, 2026

- Centers all setup steps, headings, actions and progress on the full horizontal display bounds while retaining vertical safe areas and scrolling accessibility actions. Runtime reserved-region frames (including their system margins) provide local top-control clearance only when needed.
- Thirteen native geometry/layout assertions added; all Setup37 pass, including independent UIKit window-coordinate checks for every step with left/right asymmetric safe areas. Debug/Release builds, 328 portable checks and strict lint pass. Closed/open/partially folded, rotated and maximum-text UI captures confirm the final single-host layout; the ultimate combined-stack run also passed (see the integration checkpoint above). [Evidence](reviews/2026-11-12-setup-centering/README.md).

## Camera avoidance and gradual settling — November 12, 2026

- Handoff follow-up: PR #23's hosted Reddit check timed out before handoff. The unchanged local baseline and three diagnostic runs each passed all 29 assertions, while diagnostics consistently showed stale native content size (980 × 1426 → 466 × 2238) after DOM readiness. The harness now waits for matching native/DOM geometry before native scrolling, retaining all assertions and the original 10-second waits; production code is unchanged, and CI compilation uses `-jobs 2`. The exact hosted timeout was not reproduced. The corrected Debug build, three Reddit29 runs, Camera42, 339 portable checks, 197 web assertions and pinned strict lint passed locally. Final combined validation and hosted CI/review are tracked in the setup branch before signed-device installation. [Evidence](reviews/2026-11-12-camera-settling/README.md#november-12-handoff-reddit-scroll-readiness).

- Responds to the owner's long-paragraph camera overlap and abrupt-motion report. Side fitting now supports bounded longer paragraphs; mutation activity cannot indefinitely postpone fitting or repeatedly restart a glide. Motion uses a gentler horizontal transform, with one settled reflow, presentation-preserving interruption, unchanged reading anchors and static Reduce Motion avoidance.
- 197 web assertions, 328 portable assertions, strict lint and Debug pass. All 42 focused native camera checks pass, including eight new actual-system-occlusion, production-bridge and interruption checks. Production UI confirms long-text clearance, Original Layout reversal and static Reduce Motion; manual scrolling is blocked by Device Hub automation. Final combined-stack validation remains separate. [Evidence and limits](reviews/2026-11-12-camera-settling/README.md).

## Tab recovery and navigation — November 12, 2026

- Copilot follow-up: Undo measures its rendered height and spacing for WebKit's obscured-content reservation, including accessibility text and camera-aware control lifting. Ordinary notice expiry uses the original close timestamp; VoiceOver/accessibility sizes still keep explicit dismissal. Closed records and close capture share reopening's 8192-character URL contract. Eight portable URL/time regressions pass; three new native measured-height/footer/removal checks await the coordinated runtime run.

- Follow-up review: clearing recovery now reports durable-write failure and retains rows to retry. Retained Undo pages reject navigation and native permission prompts; no presenter is available for JavaScript dialogs. Added native failure/retry and retained-page assertions; those follow-up assertions passed in the integrated 440-check run. Later notice-height/expiry review regressions await the ultimate camera-branch suite.

- Added normal-tab Undo and a 20-entry persisted Recently Closed list, preserving title, address, best-effort reading position, workspace and pin. Private tabs are excluded. History deletion also clears corresponding recovery records. Reopening loads the saved address, not form input or a full navigation session.
- Closing selects an adjacent visible tab. Address-capsule swipes and accessible menu actions switch tabs without reloading; Back supports a bounded history menu with stale-item validation.
- Debug/Release builds, 202 portable assertions, 186 browser assertions, SwiftLint and the full native suite passed. Native UI verified Close/Undo, accessible tab switching and Recently Closed across display sizes; gesture, keyboard/pinch and full accessibility/occlusion gaps remain. [Tab recovery evidence](reviews/2026-11-12-tab-recovery/README.md).
## Maintained content filters — November 12, 2026

- Copilot converter follow-up: exact `badfilter` option parsing, requesting-frame network domain scope, separate document/iframe exception alternatives, and WebSocket schemes; cache version 3. Portable regressions pass; added nested-frame/socket native assertions await integration. Cold hosted preparation failures now report bounded stage timings and retain the full-protection assertion with an explicit larger CI budget. See the maintained-filter report.

- Replaces the 19-service baseline with bundled EasyList/EasyPrivacy supported network and cosmetic rules, plus opt-in Cookie List filtering. Adds transactional automatic/manual updates, per-site draft-preserving switches, and offline filter credits. Filter data uses upstream CC licenses; independent app/converter code remains MIT. See [design, licensing and limits](MAINTAINED_FILTERS.md).
- Debug simulator build, 221 portable assertions, 186 web assertions and strict SwiftLint passed. Full bundled source lists compiled through a separate native macOS WebKit probe. An initial web timing failure under heavy concurrent compiler load passed on rerun with no JavaScript changes.
- Native UI verified manual update success, cookie controls, offline licenses, light/dark, closed/open/partial/rotated layouts, maximum text and Reduce Motion. Browsing starts with baseline protection during first preparation; a validated compiled cache avoids repeated conversion. Final Debug/Release and all 313 native assertions passed, including full maintained rules, cache recovery, draft-preserving promotion, stale callbacks and private/foreground update permission. See the [review record](reviews/2026-11-12-content-blocking/README.md). No real-site effectiveness percentage or hardware claim is made.
## Saved pages and offline reading — November 12, 2026

- Final review follow-up: failed bookmark/folder deletion now restores Library rows and presents an error. Three added native failure/retry assertions passed in the integrated suite; later archive/read/edit review regressions await the camera-branch suite; portable and lint validation are recorded in the saved-pages evidence.

- Added native Save Page with editable titles, Favorites/folder/Read Later destinations and explicit private-save disclosure. Library now supports folder creation/rename/move, bookmark editing, read/unread filtering and offline copy management. Reader appearance, spacing and text size persist.
- Offline saves reuse sanitized Reader extraction, capture bounded anonymous same-origin HTTPS raster images, and render from local snapshots with network-denying CSP in a separate ephemeral WebKit store. Storage is capped at 50 MB; unsupported images, videos and interactive content are not promised offline. Failed writes roll back saves; failed copy deletion reports an error and retains a retryable item.
- Debug/Release builds, 210 portable assertions, 186 web assertions, strict SwiftLint, repository checks and full native suite passed before the final disk-deletion follow-up (its three added assertions subsequently passed in the integrated run). Save-sheet controls and existing Library layouts were inspected across fold poses, rotation, dark appearance, maximum text size and Reduce Motion. A final focused-title/Command-S interaction saved an offline Reading List entry and verified its Unread · Offline row. The saved Offline Article also opened with the fixture server stopped. Manual folder creation/rename and subsequent persisted read-state transition remain unverified. Final accessibility metadata-stacking correction compiled in Release; the corrected maximum-text screenshot is now captured. Full spoken VoiceOver, pinch/live occlusion, physical-device and real HTTPS-image capture remain open. [Detailed evidence and precise follow-up status](reviews/2026-11-12-saved-pages/README.md).
## Browser Settings and website data — November 12, 2026

- Added grouped native Settings with search-engine choice (Google default), the existing online-suggestions preference, appearance, status bar, setup and privacy. Page options prioritizes page actions.
- Added confirmed selective normal history/cookies/cache removal and per-WebKit-record website removal; private data remains separate and saved pages/downloaded files stay intact.
- Integrated Debug/Release builds, 328 portable assertions, strict lint and repository checks passed. The preceding integrated native run passed 440 checks, including 40 Settings checks. Search, clear-data, selected-site removal and actual app appearance interactions passed simulator inspection. Website Settings is now a dedicated host-scoped Form; its host, toggle, protection detail and Done interactions passed simulator inspection. Its eight added native checks are queued with the ultimate camera follow-up validation. [Behavior, tests and integration notes](reviews/2026-11-12-browser-settings/README.md).

Earlier integrated checkpoint (superseded by the final validation above): source `5aaa842` builds and portable checks pass; review fixes and the dedicated Website Settings page still need the ultimate combined native rerun on the camera follow-up branch. No device installation, merge or release is implied.

## Onboarding redesign — November 11, 2026

- PR #17 review follow-up: retain the model’s status message during transfer review so a failed save displays its recovery instructions. Added a regression assertion for failed durable writes; the normal review notice remains concise. Removed optional category counts after review found that received bookmark totals could misrepresent the selected Favorites category; the saved summary reports actual results.
- Rebuilt the four-step setup presentation with system typography, plain surfaces, concise copy, aligned Back/Skip navigation and full-width primary actions. The welcome expansion symbol points horizontally. Transfer review has compact category toggles; extra details are disclosed on demand, and unavailable capabilities do not show unusable switches.
- Kept the existing transfer/privacy/persistence model. Maximum accessibility sizes remove decorative images and put actions in the scrollable content. Completed first-run, synthetic import, reentry and skip interactions on the iOS 27.1 Duo simulator, with closed/open/partial poses, rotation, dark appearance and maximum text size.
- Debug/Release builds, 192 portable assertions, 186 web assertions, SwiftLint, repository checks and the combined native suite passed. A simulator Reduce Motion pass covered forward navigation, Back and Skip; the original setting was restored. Full spoken VoiceOver, live occlusion, hardware and actual Safari transfer remain unverified. [Screenshots and evidence](reviews/2026-11-11-onboarding/README.md).

## Reddit app links and ad-blocking controls — November 11, 2026

- Added native Apollo Reborn handoff for trusted Reddit content-link taps and supported Google wrappers, a remembered first choice, Ask Every Time, browser fallback, private-tab confirmation and Settings controls. A fixed isolated-world click gate prevents scripted clicks from launching apps; URLs are not persisted or logged. Artemis was researched but is not exposed until its deep-link contract and actual post/comment behavior can be verified.
- Added the global Block Ads & Trackers switch over the existing 19-service rules. Preserves site exceptions and page drafts; existing tabs apply changes to new requests without automatic reload. New tabs, private tabs and Reader inherit the preference. This is built-in blocking, not support for installed Safari extensions.
- Passed Debug/Release simulator builds (Xcode 27.2, iOS 27.2 SDK, deployment target unchanged at iOS 27.1), 192 portable assertions, 177 Playwright assertions, SwiftLint and repository checks. Full native suite passed: 23 setup, 25 Reddit, 18 tab-stack, 93 core, 63 upgrade/blocking/Reader, 34 settling, 2 cookie-write, 2 cookie-read and 13 memory checks.
- Real simulator tap verified the production gesture gate and chooser, correct comment deep link, remembered selection and retained draft using a simulated OS launch. Settings controls were exercised in closed/open/partially folded poses and rotation. Actual Apollo installations/sideload variants, Artemis, hardware touch/energy, full spoken VoiceOver, large text and the remaining accessibility/occlusion matrix remain unverified. [Evidence and limitations](REDDIT_LINKS_AND_BLOCKING.md).
- Parallel research confirmed public native WebKit extension-hosting APIs, but Safari transfer contains extension metadata rather than packages/settings/permissions. A tested compatible catalog and a permission-aware extension host need separate implementation before useful migration. [Extension feasibility and stages](SAFARI_EXTENSIONS.md). No extension runtime, merge, release or App Store approval is claimed.

## Completed setup — October 26, 2026

- Local Git repository initialized on main.
- Brim's landing page and TestFlight listing checked; implementation details remain unverified.
- Apple Duo layout, WebKit, Foundation Models, and browser entitlement references researched.
- Xcode 27.1 and Duo simulator availability checked.
- Public reserved-region API declarations found in the installed SDK.
- Initial brief direction approved by the owner. App-project registration remains open.
- Native Xcode project created with a shared DuoBrowser scheme, iOS 27.1 app target, local fixture, URL/search navigation, full-width toggle, and reserved-region overlay.
- Debug build passed for both simulator architectures. A dedicated DuoBrowser QA simulator was created; installation and launch succeeded. Interaction testing remains open; see VALIDATION.md.
- Follow-up: removed the default right-hand blank strip by enabling full-width rendering and hiding the status bar. Rebuilt and installed on DuoBrowser QA; visually confirmed Apple's website spans the closed display. See VALIDATION.md for remaining checks.
- Scrolling follow-up: moved the native indicator to the right edge and added a compact URL pill on downward scrolling, with upward-scroll/tap restoration. Build and 16 policy checks passed; native closed-display collapse, restoration, and keyboard interactions passed. Other poses, accessibility settings, and hardware remain to verify; see VALIDATION.md.

## Glass controls and tabs — October 26, 2026

- Centered bottom controls across the full display, using native Liquid Glass without a forced material tint or appearance.
- Added a continuous domain-capsule collapse, with separate compact/expanded vertical positions. Side controls fade near the outer edges and are absent when compact; tap or reverse scrolling restores them.
- Added multiple tabs with stable web views, page previews, close/new/select, tab search, and basic URL/order/selection restoration. Background restored tabs load when selected. Private browsing, tab groups, full session recovery, and memory-pressure eviction remain later work.
- Build and 33 portable behavior checks passed. Closed-Duo native creation, URL entry, selection, closing, relaunch restoration, full-width overview, and compact/restored controls were exercised. See VALIDATION.md for detailed evidence and remaining checks.

## YouTube feed compatibility — October 26, 2026

- Implemented a bounded, reversible mobile YouTube body-padding correction. Feed previews and search results now span 466 CSS pixels on the closed QA display, reclaiming the measured 84px gutter. The independently inset header stays unchanged.
- Added an “Original YouTube layout” switch for the current live tab; full-width off also restores the original page. No AI, page text collection, or general bridge is involved.
- Enabled inline media playback for sites that request it, avoiding forced fullscreen feed previews.
- Simulator build, 16 synthetic browser layout checks, 21 scroll checks, and 12 archive checks passed. Native feed/search, scrolling, menu reachability, restore/reapply, and playback checks are recorded in VALIDATION.md.
- The watch-page player's separate inset, general camera avoidance, native pinch/accessibility, broad pose coverage, and hardware profiling remain open.

## Automatic gutter fitting — October 27, 2026

- Replaced the YouTube-specific module with `PageLayout`: no host or site-element rules remain. Detect one matching body/root-wrapper gutter with a responsive child and protected fixed/sticky top bar. Validate header descendants and horizontal overflow; roll back failures.
- Added the universal “Original page layout” control. Generalized the regression suite to 24 real-browser synthetic scenarios, including unrelated origins and standard HTML containers; all passed.
- Updated the native viewport lab to exercise the same safe-area pattern without YouTube markup. See VALIDATION.md for actual native results.
- Confirmed current Apple Foundation Models APIs and documented the bounded on-device selection experiment in ARCHITECTURE.md. No AI runtime integration or universal camera avoidance is claimed. Native pinch/collision validation, additional safe operations, held-out evaluation, and eligible physical hardware precede AI enablement.

## 1. Prove the available space

### Owner's eight-site smoke test — October 27, 2026

All eight supplied sites were exercised in the native QA simulator; [results and coverage limits](SITE_QA_2026-10-27.md). Prioritize general camera-control protection and browser/site bottom-UI collision handling, then diagnose Google/Meta gutters and the native Open Link path that launched Safari. Logged-in flows, complete sticky/infinite-scroll coverage, and the broader device/accessibility matrix remain open. No runtime fix or AI integration was added in this test pass.

The starter `DuoBrowser.xcodeproj` now has a SwiftUI iOS app target, shared scheme, UIKit/WebKit integration, and iOS 27.1 deployment target. Put app sources under `DuoBrowser/`, synthetic web fixtures under `Tests/Fixtures/`, and meaningful geometry tests under `DuoBrowserTests/`. Use no third-party dependencies initially. Keep the signing team unset for local simulator builds.

Build a diagnostic browser shell with URL entry, back/forward, reload/stop, and a full-width mode. Expose reserved-region and viewport overlays only in development UI. Make a dedicated DuoBrowser QA simulator so existing QA sessions are not disturbed.

Acceptance:

- Build with xcodebuild for iOS Simulator and launch on Duo.
- Compare Safari, ordinary WKWebView, and experimental full-width WKWebView on identical fixtures and zoom levels.
- Record actual web viewport width and height, occluded area, browser chrome area, and reachable actions in closed, open, rotated, and partially folded poses.
- Verify keyboard entry and pinch zoom before adding AI.
- No fixed camera coordinates, private API, unexplained blank rail, or inaccessible navigation.

Gate: prove a usable-space gain. SDK availability alone does not pass.

## 2. Fit around the camera

Implement bounded DOM collision detection, a reversible adjustment ledger, geometry conversion, and original-layout/site-disable controls. Add fixture cases for fixed and sticky headers, flex/grid menus, right-to-left layouts, forms, scrolling containers, transformed/clipped elements, safe-area-aware sites, and dynamic replacement of nodes. Include unsupported iframe/canvas cases that deliberately fall back.

Acceptance:

- Every fixture's essential action remains reachable and functional after adjustment and restoration.
- Navigation, zoom, focus, form state, and fold transitions remain intact.
- Repeated mutations converge or trigger fallback; there is no feedback loop.
- Motion looks intentional at normal speed and obeys Reduce Motion.
- On-device profiling targets smooth scrolling with no adaptation-created long main-thread stalls; record traces before declaring success.

## 3. Test whether AI helps

Add optional Foundation Models classification behind an experimental switch. Use typed outputs selecting existing actions. Benchmark against the deterministic engine on the same held-out layouts.

Acceptance: a measured improvement in successful repairs, bounded latency and energy impact, safe failure/timeout behavior, no inference during every scroll frame, and unchanged browsing when the model is unavailable. Test on an eligible physical device; a simulator is not evidence of real Apple Intelligence performance.

Retain AI only if it improves the experience. The product benefit is better browsing space.

## 4. Make it a daily browser

Add persistent tabs and crash recovery, bookmarks/history, private sessions, find in page, share, downloads, page zoom/text controls, permission handling, desktop-site preference, and content-blocking support. Cover JS dialogs, popups, file uploads, PDFs, media, WebRTC, and network failures.

Assess password/passkey/autofill behavior and relevant entitlements separately. Evaluate Reader and sync as later capabilities; do not promise Safari's integrations. Keep privacy deletion complete across web data, history, tabs, caches, and diagnostics.

Acceptance: routine browsing flows pass on the owner's frequent sites, a representative compatibility corpus, and a physical Duo. Restore sessions after process termination. Verify private-data isolation and deletion.

## 5. Release readiness

Test VoiceOver, Dynamic Type, Reduce Motion, keyboard accessibility, hardware touch targets, Live Activities/system occlusion changes, network transitions, memory pressure, energy, and long sessions. Compare the same tasks against Safari.

Request the default-browser capability and any other needed managed entitlements through Apple's process. Review adaptation behavior against default-browser requirements; preserve the site's intended content and navigation. Select final naming, bundle ID, icon, privacy disclosures, signing, and distribution route before TestFlight/App Store work.

## Measurement sheet

For each comparison, record device/runtime, pose, site/fixture version, zoom, browser mode, raw viewport size, exclusion area, chrome area, and usable area as the viewport minus the union of occlusions/chrome. Also record completed essential actions, layout regressions, adaptation latency, frame hitches, and fallback rate. Avoid double-counting overlapping regions. All performance budgets are proposed targets until measured on hardware.

## Next owner input

The owner approved PRODUCT_BRIEF.md's direction, including bottom floating controls and the initial opt-in adaptation experiment. Add this folder as a local project in the app, then move the planning chat into that project. Supply frequently visited sites when convenient; synthetic fixtures can proceed independently.

## Production audit and implementation — October 27, 2026

The requested P0/P1/Duo gap analysis was completed before code changes: [frozen audit and dependency plan](PRODUCTION_AUDIT_2026-10-27.md). Subsequent profile/privacy, durable-state, navigation, transfer, library and geometry work is described in [implementation and release gates](PRODUCTION_IMPLEMENTATION_2026-10-27.md). That report supersedes earlier “future work” descriptions for those features, without converting unverified credential/hardware behavior into a pass.

The immediate next release dependencies are signed credential/passkey eligibility, physical permissions and accessibility, hostile/complex layout fallback, and low-memory/endurance validation. There is still no on-device AI implementation or reason to require it for basic browsing.


## Accessibility and memory follow-up — October 27, 2026

Added adaptive large-text browser/tab/library controls, constrained address editing, explicit accessibility traits/order, dynamic bottom obscuration and error announcements. Preview images now have a 640-pixel dimension ceiling and 8 MiB cache budget with recent-tab priority. Reclamation uses isolated, bounded DOM checks and protects inline-event pages as well as forms/scripts. See [measured results and remaining gates](ACCESSIBILITY_MEMORY_2026-10-27.md) and [the owner device credential checklist](IPHONE_PASSWORD_PASSKEY_CHECKLIST.md). Physical spoken/gesture coverage, WebKit-inclusive memory/energy endurance and correctly provisioned arbitrary-site passkeys remain separate release work.

- Rotated native controls now use active system occlusion geometry to avoid the bottom camera without narrowing the page; final Debug/Release builds and 30 native checks passed. See the accessibility/memory follow-up for limits.

## App icon — October 27, 2026

The owner selected and supplied a blue-globe/open-book icon after the earlier compass and two-panel D concepts, then requested removal of its exterior white border. The navy background now fills the square asset, with iOS applying the final corner mask. The 28-second product demo closing card also uses the selected artwork. See [asset provenance and verification](APP_ICON.md). The 1024-pixel opaque raster is wired into Debug and Release; custom dark/tinted layers and hardware appearance remain unverified.

## Open-source preparation — October 27, 2026

Prepared MIT licensing, contribution/security/release guidance, issue/PR templates, owner review policy, pinned development tools and hosted CI on `chore/open-source-preparation`. The pre-change exposure assessment found no committed secrets; the owner approved the public reporting email and icon licensing. Application behavior and project configuration are unchanged. Local and hosted build/test checks passed. See [verified settings, limitations and publication checklist](OPEN_SOURCE_PREPARATION.md). The repository remains private, PR review is required, and public visibility and App Store publication each require separate explicit authorization.


## Sideways scroll settling — October 28, 2026

Camera fitting now waits for touch release and a 240 ms quiet period, then settles horizontally over 420 ms. Reading paragraphs retain their top position and font size. Supported full-width paragraphs narrow inward from the camera side only after scrolling stops; there is no vertical text-avoidance fallback. New gestures freeze fitting, and Original Layout restores the author layout. A separate simulator-only ActivityKit companion and Debug system-status switch allow review with a real Dynamic Island activity.

Debug/Release builds, 102 browser-layout checks, portable checks and lint passed. The synthetic page was reviewed with the compact island, Original Layout, keyboard/form editing, closed/partial/open poses and rotation. See [verification and remaining limits](SCROLL_SETTLING_2026-10-28.md) for native regression results, screenshots and the exact review matrix. Physical touch/frame-rate/energy profiling, spoken VoiceOver, manual pinch/larger-text coverage and the broader website corpus remain open; simulator success does not close those release gates.

- Reading-position follow-up: reproduced a 24 px upward jump when restoring an offscreen paragraph. Fitting now anchors visible text across reflow and excludes internal scroll corrections from animation interruption. Added browser and native regressions for the paragraph's screen position and partially visible words; see the same validation report for results.

The live news-layout follow-up now handles compact sticky control rows (including closed offcanvas drawers) and local paragraph flow inside deeply nested grid shells. The same live article was inspected with the compact system activity: header controls and paragraph text fitted sideways. A synthetic fixture adds thirteen regressions for links, restoration, repeated settling and visible-word anchoring below sticky page bars. Native verification and CI status are recorded in the [settling report](SCROLL_SETTLING_2026-10-28.md). Clipped scrolling tickers and other unsupported structures may still remain behind the system region.


## Browser productivity upgrades — October 29, 2026

Implemented local unified search, normal-tab workspaces and pins, interactive Peek with same-web-view promotion, native text Reader, and a conservative bundled third-party ad/tracker blocker. Existing glass controls and camera-layout engines are preserved. The feature branch is stacked on PR #4 for owner review; no merge or release is performed.

Debug/Release builds, 62 portable assertions, 118 browser/DOM assertions and the 106-assertion native suite passed. See [feature usage, privacy boundaries, UI evidence and remaining validation](BROWSER_UPGRADES_2026-10-29.md). Full manual pose/accessibility coverage and hardware acceptance remain open; the blocker is a 19-domain baseline and Reader is text-only.


## UX and review follow-up — October 29, 2026

Reworked URL search into a compact keyboard-adjacent palette, replaced the Peek sheet with native context-menu preview/commit animation, and added a clear Website Protection panel with scoped exceptions. Polished tab/library empty states and preserved the existing glass controls. Reviewed all eleven Copilot findings across PRs #4/#5 and fixed the inherited camera-layout CI regression. See [design changes, comment disposition and verification](UX_POLISH_2026-10-29.md). No merge or release is authorized by this work.

## Status bar setting — October 29, 2026

- Page options exposes a persistent **Time, Signal & Battery** toggle in Debug and Release. It controls the system status indicators independently of full-width page mode and also applies in the tab overview.
- Debug and Release simulator builds and 34 native browser checks passed. Closed-display simulator interaction verified the earlier longer label toggled the indicators on and off; the final shorter label could not be visually rechecked after the Mac locked. Hardware, VoiceOver, and the full pose/accessibility matrix remain to be verified.

## Start page and tab appearance — October 29, 2026

Added a native start page with bookmarks, recent visits, a search shortcut and a private-browsing state, plus a locally saved tab-switcher background color and reset. The page uses existing local library data and does not show normal browsing history in private mode. Debug and Release simulator builds, 36 native browser checks, 62 portable checks and 126 layout checks passed. On a closed Duo simulator the start page and color picker were displayed and a color was applied. Physical-device, VoiceOver and full pose/accessibility coverage remain to be verified.

## Tab stack — October 29, 2026

The overview uses a native UICollectionView stack with reusable page previews, continuous depth compression to the left, UIKit momentum and snapping, and upward swipe dismissal. The same layout drives displayed positions and hit testing. Closing follows the finger without a travel cap, projects release velocity, and uses a critically damped animation; reversing downward cancels, and a returning card can be caught again. Cards fit the available height. Existing glass controls, background color, search, workspaces and privacy separation remain. VoiceOver and accessibility text sizes retain the non-overlapping list; Reduce Motion removes depth/parallax and fades committed closes.

The motion follows Apple's public [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/) guidance on momentum, interruption and non-overshooting springs, using public [UICollectionViewLayout snapping](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/targetcontentoffset(forproposedcontentoffset:withscrollingvelocity:)). The depth curve is our implementation, not Apple's unpublished app-switcher formula.

Verification: final Debug/Release simulator and signed-device builds passed, along with 62 portable checks, 126 browser/DOM checks and SwiftLint. Eight motion-policy assertions passed (continuous speed, order, bounds, momentum, cancellation and Reduce Motion). Seven focused native stack checks passed on the final build: selected-tab entry, fractional scrolling, bounded layout work, animated close, successor placement, reduced motion and resize focus. These checks exercise UIKit layout and close animations programmatically, not synthesized touch gestures.

The full native suite did not pass in this run: one attempt timed out in the upgrade/WebKit checks after reenabling content blocking; a second passed the new stack assertions but timed out waiting for the synthetic TLS error. No test expectations or security behavior were weakened. The overview and multiple preview cards were displayed on the closed Duo simulator; the computer-use drag tool returned `noWindowsAvailable`, so touch-driven horizontal scrolling and swipe-up recognition remain unverified. Final development build installation on the owner's iPhone is recorded in the PR. Physical smoothness/frame pacing, spoken VoiceOver, larger-text/keyboard and the complete open/partial/rotated pose matrix remain acceptance work.


## Tab motion correction — October 29, 2026

Removed all tab-preview outlines, including the selected-tab blue border. Card dismissal now animates an app-owned container instead of UIKit's managed cell content view, preserving the finger offset across collection layout. Committed closes travel upward with a non-reversing exit; canceled gestures retain a catchable return animation. Horizontal depth scaling now eases continuously at the foreground boundary while UIKit continues to handle momentum and snapping.

Debug and Release simulator builds, portable checks, browser/DOM tests and strict SwiftLint passed. The focused native stack harness verifies retained drag offset, monotonic upward presentation during repeated layout, one-time removal, successor focus, fractional scrolling, bounded layout work, Reduce Motion and resize focus. Device Hub inspection confirmed border-free cards; automated drag input was inconclusive, and physical frame pacing remains unverified. No Safari-parity or full hardware/accessibility acceptance claim is made.

## Start-page review corrections — October 29, 2026

The start page is now native-only, with no placeholder WebKit document or competing initial load. Visibility changes at the first navigation commit, preserving the start page on failed or canceled provisional requests without covering site-owned about:blank content. The underlying web view is hidden from accessibility while the native page is visible. Scroll clearance observes the actual toolbar height and runtime camera lift instead of reserving a fixed 120 points.
## Reader and article fitting follow-up — October 29, 2026

- Replaced Reader’s inset SwiftUI column with a full-screen WebKit viewport using runtime camera geometry. Ordered photos/captions, article-header images and visible headlines are extracted with bounded native validation; private image loading stays in the source profile.
- Body text can fit inside non-scrolling horizontal-overflow shells and normal column-flex article layouts. Actual scrollers, clipped content and unsafe flow changes still fall back.
- Verification and remaining live-site/hardware gaps: [Reader layout report](READER_LAYOUT_2026-10-29.md).


## Matched tab zoom — October 29, 2026

The live browser now uses UIKit's public zoom transition from the selected card, reversing into that same card when Tabs is pressed. This replaces the overview's vertical full-screen-cover slide. A presentation coordinator observes session intent even while its SwiftUI source is offscreen, serializes presentation changes, and preserves existing web views. The return source recenters the active card and clears stale tab search. Reduce Motion, VoiceOver and accessibility text sizes use a fade; WebKit retains ownership of pinch and back gestures.

Simulator integration checks pass for initial presentation, zoom out, new-tab presentation, switching back to an existing web view, and reduced-motion return. Device Hub accessibility actions verified the actual Tabs button and card selection. The dismissal regression passed three consecutive runs using an explicit Core Animation exit from the final finger transform, anchored to the current layer clock so delayed layout transactions cannot restart its timing. The owner reported the earlier swipe-close build works well on their phone; physical acceptance of this new zoom remains theirs to check. Apple's API reference: https://developer.apple.com/documentation/uikit/uiviewcontroller/transition/zoom(options:sourceviewprovider:).


The complete local native suite passed for the zoom implementation: stack/zoom, core browsing, Reader/upgrades, camera settling, cookie write/relaunch and memory checks. Review follow-up removes the empty stack from no-results layouts, derives visible cards from their transformed viewport bounds, keeps Close exposed at the leading corner, and preserves committed closes exactly once through filtering or stack teardown. Focused native regressions cover both wide-layout tails and filter/teardown completion. Device Hub selection checks and signed development installation succeeded; final physical zoom acceptance remains owner-driven.

## Address suggestions and first TestFlight preparation — November 8, 2026

Implemented instant bundled website matches, optional DuckDuckGo predictive searches, explicit search-versus-navigation actions, and a completion button for editing a predicted phrase. The keyboard-adjacent native palette retains local tabs/bookmarks/history, Dynamic Type and the original page context. Private tabs use only local suggestions. Network requests have debounce/cancellation, bounded responses, ephemeral storage, no shared credentials/cookies, no redirects, and conservative input exclusions. Added a privacy manifest for local settings and app-container file metadata.

Verification: 33 new portable suggestion assertions and the existing 62 portable checks passed; Debug and Release simulator builds, all browser-layout checks, SwiftLint, and 175 native regression assertions passed. A signed device archive also built. Copilot review findings were addressed, including preserving separate tab identities for identical URLs and empty start-page addresses. TestFlight release provenance will be recorded after Apple processes the upload. Physical touch, spoken VoiceOver, energy/endurance, passkeys and authenticated-site acceptance remain unverified; simulator results do not close those gates.

Manual closed-Duo testing confirmed `g`/`go` → Google, `ap` → Apple, `pat` → Patriots plus live DuckDuckGo predictions, completion-arrow editing, stale prediction removal on replacement input, website navigation, and the software-keyboard layout. This caught and fixed missing scene-phase propagation through the UIKit hosting container: prediction gating now follows UIApplication lifecycle notifications. Screenshots use only synthetic queries.

The partial/open/rotated simulator transitions retained the typed query and the Apple page behind it. Disabling online predictions immediately left only local results. Maximum accessibility text in closed landscape initially clipped controls; the corrected palette gives the input/settings/Cancel priority, hides the redundant submit row when space is insufficient, and scrolls results in the remaining height. Dark appearance and the corrected maximum-text layout were visually checked. Spoken VoiceOver, physical pinch/touch and live system-occlusion changes remain unverified for this feature.

Tapping a live prediction opened the correctly encoded DuckDuckGo search, confirmed through the resulting address and page title. The feature adds no motion; existing reduced-motion native regression checks pass.

## Full-screen glass tab overview — November 8, 2026

Replaced the horizontal tab stack and settings header with a vertically scrolling, full-width preview grid. UIKit hosting now reclaims the Duo safe-area rail at the root. Titles sit below previews, X controls close cards, and deliberate left swipes dismiss them while vertical drags scroll. Search, workspaces and appearance remain in the bottom options menu; the overview hides system status indicators without changing the browsing preference.

The live browser uses the native zoom transition into and out of the selected preview rectangle, excluding its title. The same WKWebView remains alive. Reduce Motion/VoiceOver use the existing dissolve path and accessible tab list. Runtime occlusion geometry moves a covered close button to the opposite corner and lifts bottom controls when required.

A shared app wallpaper appears on the start page and behind material in the overview. Optional photos are explicitly selected through PhotosPicker, downsampled to 1600 pixels and stored locally; no photo-library enumeration, system-wallpaper extraction or network upload is added. Existing custom color choices remain available as a tint.

Verification: Xcode 27.2, iOS 27.1 simulator, unchanged iOS 27.1 deployment target. Debug/Release simulator and signed Release device builds passed, along with portable checks (95 assertions), 167 browser-layout assertions and SwiftLint. The complete native suite passed (grid/zoom, core browsing, upgrades, camera settling, cookie write/relaunch and memory). Device Hub checks verified native zoom, a fast left swipe, X close, vertical scrolling, search/keyboard behavior and closed/partial/open/rotated layouts using synthetic pages. The first full-suite attempt was interrupted by low disk space; reproducible project build caches and the newly created disposable simulator were removed, then verification continued on the existing dedicated Duo QA simulator. See [focused validation](TAB_OVERVIEW_2026-11-08.md) for final interaction evidence and remaining hardware gaps.

Final grid/zoom regressions passed after fixing per-card safe-area clipping and preserving the initial movement of a fast swipe. Development build 4 was installed and launched on the connected iPhone Duo; physical feel remains owner acceptance. The PR remains subject to owner review and merge.

## Google default search — November 8, 2026

At the owner’s request, Google now handles start-page searches, typed address-bar searches and prediction taps through one URL builder. Google also supplies optional autocomplete. The previous provider endpoint, bundled shortcut and UI labels are removed from the application; no fallback to that provider remains. Private tabs still suppress remote predictions. The owner also requested inline website completion with the remaining suffix selected, keyword predictions beneath the top website match, and removal of the bottom provider disclosure/settings row. Google predictions now start with the first eligible letter; the raw typed prefix is preserved separately from the completed address. Backspace dismisses the suffix and Return accepts the visible website. Literal plus signs, punctuation and Unicode remain intact in submitted queries. Historical provider notes above describe superseded builds.

Portable verification passed 111 assertions, including Google destinations, query encoding, first-letter predictions, inline prefixes, response validation and privacy gating. Debug/Release simulator and signed device builds passed; SwiftLint reported zero violations and all 167 browser-layout assertions passed. The native input checks cover suffix selection, continued typing, Backspace, keyword submission and completion acceptance. An initial camera-settling run failed its font-size assertion in the rotated simulator; after returning to portrait, all 34 settling checks passed without changing layout code. The full native suite passed: 23 grid/zoom, 54 core/input, 55 upgrade, 34 settling, 2 cookie-write, 2 cookie-relaunch and 11 memory checks. After the final Backspace handling change, the focused eight-check input suite passed again. Device Hub confirmed `g`/`go` inline completion, Google as the top match, keyword predictions from the original prefix, Backspace dismissal, Return navigation to google.com and removal of the bottom disclosure/toggle. Completion survived closed/partial/open transitions. Start-page typed search and prediction taps were verified to reach Google. Full spoken VoiceOver, maximum-text and IME-keyboard acceptance for inline completion remain unverified.

Development build 6, including Google search, inline completion and the simplified search panel, was installed and launched on the connected iPhone Duo. No merge, TestFlight upload or App Store release was performed.

## Start-page shortcuts — November 8, 2026

Removed the redundant start-page search button so the standard URL bar is the single entry point. Favorites and recent pages previously used hardcoded star/clock placeholders; they now display site favicons, with a domain initial when no valid image is available. Icons are requested directly from the site origin, stripping the saved page path, query and fragment. Ephemeral sessions omit shared cookies and credentials, support at most three secure CDN redirects, cap responses at 1 MiB and decode thumbnails at 144 pixels. A bounded in-memory cache deduplicates origins and is cleared when history/bookmarks are deleted. Private start pages instantiate no shortcut/icon views.

Verification: 111 portable assertions, all 167 browser-layout assertions, zero SwiftLint violations, Debug/Release simulator and signed Release device builds passed. The full native suite passed (18 grid/zoom, 64 core/input/icon, 55 upgrade, 34 settling, cookie write/relaunch and 11 memory checks). Ten added icon checks cover origin-only requests, credential rejection, secure redirects, malformed/oversized images, shared-cookie isolation, decoded dimensions and cache reuse/clearing. Device Hub visually confirmed all eight favorite logos, the sole remaining bottom URL bar and readable dark-logo backings. The final ICO representation selection and contrast adjustment were rebuilt and visually checked with the live shortcuts. Full light-mode/large-text/spoken VoiceOver and hardware accessibility acceptance remain unverified for this change. Low disk space interrupted build startup; only old generated DuoBrowser build caches were removed before retrying.

Development build 7 was installed and launched on the connected iPhone Duo with the simplified start page and site icons. Changes remain in the owner-reviewed PR; no merge or store release was performed.

### November 8 — Retina favorites and external-link preparation

Enlarged favorite tiles to 64 points with a 48-point logo. The initial enlargement exposed 16–32-pixel favicon sources; the loader now discovers ranked mobile touch icons from a bounded, inert public home-page head and compares decoded pixel dimensions with the favicon fallback. It fetches at most four candidate assets, caps each at 1 MiB, downsamples to 144 pixels, and keeps the existing cookie/credential-free ephemeral session and memory-only cache. Reddit's own verified 192-pixel asset supplements its advertised 64-pixel favicon. No icon proxy or page execution is used.

Registered HTTP/HTTPS URL types and added an external-link handler that validates destinations, opens a separate tab, and preserves private mode and existing form drafts. Default-browser eligibility remains **blocked by Apple capability approval**: a signed-device provisioning attempt explicitly rejected `com.apple.developer.web-browser` for `dev.cnichols.duobrowser`. The approval-dependent entitlement is prepared in `Configuration/DefaultBrowser.entitlements`, but deliberately not enabled in ordinary development builds. See `docs/DEFAULT_BROWSER.md` for the request and verification steps. No claim of default-browser picker visibility is made.

Validation: Debug simulator and signed Release device builds succeeded; native core checks increased to 73, including high-resolution selection over a 16-pixel fixture, malformed/unsafe icon references, exact external-link routing, draft preservation and private-store isolation. The complete native suite passed: 18 tab/zoom, 73 core, 55 upgrade, 34 camera-settling, 4 persistent-cookie and 11 memory checks. All 111 portable Swift checks, 167 JavaScript assertions and strict SwiftLint passed. The simulator visual check confirmed sharper logos for all eight favorites. Apple’s signed-in request form was prepared but not submitted because it requires App Store or TestFlight availability; no distribution was authorized or performed.

Signed development build 9 was installed and launched on the connected iPhone Duo; device tooling confirmed version 0.1.0 (9). Physical visual acceptance remains with the owner. No merge, TestFlight upload, App Store release or entitlement request submission occurred.

### November 8 — 1.0.1 TestFlight preparation

Centered shortcut labels and installed/launched development build10 on the connected Duo before continuing the release review, as requested. The owner then authorized TestFlight1.0.1 and a separate release agent. Fixed the seven tab/wallpaper review findings, added in-app/public privacy documentation, and configured web-content-only ATS for arbitrary browser HTTP navigation. Fourteen additional regression checks pass (87 core total). Detailed findings, evidence and explicit hardware limitations are in `docs/reviews/2026-11-08-testflight/README.md`. Apple approval is not presumed; the default-browser entitlement request remains deferred.

### November 8 — beta review follow-up

- Copilot confirmed the seven original findings resolved. Preserved saved prediction opt-outs without restoring the removed UI, measured full footer rows/bottom inset for occlusion avoidance, and retained redirected home-page URLs for Retina icon resolution.
- Debug simulator build, 111 portable checks and strict lint pass. Four native regressions added; updated native suite, CI/review and rebuilt 1.0.1 archive are pending before TestFlight upload.

- Final completed review also found keyboard-safe-area, spanning-island classification and incoming-link-capacity feedback issues. Fixed all three, added four focused regressions, and verified search footer above the software keyboard with clean Cancel dismissal. Independent review passed; final 93-core/13-memory suite and CI are pending before upload.

### November 8 — 1.0.1 TestFlight submission completed

- Centered favorite/recent-item captions were installed and launched on the connected iPhone Duo as build10 before the beta review.
- PR12 merged as `fc324bfcf168c3f8e86acacfc412986c347b3e6e`. The 1.0.1 (11) archive uses source `7ff8f6084e6c8f82d9a264a9e0500cb8c4c9c009`, whose tree is identical to the merge. All required CI jobs passed on that source. Every finding from the completed Copilot reviews was investigated and fixed; independent follow-up review and local/native regression checks passed.
- Final native receipts: 24 tab/zoom, 93 core, 55 upgrade, 34 settling, 4 cookie persistence and 13 memory checks. Maximum-text closed/open controls and software-keyboard footer avoidance were exercised in the simulator. Physical accessibility, credentials/permission combinations, endurance and live occlusion/frame-pacing acceptance remain beta work.
- Upload succeeded. **DuoBrowser Internal: Testing. DuoBrowser Public Beta: Waiting for Review.** This is an external TestFlight review submission, not Apple approval or an App Store release. Default-browser capability remains deferred and absent from signing.
- See the [beta release record](reviews/2026-11-08-testflight/README.md) for provenance, disclosures and remaining limits. These results supersede the earlier pending-validation notes above.

## Guided setup and direct Safari transfer — November 11, 2026

Implemented optional Welcome → Transfer → Default Browser → Tour setup, local progress/category restoration, and Page options reentry. The public BrowserKit integration requests direct transfer only, stages data for review, and preserves bookmark folders, user-designated favorites, history dates, and Reading List entries. No file-export/import steps or credential transfer were added. Library now exposes imported folders and Reading List. Bounded imports deduplicate and reject unsafe/oversized input; private sessions, replay, cancellation, stale completions, and failed writes have explicit handling.

Apple accepted the owner-authorized Default Web Browser entitlement request **Y9UACWK77A**. A signed provisioning attempt confirms access is still pending Apple assignment. The approved-browser build configuration is prepared; ordinary builds explain that transfer/default selection are unavailable and let setup continue. No new TestFlight build, merge, or release was performed. See [the transfer and Apple activation record](SAFARI_TRANSFER.md).

Debug and Release simulator builds passed; 139 portable assertions (28 new import checks), 167 browser/DOM assertions, and strict SwiftLint passed. The complete native suite passed: 23 setup, 24 tabs/zoom, 93 core, 55 upgrades, 34 camera settling, 4 cookie persistence, and 13 memory checks. Device Hub interaction verified the walkthrough, category changes, completion, skip/reentry, and closed/partial/open/rotated continuity. Dark appearance and maximum accessibility text were checked; the initial oversized fixed footer was corrected to scroll with content at accessibility sizes. Real Safari transfer, signed-device default selection, hardware touch/performance, spoken VoiceOver and live system occlusion remain unverified pending entitlement approval and device testing.

The final synthetic review UI was exercised with Favorites mapped and History deselected; it saved one bookmark, one favorite, zero history entries, and one Reading List item. [Verification and screenshot](reviews/2026-11-11-setup/README.md).

- PR #15 review follow-up: preserve distinct same-named source folders with one-to-one destination matching; apply archive file protection within atomic writes so there is no throwing post-commit operation. Portable coverage now totals 148 assertions. Device-only protection-class checks added because the simulator omits that metadata. Initial hosted CI failed during simulator startup before native tests; require passing CI on the corrected head before merge.


## Native Downloads — November 12, 2026

Added Page options → Downloads with filenames, byte progress, per-item Cancel/Retry, Quick Look, Save to Files and explicit removal. Normal files belong to the session and survive tab closure/relaunch; dismissing export keeps the app copy. Private transfers and files are isolated and removed with the last private tab. Safe retry uses a WebKit resume token or the unchanged original webpage context; a fresh data store alone is insufficient to preserve cookie context. No credentials are extracted or POST requests replayed.

Files use bounded UUID directories, sanitized names, protected/excluded-from-backup storage and a manifest without URLs, credentials or resume tokens. Failed deletion remains visible; recovered files have explicitly unverified completion and count toward actual disk limits. See [behavior and boundaries](DOWNLOADS.md) and [review evidence](reviews/2026-11-12-downloads/README.md).

Validation: Debug simulator build, 220 portable assertions (28 new storage checks), 186 browser/DOM assertions and strict SwiftLint passed. All 34 native Downloads checks passed, including authenticated retry, file export dismissal, independent cancellation, source-tab closure, last-normal-tab closure to native Start Page with no loaded WKWebView, stale callbacks and private cleanup. Initial runs found source lifecycle and retry cookie-context issues; both were corrected before this passing run. The full standalone native regression passed. Integrated Debug/Release, 277 portable assertions and 36 Downloads checks passed, including direct attachment/inline handling. Manual UI verified Quick Look contents, Files-picker cancellation retaining the file, Cancel→Retry→completion, large text, dark appearance and fold/rotation continuity. A final scoped suppression of a misleading policy-change error adds a 37th native assertion; its build/run is delegated to the combined Settings stack. Details and screenshots are in the review evidence. Physical touch/energy, iOS suspension, signed Files-provider export and full spoken VoiceOver remain device acceptance work. No merge or release was performed.


Downloads PR review follow-up: GET restart now validates the originating document generation and invalidates old eligibility on navigation, including reload/away-back to the same URL. UUID-directory symlinks are unlinked even when their targets are missing, restoring quota admission without following the target. Portable download coverage passes 32 checks; the combined native run now requires 43 Downloads assertions including the two stale-document cases.
Downloads validation follow-up: an intermittent policy-error assertion exposed an unscoped conversion flag. Suppression now requires the actual failing URL to match a pending download conversion; unrelated or unattributed errors surface, cancellation does not consume the expectation, and document changes clear it. Four attribution checks bring Downloads to 47 native assertions (pending final integrated run). Hosted CI previously timed out before retry/source-close while a focused local 43-check run passed; the cause is not confirmed. That synthetic transfer now holds after its first chunks until an explicit bounded test release/cancel, with stage-specific failure diagnostics and unchanged interaction deadlines. Seven portable gate checks cover independent attempts, release-before-retry and bounded inventory. Debug/Release simulator builds, 319 portable assertions and strict lint passed; the 47-check native run remains delegated to the final combined stack.
The older camera-stack hosted run also timed out waiting for observable unknown-length progress. All synthetic transfers whose assertions require an active window now use the same explicit release protocol, including overlap/cancel, source closure, stale-document retry and last-normal-tab closure. Single-attempt gates clean up on completion; retry gates retain the independent second attempt. Real progress, cancellation, authentication and completion assertions remain required, with the original 10/30-second interaction deadlines and no changes to production transfers.
Focused current-stack Downloads47 passed with these gates. A subsequent Python-only lifecycle correction retains attempt 1 if cancellation arrives before the 64 KB hold; only explicit expiry/final/excess attempts remove it. All 11 portable gate checks pass, including execution of the actual interrupted-response handler, independent retry release, final cleanup and expiry. The early-cancellation regression rejects the prior cleanup behavior. Final integrated native/CI validation must include this correction.
Hosted runs subsequently repeated a first-download timeout and an authenticated retry/source-close failure despite passing local runs. Opt-in DEBUG-only callback observers now let the synthetic harness report bounded, timestamped policy/conversion/transfer/cancellation events and item/tab/file state at those failures. Hooks remain nil during ordinary browsing and are absent from Release; no production behavior, assertion or deadline changed. Debug, 323 portable assertions and strict lint passed, and a newly created disposable simulator passed all 47 Downloads assertions with diagnostics enabled; the hosted failures were not reproduced locally. The next hosted run must establish the failing boundary before any behavioral fix.
Saved-pages review follow-up: archive replacement commits the primary last, saved reading remains available during status-write failure, duplicate-URL edits use IDs, offline cleanup retains both archive generations and retries orphan files, and folder pickers reuse a bounded index. Portable fault/recovery/large-library checks pass; final native verification is pending.

Cancellation review found a separate file-ownership race: Retry could reuse a destination before WebKit's asynchronous cancellation finished. Transfers and pending starts now retain their source until cancellation completion; Retry stays unavailable with “Canceling…” feedback, and removal/private cleanup wait for outstanding file IO. Private data-store cleanup and deletion errors complete even after the session releases its manager. Repeated cleanup requests retain registered completions and ignore unrelated older warnings. Five additional native assertions cover the retry/file-reuse barrier, pending-start removal, active private teardown, staging deletion and repeated cleanup. Every Downloads-suite failure now includes a bounded pre-cleanup snapshot and callback trace, including second-tab conversion. Debug, 323 portable checks and strict lint passed; a fresh default-protection run reproduced a separate conversion stall before WebKit delivered any transfer. An A/B completed the isolated first fixture, then stalled on another still-protected view. Public WebKit source defers download conversion during reputation checks. The DEBUG-only Downloads fixture now excludes that external service using public WKPreferences, with a new assertion preserving the production-enabled default (53 total checks). This suite does not test external reputation effectiveness. The complete isolated fresh iOS 27.1 simulator passed all 53 checks; hosted CI and final integrated validation remain pending. This cancellation fix is not claimed to explain conversion stalls.

Persistence-harness follow-up: the relaunch check now observes actual application background before termination, retains the writer view/profile through that event, and validates a fresh per-run nonce in the first request's cookie as well as document/localStorage. It removes the arbitrary two-second sleep and does not poll authentication into existence after the first request. Debug, 339 portable checks, strict lint and a fresh simulator's five persistence assertions passed; public synthetic logs confirm WebKit entered network suspension preparation. This verifies background→termination→relaunch, not crash durability. No production persistence code changed; hosted and final integrated verification remain pending. Details are in the browser-settings review record.

Consolidated native-harness follow-up: fixture loading now verifies a new actual document via an isolated-world marker plus exact document URL/readiness; the camera helper awaits the correct async API. Website-data refresh precedes the eight-second Undo window, and valid deletion checks live-Undo release synchronously around the original callback. Downloads retain synchronous diagnostics by default; extra cookie/document IPC snapshots require an explicit diagnostic flag. Debug, strict lint, focused core93 and the complete fresh iOS 27.1 simulator run passed using Xcode 27.2. Combined source `3103706` plus the v2 harness patch passed **504 assertions in 11 batches**, including Downloads53, Settings48, Setup37, Reddit29, tabs24, core93, upgrades160, camera42, cookie write2/read3 and memory13. Default non-awaiting diagnostics preserved both authenticated 544,000-byte retry/close completions; scroll400 was captured/restored. The original hosted authentication failure's exact cause remains unproven and no production authentication behavior changed. Latest hosted CI remains pending; details are in the browser-settings review record.

Settings fixture separation: the clear-data suite seeds a real completed `DownloadStore` file/manifest before session construction, verifies production restoration of the exact item/path/bytes, and requires that same file after clearing. Real network conversion/authentication coverage remains in Downloads53; no production protection or timeout changes. Debug, strict lint, independent source review and fresh Settings49 validation pass on a disposable iOS 27.1 simulator. The original hosted Settings transfer timeout's cause is unproven.

Download fixture follow-up: explicit-release gates now share the 600-second outer batch budget and still abort on expiry; client interaction deadlines and predicates are unchanged. Synchronous waiter/item-identity diagnostics add no IPC barriers. All 11 portable gate regressions, strict lint, independent review, Debug build and fresh Downloads53 pass; both source-close retry variants completed 544,000 authenticated bytes. Settings49 passed separately on a fresh simulator. These are focused follow-ups, not another full combined run; the prior 504-check result remains the full-stack evidence. The hosted scheduling failure's exact cause remains unproven, and latest hosted checks remain required.
