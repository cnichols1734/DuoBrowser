# Starter validation

October 26, 2026, America/Chicago.

## Confirmed

- Xcode 27.1 Debug simulator build succeeded for arm64 and x86_64 using the shared DuoBrowser scheme and iOS 27.1 deployment target.
- No Swift compiler warnings remained after correcting the WebKit navigation decision-handler actor annotation. Xcode emitted its standard AppIntents metadata-skipped notice because this app has no AppIntents dependency.
- A dedicated **DuoBrowser QA** iOS 27.1 simulator was created and booted. Identifier: `3ABC97EF-86C9-42F1-A7CF-63089F2FD617`.
- `simctl install` succeeded and `simctl appinfo` confirmed `dev.local.DuoBrowser`, version 0.1.0 (1).
- `simctl launch` succeeded and returned process ID 73046. This confirms launch, not completed interaction testing.
- Local documentation links and Git whitespace checks passed.

## Still to verify

During the initial setup, the Device Hub UI remained on another simulator. Attempts to select the new simulator were rejected after the tool detected user changes. Attempts to open Xcode through Computer Use timed out; the project file is available to open manually. The subsequent full-width verification below supersedes the initial visual-inspection gap for closed-display rendering only.

Run the app on DuoBrowser QA, then check:

1. Fixture content loads, its test button works, and keyboard input retains its value.
2. Full-width and safe-area modes change the actual CSS viewport as expected.
3. Reserved-region overlays track the camera and fold across poses.
4. URL/search entry, back/forward, reload/stop, errors, and new-window links behave correctly.
5. Keyboard, pinch zoom, rotation, and the last lines of a page remain usable.

The starter has no automated UI suite yet. Camera-avoidance behavior, AI, native accessibility review, hardware performance, energy, private browsing, tabs, and Safari comparison are future milestones. No area-gain percentage or Safari-equivalence claim is established.

## Full-width follow-up — October 26, 2026

- The owner's screenshot showed the fixture at 382 × 644 CSS pixels, with a full-height white strip on the right. The model's full-width flag was false, so the web view was constrained to its safe-area layout frame.
- Full-width rendering is now on by default in both model and viewport view. The status bar is hidden in this mode, and the menu calls the option “Full-width page”. Switching it off restores the conservative comparison mode.
- The updated simulator build passed, with no Swift compiler warnings. The AppIntents metadata-skipped notice remains expected.
- Installed and relaunched on DuoBrowser QA. Visually inspected a live Apple webpage filling the closed display from left to right, with no dedicated blank right-hand strip and no clock/connectivity indicators over the page. The bottom browser controls also occupy the available width.
- Camera avoidance is still separate work: this change removes the full-height gutter, but does not relocate arbitrary site controls around the physical camera.
- A follow-up attempt to select the local test page was rejected after a user UI change. No new CSS-width measurement, open-pose, keyboard, pinch-zoom, or automated interaction result is claimed for this pass.

## Scrolling controls follow-up — October 26, 2026

- Disabled automatic safe-area adjustment of the native vertical scroll indicator and set its right inset to zero. During native scrolling, the indicator was visually confirmed at the display's right edge, including with the keyboard open.
- Added a direction-aware scroll policy: sustained downward movement collapses the controls to a site-name pill; upward movement, returning to the top, tapping the pill, navigation, or an error restores the controls. Separate thresholds avoid flicker on small reversals. Page dimensions and the bottom content inset remain stable during the transition.
- A native fast-fling check exposed a first-event overshoot at the page bottom. The policy now compares clamped offsets, counting the real travel while ignoring elastic bounce. Regression checks cover both overshoot and rebound.
- All 16 portable scroll-policy checks passed. They cover directions, thresholds, bounce, fast flings, short pages, programmatic scrolling, tap-to-reveal during deceleration, and expansion suppression. See `Tests/README.md`.
- The final Debug simulator build passed with no Swift compiler warnings; the AppIntents metadata notice is expected. Installed and relaunched the resulting app on DuoBrowser QA.
- Native interaction checks passed on the closed Duo fixture: downward scroll collapsed the controls; tapping the pill restored them; a new downward scroll collapsed them again; upward scroll restored them. URL editing showed the keyboard and kept full controls visible during further scrolling. Submitting the empty field dismissed the keyboard without navigation.
- The full-width fixture reported **466 × 678 CSS pixels at scale 1** with the keyboard closed, and **466 × 413** with URL entry active. This is a fixture measurement, not a Safari comparison or a usable-area percentage.
- The transition respects Reduce Motion in code, and VoiceOver/accessibility text sizes keep controls expanded. Native VoiceOver, larger-text, Reduce Motion, pinch zoom, rotation, open/partially folded poses, and physical-device motion/performance checks remain outstanding for this change.

## Project registration

The Git repo and Xcode project exist locally. They have not been registered as a project in the chat app, and this chat has not been moved. The available tools cannot create a local project; Computer Use explicitly disallows controlling the Codex app. Add the repo folder manually using the path in README.md.
