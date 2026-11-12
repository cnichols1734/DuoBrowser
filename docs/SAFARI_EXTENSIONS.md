# Native web extensions and Safari migration

Research date: November 11, 2026. This is a feasibility assessment, not a shipped feature or an App Store approval claim.

## What is possible

DuoBrowser can host compatible web extensions using public WebKit APIs. Apple added `WKWebExtension`, `WKWebExtensionContext`, and `WKWebExtensionController` on iOS 18.4; the iOS 27.1 deployment target already exceeds that requirement. The controller attaches to `WKWebViewConfiguration`, so this does not require replacing WKWebView or adopting an alternative browser engine. [WebKit announcement](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/#web-extensions), [controller documentation](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller).

This support does **not** establish that DuoBrowser can enumerate and load every Safari extension already installed on the device. The documented loaders take an accessible app-extension bundle or a local directory/ZIP containing `manifest.json`. Neither loader is an installed-Safari-extension picker. No public iOS API for copying arbitrary installed Safari extension packages into DuoBrowser was found in the inspected WebKit, SafariServices, and BrowserKit headers. This is a bounded research finding, not a claim about private system capabilities. [Bundle loader](https://developer.apple.com/documentation/webkit/wkwebextension/init(appextensionbundle:)), [resource loader](https://developer.apple.com/documentation/webkit/wkwebextension/init(resourcebaseurl:)).

## Three different extension formats

| Format | DuoBrowser path | Important limit |
| --- | --- | --- |
| Safari Web Extension: manifest, JavaScript, CSS, resources | Host a compatible, legitimately available package with `WKWebExtensionController`. | Compatibility is per extension; Safari/native-companion integrations and unsupported browser APIs need separate work. |
| Safari Content Blocker: declarative JSON rules | Compile an available rule list with `WKContentRuleListStore`; DuoBrowser already does this. | Safari's installed blocker, settings, subscription, and rules are not automatically shared with another app. |
| Safari App Extension: native SafariServices integration | Requires a separate port or equivalent implementation. | A native Safari app extension is not a manifest-based web extension that the WebKit loader can simply import. |

Apple documents that `WKContentRuleList` uses Safari content-blocker rule syntax. This is the direct mechanism for the current ad-blocker request; a general extension host is not required to provide an on/off switch or stronger audited rules. [Content rules](https://developer.apple.com/documentation/webkit/wkcontentrulelist), [Safari app extensions](https://developer.apple.com/documentation/safariservices/safari-app-extensions).

## What “transfer extensions from Safari” can mean

BrowserKit's `BEBrowserDataExtension` transfers four fields: display name, developer name, extension identifier, and App Store identifier. It does not carry the extension package, purchases, internal settings, saved data, or permission grants. Apple describes using this information to help people discover/install equivalents. Safari's older `Extensions.json` export is likewise identifying and marketplace metadata. [BrowserKit extension record](https://developer.apple.com/documentation/browserkit/bebrowserdataextension), [Safari export schema](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).

A viable future setup flow is: receive the extension inventory through the existing direct transfer; match entries to a tested DuoBrowser-compatible catalog; show availability; let the person choose installations; request fresh website permissions. An App Store listing alone does not supply DuoBrowser an executable extension package. Availability of a compatible package must be established first, through a developer-provided package or an appropriately licensed bundled distribution. Unmatched entries should say unavailable, rather than claiming transfer succeeded.

The existing setup explicitly excludes extensions and has no file import fallback. Keep that direct-transfer choice. Add metadata review only after useful compatible destinations exist. BrowserKit transfer remains subject to Apple's default-browser criteria and actual signed-device availability; see [the current activation status](SAFARI_TRANSFER.md). [Apple's transfer flow](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser).

## Proposed implementation stages

These are engineering recommendations based on DuoBrowser's current source and the installed SDK headers.

1. **Prove a bounded host.** Use a project-owned synthetic Manifest V3 extension with a content script, toolbar action, local storage, and declarative network rule. Attach a session-owned controller before constructing web views. Keep the fixture and prototype isolated from production until lifecycle/privacy tests pass.
2. **Map browser state.** Implement `WKWebExtensionTab` and `WKWebExtensionWindow` adapters for `BrowserSession`/`BrowserModel`. Report open, close, select, move, URL/title, and loading changes. Cover workspaces, lazy restored tabs, popup adoption, preview promotion, and memory eviction. Existing popup code replaces `WKUserContentController`; audit that path for extension state and isolation.
3. **Build permissions and controls.** Add Settings → Extensions with enable/disable/remove, website access, options, and a visible action menu. Handle permission requests and revocation through the controller delegate. Never grant every requested host silently. Bound package size, archive expansion, manifest parsing, and update behavior; reject unsupported packages with understandable errors.
4. **Preserve privacy and continuity.** Initially exclude private tabs entirely. Any later private opt-in needs its own nonpersistent controller, website store, content controller, and restricted tab enumeration. Contexts need explicit private access; the SDK warns that extensions can access cookies in other open-tab stores if exposed. Disabling an extension cannot be assumed to undo arbitrary DOM edits; offer a deliberate reload without silently losing forms. Extension-origin options pages require the context's configuration, so use dedicated presentation rather than rebuilding an active browsing tab.
5. **Validate a small real catalog.** Start with one developer-supported portable extension and test its complete API usage. Hide unsupported APIs using `unsupportedAPIs`. Native messaging must be deliberately implemented or unavailable; do not create a generic native bridge. Match Safari inventory only to catalog entries whose package provenance, rights, and behavior have been checked.

Apple explicitly requires consent before private-data access and distinct content controllers/nonpersistent website stores. The default native-message handling also depends on whether an app-extension bundle was supplied; a JavaScript-only ZIP does not recreate another app's companion integration. [Private data access](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/hasaccesstoprivatedata), [native messaging](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller(_:sendmessage:toapplicationwithidentifier:for:replyhandler:)).

## Distribution and verification

The SDK's loader is not an App Store approval for any chosen package-distribution model. A curated bundled package provides a simpler first review target than an unrestricted extension marketplace. Document any downloadable JavaScript plug-in model and assess Guidelines 2.5.2, 4.4, and 4.7 against the actual design; 4.7 permits certain plug-ins subject to additional obligations, so a blanket “downloaded extensions are prohibited” conclusion would also be inaccurate. Preserve package licensing and describe extension access accurately. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

Verification performed: read public documentation and installed Xcode 27.2 (27B52), iOS Simulator 27.2 SDK headers. A scratch Swift API probe passed `swiftc -typecheck -warnings-as-errors` targeting `arm64-apple-ios27.1-simulator`, covering package initialization, a nonpersistent controller, private-access exclusion, unsupported APIs, configuration attachment, load/unload calls, and BrowserKit metadata fields. Probe: ignored `work/extension-research/APICheck.swift`. This proves compile-time availability only. No extension was installed, executed, transferred, or published; no personal Safari inventory was read.

Before release, require native synthetic checks for denied/revoked permissions, private isolation, stale tasks, malicious archives, tab lifecycle, content-blocker coexistence, disable/remove behavior, restart, and memory limits; then test actual supported packages and signed-device behavior. Check closed/open/partial poses, rotation, keyboard, zoom, VoiceOver, large text, Reduce Motion, and system occlusion around extension UI. Battery, touch, and long-session performance need hardware evidence.

Recommendation: deliver the built-in blocker controls and native Reddit routing now. Treat extension hosting as several dedicated PRs, beginning with the synthetic prototype and one supported package. Broad Safari compatibility is a multi-week product effort with external package/distribution dependencies, not a settings switch. An automatic cutover of every installed Safari extension is not supported by the evidence gathered here.
