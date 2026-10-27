# Contributing to DuoBrowser

Help make everyday browsing reliable on the Duo's outer display. Small, focused changes are easier to review. For a substantial feature, discuss the problem in an issue before building it. The browser stays free, minimal, and focused on privacy: no ads, subscriptions, paid features, or tracking.

## Submit a change

1. Fork the repository into your GitHub account and clone your fork.
2. Create a branch: `git switch -c fix/describe-the-change`.
3. Follow the build instructions in [README.md](README.md). Keep signing and local machine settings out of Git.
4. Make a focused change and run the relevant [checks](Tests/README.md).
5. Push your branch and open a pull request against `main`. Explain the problem, solution, verification, and any remaining gaps. Include before/after screenshots for UI changes, with personal data removed.

Every contribution goes through a pull request. Passing checks or submitting a PR does not guarantee acceptance. Christopher Nichols (`@cnichols1734`) retains final authority over direction, merges, and releases. His account has a review-only exception for merging PRs without a second reviewer; PRs and passing CI remain mandatory. Other maintainers receive authority only through an explicit owner decision. Do not merge, enable auto-merge, or publish a release on the owner's behalf without explicit authorization.

## Coding conventions

- Use SwiftUI for the shell, UIKit where native geometry/lifecycle control is necessary, and WKWebView for browsing. Use public Apple APIs.
- Follow nearby Swift naming, four-space indentation, explicit access boundaries and main-actor isolation for UI. Prefer small functions and clear state ownership. Run the checked-in SwiftLint rules; avoid unrelated formatting churn.
- Use runtime display geometry. Do not hardcode a camera position or assume device pose from width.
- Keep page adjustments bounded, reversible and conservative. Preserve focus, form values, navigation, zoom, hit testing and accessibility. Treat page content as untrusted.
- Keep credentials inside system/WebKit flows. Never add credential extraction, telemetry, generated JavaScript execution or a broad native bridge.
- Keep private data ephemeral. Do not log URLs, page contents, passwords, cookies or personal browsing state. Use synthetic fixtures for tests.
- Do not add a dependency without explaining its necessity, license and security implications. Commit exact versions and lockfiles for development tools.

## Testing expectations

Run `scripts/check.sh`, `npm ci --ignore-scripts`, `npx playwright install chromium`, and `npm test`. Run SwiftLint 0.65.1 with `.swiftlint.yml`. Build Debug and Release using Xcode 27.1. For browser changes, run `scripts/native-checks.sh` on an isolated simulator; it creates and removes its own test device.

Exercise affected UI on closed, open and partially folded displays, including rotation, keyboard, larger text, VoiceOver and Reduce Motion. Record what you actually tested. Simulator success is not evidence of physical-device passwords/passkeys, energy use, camera/microphone/location permissions or App Store eligibility. Do not invent passes for unavailable hardware.

CI uses disposable GitHub-hosted machines, read-only tokens and synthetic fixtures. Never run unreviewed external PR code on a personal machine or self-hosted runner with credentials. Review workflow and dependency changes before approving a fork's Actions run.

## Report a problem or propose a feature

Use the relevant issue template. Include app commit, Xcode/iOS version, display pose, reproducible steps, expected behavior and actual behavior. Website/layout reports should use a public URL without tokens or personal query strings. Try Original Layout and report whether it changes the result. Redact screenshots and logs.

Use Discussions for general questions and ideas. For exploitable vulnerabilities, use the private process in [SECURITY.md](SECURITY.md), never a public issue. Participation follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

By contributing, you agree that you have the right to submit the work and that your contribution is licensed under this project's MIT license. Identify third-party material and retain its original notices; do not submit code or assets you cannot license.
