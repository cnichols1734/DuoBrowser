# Camera avoidance and gradual settling

The owner reported text remaining beneath the camera and abrupt motion. The
simulator review reproduced a long paragraph beneath the camera with Original
Layout off and full width on, under both Reduce Motion settings. The updated
production browser now keeps that long text clear of the camera.

The previous fitter rejected every paragraph taller than 320 CSS pixels, even
when ordinary text had room beside the camera. Validated side fitting now accepts
bounded longer paragraphs: at most two viewport heights (capped at 1600 pixels),
with no more than 160 pixels of height growth. Existing character, text-node,
line-count, overflow, containing-block, reading-anchor and destination checks
remain. It still falls back for unsafe or overly complex layouts.

Page mutations now coalesce without continually resetting the quiet timer, and
unrelated mutations wait for an active settling animation to finish. Pointer and
scroll events still freeze the current presentation and restart the quiet period.
Geometry retargeting starts from the measured current presentation. The 420ms
horizontal transform uses a gentler curve; the prior curve completed about 75%
of its movement in the first 100ms. Width is committed once after scrolling stops;
no width interpolation, glyph scaling, DOM replacement, page-content persistence,
or artificial blank space above the paragraph is introduced. Reduce Motion keeps
static avoidance; VoiceOver retains the existing conservative text behavior.

## Verification

- All 197 web assertions pass, including eleven added checks for long text, static
  Reduce Motion, original DOM/form preservation, continuous mutation activity,
  uninterrupted animation completion, gradual progress, touch interruption, a complete quiet period after release, and reverse settling.
- All 328 portable assertions and strict SwiftLint pass. Debug simulator build
  passes; the final incremental build includes the new native interruption check.
- Eight added native assertions cover a long article intersecting an actual system
  occlusion, the production `ViewportView` geometry bridge, gradual interpolation
  and interruption, retained DOM/draft/font, Original Layout reversal and static
  Reduce Motion. All 42 focused native camera assertions passed. A review follow-up sets Original
  Layout after navigation applies site preferences and waits for reversal before
  capturing the unadapted baseline; the focused rerun verifies that ordering.

## Production UI inspection

On the closed iOS 27.1 Duo QA simulator, the actual address field loaded the
synthetic `/upgrades?camera-review#camera-reading` page. The paragraph anchor
positions the long article beneath the system camera reproducibly. Screenshots
show [camera avoidance](long-article-avoided.png), [Original Layout restoring the
authored width](long-article-original.png), and [static avoidance with Reduce
Motion enabled](long-article-reduce-motion.png). Website Settings controls were
actually toggled; Full-width Page remained on. Reduce Motion was restored off.

Device Hub scrolling returned `windowNotFoundAtPosition`, so this pass does not
claim a manual scroll gesture or motion recording. Web and native interpolation
checks establish bounded motion behavior; they do not establish frame rate,
physical-device performance, battery behavior, universal site adaptation or a
full spoken VoiceOver pass. Final combined-stack validation is tracked separately.

## November 12 handoff: Reddit scroll readiness

Hosted PR #23 at `ba26e98` timed out before the synthetic Reddit handoff, while
waiting for the native scroll offset to match an earlier DOM value. The unchanged
local baseline passed all 29 Reddit assertions. Three diagnostic runs also passed
29 assertions each, but consistently exposed stale native geometry after document
readiness: content size was initially 980 × 1426 with a 466 × 678 viewport, then
became 466 × 2238 after two animation frames. These runs establish a readiness
gap; they do not reproduce or establish the complete cause of the hosted timeout.
Local receipts are `work/reddit-diagnostic-{1,2,3}.txt`.

The test now waits for matching native and DOM content dimensions and viewport
geometry at the fixture's declared scale of 1, then scrolls the native scroll view
to 200 and requires both native and DOM offsets to acknowledge that position.
All handoff assertions and the original 10-second interaction waits remain;
failure diagnostics report synthetic viewport and scroll geometry. This follow-up
changes no production browser behavior. CI compilation now uses `-jobs 2`.
The corrected Debug build passed on Xcode 27.2 / the iOS 27.1 simulator. Three
fresh app launches each passed Reddit29, followed by Camera42; all 339 portable
checks, all 197 web assertions and pinned strict SwiftLint passed. Receipts are in
`work/reddit-corrected-{1,2,3}.txt`, `work/camera-corrected.txt`,
`work/corrected-portable.log`, `work/corrected-web.log` and `work/corrected-lint.log`.
Final combined validation and hosted CI/review are tracked in the setup branch;
installation uses a newly signed build of its final commit after those gates pass.
