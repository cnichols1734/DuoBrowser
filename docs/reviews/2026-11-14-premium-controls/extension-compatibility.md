# Installed blocker compatibility — November 14, 2026

This is a representative compatibility check, not a popularity ranking. It distinguishes an installed **Safari extension** from a vendor's separately enabled **system-level filter**. No vendor was contacted, no subscription was purchased, and no installed vendor app was inspected or changed.

## Result

The inspected public iOS 27.2 SDK does not provide a supported path for DuoBrowser to enumerate, extract, or reuse arbitrary installed Safari extensions and their app-private settings. Default-browser approval and Safari transfer do not supply those extension bundles. Building an independent WebExtension host would require accessible, permitted packages and a separate permission/runtime implementation; it would not make the installed Safari apps available.

Some named products have a genuine system-level feature that can affect ordinary DuoBrowser WebKit traffic once the user enables it in that product. That is coexistence with an OS filter, not DuoBrowser loading their Safari extension. The vendor-documented routes below have not been verified on the owner's device with DuoBrowser.

| Product | Installed Safari extension in DuoBrowser | Separate documented route beyond Safari | Official evidence |
| --- | --- | --- | --- |
| AdBlock Pro | No verified public installed-app route | Its help explicitly limits the product to Safari; no system-wide route established | [AdBlock Pro help](https://adblockpro.com/help) |
| Adblock Plus | No verified public installed-app route | The iOS Premium app supports a separately enabled DNS configuration | [Adblock Plus iOS DNS and Safari setup](https://help.adblockplus.org/adblock-plus-help-center/enable-ad-blocking-in-apps-in-the-adblock-plus-for-ios-app) |
| AdGuard | No verified public installed-app route | Enable DNS protection in AdGuard. Vendor explicitly documents non-Safari browser filtering and says cosmetic filtering is unavailable there | [Other-browser behavior](https://adguard.com/en/support/adguard_for_ios/display_incorrectly/different_browser.html), [setup](https://adguard.com/en/support/adguard_for_ios/doesnt_block_ads/in_other_browsers.html) |
| 1Blocker | No verified public installed-app route | Its separate Block In-App Trackers filter operates at the network level through a local profile; this is tracker-domain filtering, not Safari page cleanup | [In-app filter overview](https://support.1blocker.com/en/articles/9313591-in-app-tracking-filter-overview), [current feature location](https://support.1blocker.com/en/articles/10330106-where-is-firewall) |
| Wipr / Wipr 2 | No verified public installed-app route | Wipr 2's optional Filtr add-on uses iOS 26 URL Filters. The developer documents coverage in most other iOS browsers and separate activation under More → Filtr | [Current Wipr help](https://kaylees.site/wipr-help.html#what-is-filtr), [current developer App Store description](https://apps.apple.com/us/app/wipr-2/id1662217862) |
| AdBlock for Safari + VPN | No verified public installed-app route | The Premium VPN layer is documented to extend blocking to other browsers/apps | [Installation and VPN setup](https://helpcenter.getadblock.com/adblock-help-center/install-adblock), [blocking behavior](https://helpcenter.getadblock.com/adblock-help-center/how-ad-blocking-works-in-the-adblock-vpn-apps) |
| Ghostery | No verified public installed-app route | The reviewed iPhone/iPad product is a Safari extension; no separate system-filter route established in the reviewed official docs | [Ghostery for Safari](https://www.ghostery.com/ghostery-ad-blocker-safari) |
| uBlock Origin Lite | No verified public installed-app route | Official project distributes Safari via the App Store; independently distributed WebExtension packages are a separate host-compatibility project, not installed-Safari-app access | [Official releases](https://github.com/uBlockOrigin/uBOL-home/releases), [official Safari troubleshooting](https://github.com/uBlockOrigin/uBOL-home/wiki/Troubleshooting) |
| Firefox Focus | No verified public installed-app route | It is a standalone browser and can separately provide a Safari content blocker. Neither mode documents loading its installed blocker into another WKWebView app | [Mozilla's iOS overview](https://support.mozilla.org/en-US/kb/firefox-focus-ios) |
| NextDNS | Not a Safari-extension import path | The official native app or Apple configuration profile supplies system DNS filtering; expected to affect standard WebKit traffic subject to the device's actual resolver configuration | [NextDNS product](https://nextdns.io/), [official iOS instructions](https://github.com/nextdns/nextdns/wiki/iOS), [Apple profile generator](https://apple.nextdns.io/) |

DNS/network filters cannot be assumed to provide a Safari extension's cosmetic page cleanup, settings, site permissions, script behavior, or identical filtering. Wipr Filtr is URL-based rather than simply DNS-based. Its own documentation still recommends Safari for best results. Other provider routes differ and require physical-device checks with the actual VPN/DNS/URL-filter setup.

## Installed SDK evidence

Read-only inspection used the selected Xcode installation's iPhoneSimulator 27.2 SDK under `System/Library/Frameworks`:

- `WebKit.framework/Headers/WKWebExtension.h` exposes construction from an accessible app-extension bundle or a file URL to a manifest directory/ZIP. These constructors do not enumerate or grant access to another installed app's resources.
- `WebKit.framework/Headers/WKWebExtensionController.h` associates a host controller with the browser's WebKit configuration; it does not supply a catalog of Safari-installed extensions.
- `SafariServices.framework/Headers/SFContentBlockerManager.h` exposes reload/state operations, not an API to extract another blocker's rules or install it into our WebKit store.
- `WebKit.framework/Headers/WKContentRuleListStore.h` compiles and retrieves rules in the selected rule-list store. It does not expose Safari's rule store or another app's private data.
- `NetworkExtension.framework/Headers/NEURLFilter.h` describes voluntary URL checks for apps **not** using WebKit, CFNetwork, or Network.framework. This supports the inference that ordinary WebKit traffic participates in the system URL-filter path. It is not a device test of Wipr Filtr with DuoBrowser.

Apple separately documents [Safari extension installation](https://support.apple.com/en-gb/guide/iphone/iphab0432bf6/ios) and the [WKWebExtension API](https://developer.apple.com/documentation/webkit/wkwebextension). The sandbox prevents treating an installed product's files or settings as ours to read; see [Apple runtime-process security](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web).

## Legitimate future integration routes

1. **Keep the existing maintained EasyList/EasyPrivacy path.** It already performs real browser-local blocking without depending on a second app. A provider partnership or licensed public list could be added through the same bounded, verified rule pipeline, after compatibility and license review.
2. **AdGuard publishes a real Swift conversion library.** [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) converts supplied filter rules to Safari-style content-blocking JSON. Its advanced output requires separate extension machinery. Its GPL-3.0 license needs deliberate distribution review before inclusion in this MIT project. It does not read an installed AdGuard app's lists, settings, or subscription.
3. **Ghostery publishes an embeddable library.** [ghostery/adblocker](https://github.com/ghostery/adblocker) is a JavaScript/TypeScript engine under MPL-2.0. No native WKWebView adapter was established in the reviewed material. Embedding such an engine is a different project from loading the installed Ghostery Safari app.
4. **A separate WebExtension host remains possible in principle.** It would need independently accessible, licensed packages, supported API coverage, explicit permissions, normal/private isolation, update integrity and revocation. Compatibility must be tested per package. No host, catalog, arbitrary extension switch or import claim is added here.

Recommendation: retain working built-in protection; document the real user-enabled system-filter routes accurately. Do not add a generic “Use installed Safari blockers” switch. Verify the owner's actual blocker/version on hardware before presenting any external provider as active or fully compatible.
