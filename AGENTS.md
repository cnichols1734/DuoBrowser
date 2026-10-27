# DuoBrowser project instructions

## Intent

Build a native iOS browser for iPhone Duo. Prioritize usable space on the closed outer display, reliable browsing, and polished motion. Safari is the quality benchmark. Brim is a researched reference, not a specification of its implementation.

Read README.md and docs/ROADMAP.md first. Consult docs/PRODUCT_BRIEF.md, docs/ARCHITECTURE.md, docs/RESEARCH.md, and .impeccable.md before changing the design or architecture. The owner approved the initial brief's direction on October 26, 2026. Continue the staged implementation plan; do not treat that as proof of runtime behavior.

## Engineering

- SwiftUI for the app shell; UIKit-backed WKWebView where viewport and lifecycle control are needed. Start with iOS 27.1; document any later compatibility decision.
- Use public SDK APIs. Read reserved-region geometry and margins at runtime; never hardcode a camera position or infer pose solely from screen width.
- Preserve navigation, zoom, focus, text, form values, links, and accessibility when changing page layout.
- Make every page adjustment bounded and reversible. Provide an original-layout mode and conservative fallback.
- Treat pages and model responses as untrusted. No generated JavaScript/CSS execution, broad native bridge, credential extraction, or page-content telemetry.
- AI is optional. The browser and geometry-based adaptation must work without Apple Intelligence.
- Keep private browsing data, diagnostics, and adaptation caches isolated and ephemeral.
- Do not claim Safari parity, hardware QA, or App Store approval without evidence.

## Verification

For browser implementation, build the simulator target and exercise the affected real interactions. Add meaningful tests for geometry conversion, rollback, stale work, bridge validation, and privacy boundaries. Prefer reproducible synthetic fixtures to tests that depend only on live sites.

Check closed/open/partially folded poses, rotation, keyboard, pinch zoom, Reduce Motion, VoiceOver, larger text, and system occlusion changes. Simulator checks do not replace hardware checks for touch, battery, performance, or Apple Intelligence.

Keep scratch files and build products in ignored work/ or DerivedData/. Record outcomes and remaining gaps in the roadmap. Never upload browsing data. The owner authorized preparation of the existing private GitHub repository for open source on a dedicated branch and PR. Do not change visibility without explicit final approval. All changes go through PRs; the owner retains merge and release authority. Follow CONTRIBUTING.md, SECURITY.md and RELEASING.md. Do not weaken protections, add collaborators or publish an App Store build to work around a blocked review.
