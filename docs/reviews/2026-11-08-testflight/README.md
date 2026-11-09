# DuoBrowser 1.0.1 beta review

The owner authorized external/public TestFlight preparation and submission on November 8, then explicitly requested a separate release agent for version **1.0.1**, internal testing at minimum. Production App Store publication and the default-browser entitlement request remain outside this submission.

## Findings and fixes

| Priority | Finding | Result |
| --- | --- | --- |
| P1 | Search Cancel and accessible-list Close could overlap runtime camera regions | Runtime-derived edge clearance for search/list controls; grid keeps full screen |
| P1 | Tab Close measured the wrong physical corner in RTL; moving to the other top corner could still be obstructed | Check semantic trailing then leading candidates and lower clear rows against every active region; fully covered cards retain context-menu/swipe fallback |
| P1 | Photo removal/replacement could be overwritten by an older import | Selection/cancellation checks plus store generation token; removal invalidates work; successful/failed imports reset selection |
| P1 | Photo size checked only after allocating entire image | File representation checks file size before ImageIO downsamples within the provider file lifetime; no full-image Data or retained temporary copy |
| P1 | Arbitrary wallpaper could obscure start-page/preview text | Appearance-aware 72% contrasting scrim for photos and primary text styles for exposed copy |
| P1 | Missing accessible in-app privacy policy | Native policy sheet under Page options plus public PRIVACY.md; explicitly describes Google predictions, icon hosts, local storage, deletion and private limits |
| P1 | General-purpose HTTP web content lacked explicit ATS configuration | Web-content-only ATS exemption, with review justification; native URLSession ATS and system TLS trust retained |
| P1 | Existing suggestion opt-outs were ignored after hiding the bottom controls | Restore the saved preference gate without restoring the removed section or toggle |
| P1 | Footer clearance assumed a 72-point centered band | Measure actual footer rows and bottom inset, check full width and successive occlusions |
| P2 | Redirected home pages resolved relative icons at the original root | Retain final response URL as the icon document base |
| P1 | Tab search disabled keyboard avoidance with container insets | Keep the keyboard safe-area region; software keyboard and Cancel interaction verified |
| P1 | Inset full-width occlusion classified as a side obstruction | Choose clearance axis for spanning regions before nearest-edge fallback |
| P2 | Incoming link silently ignored at 200 tabs | Preserve selection/data and reveal the existing close-a-tab explanation |
| P2 | Shortcut labels left aligned beneath icons | Centered both the tile stack and wrapped caption; build10 installed/launched on physical Duo first |

The seven existing Copilot findings on PR12 were individually checked against source and addressed by these changes. The second Copilot review confirmed all seven fixes and identified the three follow-ups above. A second agent independently reviewed the changed wallpaper, geometry, policy and Info.plist code; its additional nil-transfer retry finding was fixed.

## Technical UI audit

Scores are a bounded source/simulator assessment, not accessibility certification or hardware performance results.

| Dimension | Score / 4 | Evidence and limit |
| --- | --- | --- |
| Accessibility | 3 | Native labels, large-text/list fallback, corrected occlusion handling; full spoken VoiceOver matrix remains |
| Performance | 3 | Bounded file/thumbnail import and icon cache, lazy webviews; physical energy/thermal endurance remains |
| Responsive layout | 3 | Runtime geometry, closed/partial/open/rotation interaction checks, synthetic RTL/full-width occlusion checks; broader hardware matrix remains |
| Theming | 3 | System appearance and photo scrim, black/white fixture checked in dark appearance; exhaustive light/high-contrast matrix remains |
| UI consistency | 4 | Native controls and deliberate owner-requested glass/grid design; no unrelated visual redesign |
| Total | 16 / 20 | Good within the verified scope |

## Validation

- Debug simulator build passed. Native suite passed: 24 tab/zoom, 93 core, 55 upgrade, 34 settling, 4 cookie persistence and 13 memory checks. Twenty-two new checks cover RTL/occlusion placement, header/list clearance, bounded file import stale wallpaper rollback, measured footer bounds, redirected icon bases and incoming links at capacity.
- 111 portable Swift checks, 167 browser-layout assertions, strict SwiftLint and patch formatting passed.
- Simulator interactions: centered labels; native Privacy Policy open/dismiss; selected synthetic black/white photo via PhotosPicker; import/removal; dark start-page and preview contrast; tab search Cancel clear of camera; closed/partially-open/open/rotation tab controls.
- Physical Duo build10 installation/launch verified for the requested label fix. Physical passkeys/credential-provider matrix, voice accessibility, camera/mic/location grant/revoke, battery, thermal and interruption endurance remain beta acceptance work. No claim of Safari parity or guaranteed Apple approval.
- Final CI on the archived source passed all four required jobs. Every finding in the completed Copilot reviews was addressed, and an independent agent reviewed the follow-up fixes. The final three summary-only findings were verified through focused regression tests and actual software-keyboard interaction; no Copilot review was running at merge.

## Apple preparation

Bundle `dev.cnichols.duobrowser`, existing App Store Connect app `6832349110` (DuoBrowser Web Browser). Version1.0.1 is the requested beta version. The existing DuoBrowser Internal group is reused. No browser login/demo credentials are needed. Default-browser managed entitlement is deliberately absent pending Apple approval; describe that limitation in tester/review notes.

Privacy metadata conservatively discloses Search History and Browsing History for App Functionality, linked, not app tracking, because Google prediction and icon-host requests may be associated by those providers. The developer does not operate browsing telemetry or an analytics service. Browser age questionnaire marks unrestricted web access, and the app uses WKWebView, not an alternative engine.

ATS review justification: DuoBrowser is a general-purpose WKWebView browser. Users can navigate to arbitrary HTTP/HTTPS websites, requiring the web-content-only ATS exemption. App-native services retain ATS and certificate validation uses system trust.

References: [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/), [external TestFlight review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), [web-content ATS key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent).

## Release outcome

- PR12 merged as `fc324bfcf168c3f8e86acacfc412986c347b3e6e`. Archive source `7ff8f6084e6c8f82d9a264a9e0500cb8c4c9c009` has the identical Git tree (`3de2d2c97506d3a4e64bbbcdcea8053a9c6ec34b`); no source changes entered the archive after validation.
- [CI run 42537634644](https://github.com/cnichols1734/DuoBrowser/actions/runs/42537634644) passed repository/security, browser layout, iOS build/native tests and Required CI. Native receipts: 24 tab/zoom, 93 core, 55 upgrade, 34 settling, 4 cookie and 13 memory checks. Debug and Release built with the required SDK.
- Final simulator interaction checks additionally covered maximum accessibility text on closed/unfolded displays, usable browsing-mode popup, software keyboard lifting the tab-search footer, and clean Cancel dismissal. This does not certify spoken VoiceOver or physical-device endurance.
- Version **1.0.1 (11)**, bundle `dev.cnichols.duobrowser`, uploaded successfully at 18:10:57 CST on November 8, 2026. App Store Connect build ID `33f3d62e-a311-4a1a-bf16-25e8d950e2c6`.
- Distribution signature verified; `get-task-allow=false`, `beta-reports-active=true`, privacy manifest present, dSYM present, default-browser managed entitlement absent. Local exported IPA SHA-256: `e2bc722647f7e87bc51f4206954ffc0014e2cbd1ef17b4511dd7f7e5180efbef`.
- Beta description, review details and public privacy-policy URL saved. Search/Browsing History privacy answers are saved in App Store Connect; separate public product-page publication was not performed.
- TestFlight internal group **DuoBrowser Internal** shows **Testing** for 1.0.1 (11), with the existing owner tester. External group **DuoBrowser Public Beta** shows **Waiting for Review** after successful submission. External approval/public testing is not yet granted. The [public TestFlight link](https://testflight.apple.com/join/8DbZWD5z) is created; App Store Connect states testers cannot join until a build is approved.
- No production App Store release or default-browser capability request was submitted.
