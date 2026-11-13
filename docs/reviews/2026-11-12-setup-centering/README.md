# Setup centering — November 12, 2026

The owner’s screenshot showed the introduction aligned to the narrower camera-safe region instead of the display. Every setup step inherited the same asymmetric horizontal safe area.

Setup now uses the full horizontal bounds while preserving vertical safe-area behavior. Welcome, transfer, default-browser and tour headings and actions share that center axis. Progress has an independent centered position, so different Back and Skip widths cannot shift it. Transfer rows retain readable leading alignment inside the centered column. Accessibility-sized actions remain in the scroll view.

Only top controls that actually overlap an active system occlusion receive vertical clearance. UIKit’s returned reserved-region frame already includes system margins; it is used directly. The shared navigation row moves below those rectangles, leaving the page’s horizontal axis unchanged. Multiple regions are ordered by their bottom edge so clearing a lower control cannot move a higher control into a previously skipped tall region. No camera position, pose-width rule or persistent full-height camera rail is introduced. Measurements use the setup coordinate space and remove existing clearance before recalculation to avoid oscillation.

Setup has one SwiftUI hosting coordinate space. Its unused NavigationStack was removed; custom Back/Skip navigation, interactive-dismiss protection and the scene reference for Safari transfer remain. The full-width reader and the measured controls live inside the same horizontal expansion. Debug-only UIView probes independently convert the actual rendered heading, action, progress and canvas bounds into their UIWindow; native tests compare these with the hosting view’s physical window bounds. This caught an ambiguous earlier cross-host coordinate measurement and verifies both left- and right-side asymmetric safe areas without weakening the centering assertions.

Thirteen new native assertions exercise obstruction clearance, an unoccupied camera edge, multiple obstructions, staggered controls, all four steps with left/right asymmetric safe areas and maximum accessibility text. Existing setup transfer, cancellation, review, persistence and reentry checks remain in the same batch. All 37 focused Setup checks pass on the final product/probe source `b394999`. Debug and Release simulator builds pass on that source; 328 portable assertions and strict lint also passed before the final fixture-only upstream merge. The ultimate combined-stack receipt is recorded below.

## Visible simulator evidence

The final Debug app was installed on the isolated iOS 27.1 Duo QA simulator, using `--browser-checks --setup-preview` and synthetic transfer data. These captures show the final single-host source; native captures exclude Device Hub’s physical bezel overlay.

- [Welcome, closed portrait](welcome-closed.png): heading, body, illustration, progress and primary action share the full display’s center.
- [Transfer, open display](transfer-open.png): centered heading and actions, with leading-aligned transfer rows inside the centered column.
- [Default browser, partially folded](default-partial.png): centered content in the active app presentation; the other portion of the native display capture is black.
- [Tour after rotation](tour-rotated.png): title, progress and primary action remain centered; instruction rows remain readable.
- [Tour, maximum text](tour-large-text.png): centered wrapping and unclipped top navigation; remaining content and the primary action are below the viewport in the scroll view. A manual full scroll-to-action interaction was not recorded.

Get Started, Not Now, Continue and Back were exercised. Back returned from the tour with Reduce Motion enabled. The simulator was restored to closed portrait, Dark appearance, Text Size 3, Reduce Motion off, VoiceOver off and keyboard capture off before the final suite handoff. Full spoken VoiceOver, keyboard/pinch behavior, hardware touch/battery, and real Safari transfer eligibility are not established by these screenshots or synthetic checks.

## Handoff validation

The correction from PR #23 was merged normally into the complete setup branch.
It waits for committed native/DOM fixture geometry before native scrolling;
production browser behavior and the existing Reddit handoff assertions are
unchanged. The [diagnostic record](../2026-11-12-camera-settling/README.md#november-12-handoff-reddit-scroll-readiness)
distinguishes the observed readiness gap from the unreproduced hosted timeout.

A fresh complete run of `bash scripts/native-checks.sh` on source
`41a8431f539e11fb02817d5c7870e677207da691` passed **505 assertions in 11 batches**:
Downloads53, Settings49, Setup37, Reddit29, TabStack24, Core93, Upgrades160,
Camera42, persistent-cookie write2/read3 and Memory13. The
[fresh receipt](handoff-native-receipts.txt) supersedes the earlier 494-assertion
checkpoint below. Individual synthetic receipts are retained locally under
`work/handoff-native-receipts/`.

Combined Debug and Release simulator builds, all 339 portable checks and pinned strict SwiftLint passed.
All 197 web assertions passed in the camera branch; `git diff --exit-code`
confirmed identical JavaScript, web-test and package sources in this combined
branch. Local verification uses Xcode 27.2 and the iOS 27.1 simulator; hosted CI
continues to use Xcode 27.1 and must pass independently. CI builds use `-jobs 2`.
Latest-head CI/review is recorded in PRs #18–24, with final signed-device source,
signature, installation and launch provenance under ignored `work/final-device/`.
At this checkpoint installation was gated on those checks. The owner subsequently
requested installation during CI work and authorized merging after green checks;
the Undo follow-up below records that change. The same bundle/signing identity
and disabled default-browser entitlement are retained. TestFlight remains on hold.
The hardware/accessibility limits above remain.

## Undo follow-up validation

The owner found a missing overview card after closing a tab and using Undo.
The [tab-recovery report](../2026-11-12-tab-recovery/README.md#undo-overview-card-follow-up)
records the reproduced defect, bounded card-motion fix and removed download
authentication retry/source-closure scenarios. Production download code is unchanged.

The complete corrected source `ba78f5b30a918367069eb52b9fd26d8c01f1bf98` passed
**517 native assertions across 11 batches** on a fresh iOS 27.1 Duo simulator:
Downloads49, Settings49, Setup37, Reddit29, TabStack40, Core93, Upgrades160,
Camera42, persistent-cookie write2/read3 and Memory13. The full script exited 0;
Debug, 339 portable checks and pinned strict SwiftLint passed. The 197 passing web
assertions remain applicable to identical JavaScript, web-test and package sources.
The [receipt](undo-native-receipts.txt) supersedes the preceding 505-check checkpoint.
An independent review found no blocking issue in the Undo patch. Existing Copilot
threads were rechecked and resolved; those reviews predate this latest patch.

At the owner's request, source `47e02da` was installed over the existing app on
the connected Duo and verified running while CI investigation continued. The
Undo-corrected signed build and its installation are tracked under ignored
`work/final-device/undo-*`. Latest-head hosted CI remains an independent merge
gate. The owner authorized merging when green, with TestFlight held for device
review. No physical motion, endurance or spoken VoiceOver pass is inferred from
the simulator regression or a successful app launch.

The signed Release build from the clean immutable `ba78f5b` checkout passed with
`-jobs 2`. Strict signature, target provisioning, profile validity, bundle/version
and bundled filter/license checks passed. Version remains 1.0.1 (12); the
default-browser entitlement and direct Safari transfer remain disabled.

## Combined seven-feature validation

This record is the final integration checkpoint for maintained content filters, tab recovery/navigation, saved pages/offline reading, downloads, Browser/Website Settings, camera settling and full-display setup. Earlier feature reports preserve the checks available at their own checkpoints; their statements that later regressions await integration are historical and are superseded by the final combined receipt recorded here.

The first final-stack attempt passed Downloads47 and caught a Website Settings harness readiness race. WebKit already reported the requested `localhost` URL while its actual `isLoading` was true and the published model loading flag still described the previous document. The test now waits for WebKit to finish and the actual document to report the expected hostname and complete readiness. Its stale-scope and other-host preference assertions are unchanged. Focused Settings48 then passed; this is a test synchronization correction, with no production behavior change (`8467b81`).

The final combined native run on source `9f07d1ae3773c650a5b3d2f391e5f484756228d1` passed with exit 0: **494 assertions across 11 batches**. Counts are Downloads47, Settings48, Setup37, Reddit29, TabStack21, Core93, Upgrades160, Camera42, persistent-cookie write2/read2 and Memory13. The [combined receipt](combined-native-receipts.txt) preserves those results; the [focused setup receipt](setup-window-receipt.txt) names the independent physical-window assertions. The latest repository/portable run passed 339 assertions, including the synthetic download gate regressions; pinned SwiftLint passed. Debug passed on the final integrated source. Product Release passed at `b394999`; subsequent changes are test readiness, fixture reliability and this evidence only. Latest-head hosted CI and final exact-commit signing/device installation remain pending and are tracked in the PRs. Hardware touch, motion quality and energy use, actual Safari transfer entitlement/installation behavior, and full spoken VoiceOver remain separate device-validation work. These results do not imply a merge, device installation, TestFlight submission or App Store approval.


Feature-specific behavior, screenshots and remaining interaction limits remain in their reports:

| Feature | Evidence |
| --- | --- |
| Maintained content filters | [Filter behavior, converter and native UI](../2026-11-12-content-blocking/README.md) |
| Tab recovery and navigation | [Undo, Recently Closed and navigation](../2026-11-12-tab-recovery/README.md) |
| Saved pages and offline reading | [Saved library and offline article](../2026-11-12-saved-pages/README.md) |
| Downloads | [Transfers, retry and lifecycle](../2026-11-12-downloads/README.md) |
| Browser and Website Settings | [Data removal, preferences and website scope](../2026-11-12-browser-settings/README.md) |
| Camera avoidance and settling | [Long content, interruption and Reduce Motion](../2026-11-12-camera-settling/README.md) |
| Full-display setup | Visible evidence and physical-window assertions above |
