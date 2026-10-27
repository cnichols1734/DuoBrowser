# Licensing and dependency inventory

Project-owned source, documentation and artwork are MIT-licensed, copyright 2026 Christopher Nichols, except where a file retains another license below. The owner confirmed permission to publish the supplied globe/book icon under MIT on October 27, 2026. Earlier generated icon revisions remain in history. The MIT license does not grant rights to Apple, website or other third-party trademarks or content.

| Component | Scope | License / treatment |
| --- | --- | --- |
| SwiftUI, UIKit, WebKit, Foundation, Combine and Darwin | Apple system frameworks; not vendored | Apple SDK/system terms; not relicensed by this repository |
| Contributor Covenant 2.1 | `CODE_OF_CONDUCT.md`, adapted with reporting contact | CC BY 4.0; original attribution retained, [source](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html), [license](https://creativecommons.org/licenses/by/4.0/) |
| Playwright 1.64.1 / playwright-core | Development-only browser layout tests | Apache-2.0; npm lockfile pins versions and integrity. Downloaded browser binaries have their own notices and are not distributed with the app. |
| SwiftLint 0.65.1 | CI/local static analysis | MIT; downloaded release verified by SHA-256 |
| Gitleaks 8.30.1 | CI/local secret detection | MIT; downloaded release verified by SHA-256 |
| actionlint 1.7.12 | Workflow validation | MIT; downloaded release verified by SHA-256 |
| actions/checkout, actions/setup-node | GitHub-hosted CI actions | MIT; pinned to full commit SHAs |

There are no third-party runtime packages, package-manager dependencies, copied vendor libraries, or remote application services bundled with DuoBrowser. Development tools are downloaded, not vendored into the application. Their original licenses continue to apply. Any future dependency must receive a license/security review and an inventory update before merge.

The README screenshots in `docs/images/` illustrate browser behavior using Apple.com. Website images, text and trademarks appearing inside those screenshots are not relicensed under MIT. They remain the property of their respective owners. The screenshots show development simulator output, not Apple endorsement or hardware certification.

MIT permits commercial use by downstream recipients. The official DuoBrowser project's commitment to remain free, without ads, subscriptions, paid features or tracking, is a project policy; it does not add restrictions to the MIT license.
