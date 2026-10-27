# Research and evidence

Checked October 26, 2026. Distinguish official capabilities, local observations, third-party reports, and proposals.

## Brim

- [Brim's own landing page](https://brim.joogps.com/) describes a Duo browser that relocates website buttons obstructed by the camera. It links to a public beta and identifies João Pozzobon as its creator. The page was read directly over HTTPS; the web search reader could not fetch it.
- [Brim's TestFlight listing](https://testflight.apple.com/join/zJFXVSDY) describes its first version as providing automatic status-bar avoidance. No beta was installed or joined.
- A [community announcement](https://www.reddit.com/r/iPhoneDuo/comments/1xg7mup/new_browser_that_fixes_the_two_worst_things_about/) reports on-device Apple Intelligence and bottom URL placement. This is a third-party report, not verified engineering documentation.

Conclusion: Brim's stated camera-avoidance behavior is confirmed by its creator's page. Its model, prompt, geometry handling, animation, and exact CSS strategy remain unknown. The architecture in this repo is our proposal, not a claim about Brim's source code.

## Duo layout

[Apple's Duo design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) describes asymmetric layouts and reserved camera/fold regions. [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) introduces public iOS 27.1 reserved-region APIs for custom edge-to-edge interfaces. [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/) provides companion guidance.

[UIView.ReservedRegion](https://developer.apple.com/documentation/uikit/uiview/reservedregion) exposes geometry, margins, kind, and active state. Use occlusion regions for covered areas and division regions for the fold; do not replace those distinctions with a guessed fixed sidebar width.

The installed SDK independently confirms, in UIKit's arm64 simulator Swift interface:

```swift
@available(iOS 27.1, tvOS 27.1, visionOS 27.1, *)
func reservedRegions(
    kind: UIView.ReservedRegion.Kind,
    options: UIView.ReservedRegion.QueryOptions = []
) -> [UIView.ReservedRegion]
```

Regions expose `frame`, `margins`, and `isActive`; kinds include `.occlusion` and `.division`. SwiftUICore also exposes `ReservedRegion`. This establishes SDK availability, not verified runtime behavior in our app.

## WebKit

[WebKit's safe-area article](https://webkit.org/blog/7929/designing-websites-for-iphone-x/) explains the relationship between edge-to-edge pages, viewport metadata, and selective safe-area padding. It is useful background, not a measurement of Duo behavior.

[WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld) separates JavaScript namespaces while leaving DOM changes visible to all script worlds. Isolation is useful for our bridge, but does not make page mutations invisible or trustworthy. [WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller) is the API entry point to investigate for scripts and message handling.

## On-device intelligence

[Apple's Foundation Models guidance](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) requires availability checks and a fallback, and lists code generation among unsuitable tasks for the on-device model. [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation) supports structured output.

Engineering inference: use a bounded classifier to choose among known layout actions, with deterministic geometry and validation. Free-form generated CSS and continuous inference are poor starting points. This recommendation still needs comparative testing.

## Browser capabilities and distribution

[Preparing an app to be the default browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser) describes the managed capability and expected navigation/content behavior. [The browser entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser) and [passkey entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential) are distinct capabilities to assess.

These references do not establish that a particular adaptation design will receive approval. No entitlement was requested. Rendering with WebKit is a practical starting point, not proof of Safari feature parity.

## Local setup observations

`xcodebuild -version` reported Xcode 27.1 (27A9275). `xcrun simctl list devices available` listed iOS 27.1 Duo devices, including an already booted iPhone Duo. After the owner approved the design direction, a starter app was added and its simulator build passed. A dedicated DuoBrowser QA simulator was created. See VALIDATION.md for runtime verification and remaining gaps.

The app's current project tool inventory supports listing projects and moving chats to existing projects, but not creating a local project. Computer Use returned: “Computer Use is not allowed to use the app 'com.openai.codex' for safety reasons.” No bypass or app-state edit was attempted. [Official project documentation](https://learn.chatgpt.com/docs/projects) describes associating local folders with projects.
