# iPhone password and passkey checklist

Checked against Apple documentation and the installed iOS 27.1 SDK on October 27, 2026. This is a manual device acceptance test; no real credentials were read or entered during development.

## 1. Install the development build

The current app requires **iOS 27.1 or later**. It can run on a regular compatible iPhone; camera-region behavior is Duo-specific. There is no TestFlight build yet.

1. Open `DuoBrowser.xcodeproj` in Xcode 27.1. Connect and unlock your iPhone, approve the normal pairing/trust prompt, and select the physical phone as the Run destination.
2. Select the DuoBrowser target → **Signing & Capabilities**. Enable automatic signing, select your Apple development team, and use a unique bundle identifier registered to that team. The repository currently uses `dev.local.DuoBrowser` and has no team selected.
3. If Xcode requests Developer Mode, on the phone open **Settings → Privacy & Security → Developer Mode**, turn it on, restart, then confirm and enter the phone passcode. The option may appear only after pairing begins. These steps are for your own local development build; TestFlight does not require Developer Mode. [Apple instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
4. Run from Xcode. If iOS explicitly requests developer-app trust, follow that prompt for your selected team. Do not install or trust a website certificate. Keep normal HTTPS validation enabled.

A Personal Team may suffice for basic local development but does not establish access to a managed browser capability. Team approval and provisioning are separate from successful installation.

## 2. Configure the phone's credential provider

1. Open **Settings → General → AutoFill & Passwords**. Turn on **AutoFill Passwords and Passkeys** and enable **Passwords** as a provider. For the third-party pass, enable your installed manager there instead; open and unlock that manager first. Test one provider at a time so the result is attributable. [Apple AutoFill guidance](https://support.apple.com/en-ca/guide/iphone/iphf9219d8c9/27/ios/27).
2. For Apple Passwords syncing, open **Settings → your name → iCloud → Passwords** (sometimes under See All, or named Passwords & Keychain), then enable **Sync this iPhone** if you want those credentials synced. Apple requires two-factor authentication for iCloud Keychain. Keep a device passcode and Face ID/Touch ID configured. [Apple Keychain setup](https://support.apple.com/en-ie/109016).
3. In the Passwords app, confirm that a credential you own has the correct website domain. Use a low-risk test account. Never send me its password, verification code, passkey QR code, or recovery material.

## 3. Password acceptance test — useful now

1. In Safari, sign into that HTTPS website with AutoFill to establish a control result. Safari and DuoBrowser do not share their website cookies, so signing into one does not sign you into the other.
2. In a **normal DuoBrowser tab**, open the same site's login page. Tap its username/password field, choose the system suggestion or Passwords/key control, authenticate with Face ID/Touch ID, and submit yourself. Record whether the provider appeared, both fields filled, and the site signed in. Test an available one-time-code suggestion too.
3. Cancel the credential picker once and retry. The field and keyboard should still work. Switch tabs and return; fold/unfold if using Duo. There must be no unexplained page reload or lost input.
4. After successful login, open another normal tab for the same site. Then force-quit and relaunch DuoBrowser. A persistent login should remain if the site itself uses persistent cookies; a site that deliberately expires sessions is not a browser persistence failure. Test logout and verify the normal profile is signed out.
5. Repeat in **Private**. Normal login cookies must not appear there. Private tabs in the same private session may share a login. Close **all** private tabs; a new private session must start signed out. Password suggestions may still appear: the OS credential provider is separate from private website storage. Explicitly saving a password/passkey or exporting a file can persist outside the private session.
6. Repeat steps 2–5 using your third-party provider. Report only site domain, provider, iOS version, normal/private mode, and the failed step or exact nonsecret error.

WebKit/iOS supply the HTML credential UI; DuoBrowser preserves those native fields. This test establishes interoperability, not access to the user's credential vault. [Apple Password AutoFill](https://developer.apple.com/documentation/security/password-autofill).

## 4. Passkeys — resolve the app capability first

**The current development build has no managed browser entitlement or associated domains. Phone settings alone cannot make arbitrary-site passkeys supported. A failure in this build is not evidence that your passkey is broken.**

For a general iOS browser, the account holder needs to request Apple's **default-browser managed capability**, `com.apple.developer.web-browser`, for the final App ID. After approval, enable it for that identifier, regenerate the development profile, include the approved entitlement and HTTP/HTTPS URL handling, and install a newly signed build. Handling incoming HTTP/HTTPS links and validating Apple's content/navigation requirements remain application work for that capability; adding a text entitlement file alone is insufficient. Choosing DuoBrowser as the phone's default is a separate user preference, not proof that the signed capability exists. [Apple default-browser requirements and request form](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser).

Apple's ordinary embedded-WKWebView path instead requires a matching `webcredentials` associated domain and a website association file controlled by the relying party. We cannot associate arbitrary third-party sites ourselves. WebKit documents the entitled-browser/associated-domain boundary. [Apple embedded passkey guidance](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys), [WebKit's eligibility explanation](https://bugs.webkit.org/show_bug.cgi?id=250912).

Do **not** add `com.apple.developer.web-browser.public-key-credential` as an assumed iOS fix: Apple's reference lists macOS/Mac Catalyst availability and a macOS request process. For this WKWebView browser, WebKit handles website WebAuthn challenges; we should not scrape credentials or replace WebAuthn with an injected native bridge. [Apple entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential), [WebKit browser passkey integration](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers).

Once the properly provisioned browser build is ready:

1. Use an HTTPS service where you own an existing passkey; confirm it works in Safari first. In DuoBrowser, choose that site's **Sign in with a passkey** and complete the native sheet yourself. Verify the sheet names the intended site/account. Cancel once, then retry.
2. On a disposable test account that offers passkey creation, use the site's security settings to create a passkey yourself, sign out, and sign back in with it. Do not replace the only recovery method for an important account just to test.
3. Repeat at a second unrelated relying-party domain. Test both the explicit passkey button and username-field AutoFill if the site offers both.
4. Repeat with your third-party provider, then private mode. Closing private tabs should erase the website session, not credentials deliberately saved to the OS/provider.
5. If Safari succeeds and DuoBrowser fails, report the nonsecret error and whether the native sheet appeared. Recheck the actual installed provisioning/entitlements before changing phone settings. A true capability-probe result alone does not prove successful registration or authentication.

No device-password, provider or passkey pass is claimed until these steps have been observed on the signed build.
