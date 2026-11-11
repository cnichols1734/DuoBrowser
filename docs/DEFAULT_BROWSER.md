# Default-browser capability

**Current status (November 11, 2026):** Apple accepted request **Y9UACWK77A**; approval and provisioning access are pending. See the November 11 update below.

DuoBrowser registers HTTP/HTTPS URLs and opens incoming links in a new tab, preserving existing tabs and the selected private-browsing mode. This alone does **not** make it eligible to appear in iOS's default-browser picker.

Apple must approve `com.apple.developer.web-browser` for the developer team and bundle identifier. On November 8, 2026, Xcode rejected a provisioning attempt for `dev.cnichols.duobrowser` because the capability had not been assigned by Apple. After the owner signed in, the request form was filled out but not submitted: it explicitly states, “Your app must be available in the App Store or on TestFlight for it to be assessed.” No public TestFlight link or App Store distribution is available for this development build. A separately authorized distribution step is required before submission.

- [Apple requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)
- [Request the entitlement](https://developer.apple.com/contact/request/default-browser-entitlement/)

Request details: DuoBrowser is a native WKWebView browser for iPhone Duo, with an address/search field, tabs, bookmarks, history, and private browsing. It uses WebKit to render arbitrary HTTP/HTTPS destinations and opens external links directly in a new tab. Request only the default-browser entitlement; app-installation privileges are not needed.

After Apple grants access, enable the capability for the app ID, regenerate provisioning, and set `CODE_SIGN_ENTITLEMENTS=Configuration/DefaultBrowser.entitlements` for the signed build (then check this setting into the project). The entitlement is intentionally not enabled before approval so development builds remain installable.

Verify the signed app and embedded provisioning profile both include the entitlement. Install on the phone, confirm DuoBrowser appears under Settings → Apps → Default Apps → Browser App, select it, and test cold/warm external HTTP/HTTPS links. Default selection and hardware behavior remain unverified until this approval and device check occur.

## November 11, 2026 — request submitted

The owner authorized applying for and enabling the capability needed for direct Safari migration. The existing 1.0.1 (11) public TestFlight build is now available, removing the earlier distribution prerequisite. Apple accepted the default-browser entitlement request as **Y9UACWK77A** and displayed that it will review the request and contact the owner. The application requests only Default Web Browser, with the public beta link and an explicit note that direct transfer is an upcoming feature.

A fresh signed Release provisioning attempt still rejects the capability because Apple has not assigned it to the team and `dev.cnichols.duobrowser`. Approval, an entitled provisioning profile, and signed-device validation remain outstanding. `Configuration/ApprovedDefaultBrowser.xcconfig` prepares the entitlement and direct-transfer feature flag together for activation after approval. Current build defaults remain installable while the request is processed. [Details and verification](SAFARI_TRANSFER.md).
