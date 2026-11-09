# Default-browser capability

DuoBrowser registers HTTP/HTTPS URLs and opens incoming links in a new tab, preserving existing tabs and the selected private-browsing mode. This alone does **not** make it eligible to appear in iOS's default-browser picker.

Apple must approve `com.apple.developer.web-browser` for the developer team and bundle identifier. On November 8, 2026, Xcode rejected a provisioning attempt for `dev.cnichols.duobrowser` because the capability had not been assigned by Apple. After the owner signed in, the request form was filled out but not submitted: it explicitly states, “Your app must be available in the App Store or on TestFlight for it to be assessed.” No public TestFlight link or App Store distribution is available for this development build. A separately authorized distribution step is required before submission.

- [Apple requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)
- [Request the entitlement](https://developer.apple.com/contact/request/default-browser-entitlement/)

Request details: DuoBrowser is a native WKWebView browser for iPhone Duo, with an address/search field, tabs, bookmarks, history, and private browsing. It uses WebKit to render arbitrary HTTP/HTTPS destinations and opens external links directly in a new tab. Request only the default-browser entitlement; app-installation privileges are not needed.

After Apple grants access, enable the capability for the app ID, regenerate provisioning, and set `CODE_SIGN_ENTITLEMENTS=Configuration/DefaultBrowser.entitlements` for the signed build (then check this setting into the project). The entitlement is intentionally not enabled before approval so development builds remain installable.

Verify the signed app and embedded provisioning profile both include the entitlement. Install on the phone, confirm DuoBrowser appears under Settings → Apps → Default Apps → Browser App, select it, and test cold/warm external HTTP/HTTPS links. Default selection and hardware behavior remain unverified until this approval and device check occur.
