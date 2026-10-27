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

The Device Hub UI remained on another simulator. Attempts to select the new simulator were rejected after the tool detected user changes, so no interactive browser checks are claimed. Attempts to open Xcode through Computer Use timed out; the project file is available to open manually.

Run the app on DuoBrowser QA, then check:

1. Fixture content loads, its test button works, and keyboard input retains its value.
2. Full-width and safe-area modes change the actual CSS viewport as expected.
3. Reserved-region overlays track the camera and fold across poses.
4. URL/search entry, back/forward, reload/stop, errors, and new-window links behave correctly.
5. Keyboard, pinch zoom, rotation, and the last lines of a page remain usable.

The starter has no automated UI suite yet. Camera-avoidance behavior, AI, native accessibility review, hardware performance, energy, private browsing, tabs, and Safari comparison are future milestones. No area-gain percentage or Safari-equivalence claim is established.

## Project registration

The Git repo and Xcode project exist locally. They have not been registered as a project in the chat app, and this chat has not been moved. The available tools cannot create a local project; Computer Use explicitly disallows controlling the Codex app. Add the repo folder manually using the path in README.md.
