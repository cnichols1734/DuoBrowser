# Guided setup and direct browser transfer

## Product behavior

First launch presents Welcome, Transfer, Default Browser, and a short browser tour. Each step is optional; Page options → Set Up DuoBrowser reopens it. Progress and category choices are local settings. Setup has no document picker, Safari export-settings link, ZIP import, or file-export instructions.

The BrowserKit import request explicitly sets `supportForImportFromFiles: false`. The system chooses the source browser and its export categories. DuoBrowser reviews received data before saving it into the regular library. Bookmarks, Favorites, History, and Reading List can be selected independently at review. Favorites are identified by the folder the person chooses; the API has no separate favorite flag, so localized folder names are never guessed. Folder hierarchy, safe URLs, and history dates are retained. Passwords, cookies, login sessions, open tabs, extensions, and offline Reading List downloads are not imported.

Received data remains in memory until confirmation. Failure, cancellation, and timeout discard staged data. Incoming activities require a typed token; stale asynchronous results and repeated tokens are ignored. Private browsing cannot initiate or receive a transfer. Imports do not navigate pages or fetch icons until the person opens their saved library/start page normally.

Transfer limits are 40,000 incoming records and 12 MB of string payload. The destination supports 10,000 bookmarks, 2,000 folders, 20,000 history entries, and 10,000 Reading List entries within a 32 MB archive. Capacity errors refuse the transfer rather than silently dropping existing saved pages. Unsupported/unsafe items and duplicates are counted in the result.

## Apple requirements and status — November 11, 2026

- Apple documents direct transfer through [BrowserKit](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser). The installed SDK declares the transfer APIs available from iOS 26.4; DuoBrowser retains its iOS 27.1 minimum.
- Apple links use of this API to the [default-browser criteria](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), including the managed `com.apple.developer.web-browser` entitlement. This is separate from alternative browser engine and app marketplace installation privileges; neither is requested.
- The App ID is `dev.cnichols.duobrowser`. Its portal capability list did not expose Default Web Browser as an available capability. A signed Release provisioning attempt on November 11 explicitly failed because Apple had not assigned that capability to the team and bundle identifier.
- At the owner's request, the default-browser entitlement application was submitted on November 11. Apple displayed **“Thank you for your submission”**, request **Y9UACWK77A**, and said it would review the request and contact the owner.
- The request includes the existing external TestFlight build 1.0.1 (11), App Store Connect app 6832349110, and the verified [public beta link](https://testflight.apple.com/join/8DbZWD5z). It discloses that the upcoming transfer flow is not in that beta build. No new distribution was performed.

## Activation after approval

1. Verify Apple's approval for this exact App ID and enable the Default Web Browser capability in Certificates, Identifiers & Profiles if required.
2. Regenerate provisioning using Xcode automatic signing. Build Release with `-xcconfig Configuration/ApprovedDefaultBrowser.xcconfig`. This adds the existing entitlement file and sets `DUOBROWSER_DIRECT_TRANSFER_ENABLED=YES` together. Default project builds keep that flag off while approval is pending.
3. Inspect both the signed app and its embedded provisioning profile for `com.apple.developer.web-browser=true`. Do not treat an Info.plist flag or an unsigned simulator build as evidence of entitlement approval.
4. On an eligible physical iPhone, exercise Safari selection, category selection, cancellation, cold/warm app returns, review, persistence, and repeat import with synthetic data. Verify the actual Favorites tree and profile behavior. Verify the default-browser picker and incoming links. Runtime availability on a user's device remains authoritative; SDK presence is insufficient.
5. Merge and TestFlight/App Store distribution remain separate owner-authorized actions.

`BEAvailability` tests eligibility for alternative browser engines, not entitlement approval for this WKWebView import flow. DuoBrowser does not use it to infer transfer access or assert that transfer is restricted to a particular region. Apple's transfer documentation does not establish universal device/source-browser availability.

## Verification

Portable import checks cover selection, out-of-order folders, localized favorites selection, duplicate imports, URL/date validation, cycles, missing parents, capacity, and persistence. Native checks exercise the public BrowserKit record adapter with synthetic streams, review-before-save, invalid tokens, private isolation, replay, cancellation, stale request completion, unexpected file responses, and failed durable writes. Real Safari transfer and default-browser selection remain blocked pending Apple approval and signed-device validation.

Final build/test receipts and interactive simulator coverage: [setup verification](reviews/2026-11-11-setup/README.md).
