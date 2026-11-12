# Reddit links and ad-blocking settings

November 11, 2026. Implements TestFlight feedback; no merge or release is implied.

## Behavior

Page options → Settings contains **Block Ads & Trackers** and Open Links → **Reddit**.

- The initial Reddit preference is Ask Once. When Apollo's scheme is available, a tapped Reddit content link offers Apollo Reborn, DuoBrowser, and Cancel. The first nonprivate choice is remembered.
- Settings can select Ask Once, Ask Every Time, DuoBrowser, or an available Apollo Reborn. A saved app preference remains visible when the app is unavailable, but navigation falls back to the original web request.
- Private tabs always ask before sharing a link with another app. Private choices are not saved. The preference stores only an enum, never URLs or an installed-app inventory.
- Only top-level link activations from the main frame, including new-window links, are eligible. Typed addresses, restored tabs, inbound links from other apps, frames, POSTs, downloads, and ordinary script/server redirects do not initiate handoff. Long-press Open/Open in New Tab explicitly stays in the browser.
- A successful launch cancels the web request, preserving the source page, scroll and draft. A failed launch continues the original request. Closing/switching the tab, cancelling the chooser, or starting another navigation invalidates pending work.
- Content URLs on `reddit.com`, `www`, `old`, `new`, `np`, `m`, and bare `redd.it` are supported. Post/comment, subreddit, profile, gallery, wiki and share-link paths are preserved. Authentication/account-management paths remain in the browser. Direct media hosts remain in the browser.
- Google `/url` wrappers are parsed locally for a single `url` or `q` destination on `google.com`, `.co.uk`, `.ca`, `.com.au`, `.de`, `.fr`, `.co.in`, and `.co.jp`, with optional `www`. Other wrappers, AMP URLs, unsupported hosts and ambiguous destinations stay in the browser. No extra URL-resolution requests are added. A fixed isolated-world listener records only the current trusted anchor click in memory; navigation must consume the exact URL within 1.5 seconds. Scripted clicks cannot authorize handoff. The record is one-use and disappears with the document; no message handler or native bridge is exposed to pages.

The built-in ad blocker already covered 19 advertising/tracking services. The new global switch defaults on and is independent of per-site exceptions. It updates rule attachments in existing normal/private tabs without reloading their documents; new requests use the selected policy. Previously loaded content may remain until a deliberate reload. New and restored tabs honor the setting. Private site exceptions remain ephemeral. This change does not expand the rule list or claim to remove every ad.

## Integration evidence and limitations

[Apollo Reborn's own instructions](https://github.com/Apollo-Reborn/Apollo-Reborn#opening-links-in-apollo) document `apollo://reddit.com/<path>` and `apollo://redd.it/<id>`, preserving queries and comment paths. DuoBrowser uses native UIKit opening, not Apollo's Safari extension or an intermediary website.

[Apple's `canOpenURL` documentation](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)) requires declaring queried schemes. Only `apollo` is declared. iOS 27 deprecates this probe in favor of attempting a launch, but an installed-app chooser needs a nonlaunching availability check. The public API remains available; actual open failure is also handled. A registered scheme identifies a handler, not a cryptographically verified app identity, and cannot prove that a specific installed Apollo variant resolves every content URL.

[Artemis's developer site](https://artemisapp.me/) and [App Store listing](https://apps.apple.com/gb/app/artemis-read-upvote-post/id6751728465) were checked, along with targeted searches for its URL scheme and deep-link documentation. The listing describes an Open in Artemis Safari extension. No authoritative post/comment URL contract or accessible extension source was found. Do not guess an `artemis://` rewrite or expose a nonfunctional option. Enabling Artemis requires a developer-documented contract or inspection of a legitimately available package, plus actual device verification. Once that exists, extend the installed-client choices and URL builder; when both are available, the user selects their default.

General Safari extension hosting and migration are a separate project; see [feasibility research](SAFARI_EXTENSIONS.md).

## Verification

Debug and Release simulator builds passed using Xcode 27.2 and its iOS 27.2 SDK, retaining the iOS 27.1 deployment target. The portable suite passed 192 assertions, including 44 Reddit URL/navigation policy cases. All 177 Playwright assertions passed, including 10 real-click, keyboard, scripted-click, replay, mismatch, expiry and download cases. SwiftLint 0.65.1 reported zero violations; repository and diff checks passed. The 25 native Reddit checks passed, including preference persistence, private confirmation, failed/missing app fallback, stale choices/callbacks, exact Google/comment routing, source-page state preservation, the native chooser, and isolated-world protection.

[Manual UI evidence](reviews/2026-11-11-reddit-links/README.md) records a real simulator tap through the production trusted-click gate, remembered choice, Settings controls, and closed/open/partial/rotated layouts. Real Apollo/Artemis launches, sideload variants, physical touch, full spoken VoiceOver, and hardware fold/rotation behavior remain unverified. Synthetic tests inject the OS availability/open boundary; native routing tests also inject gesture authorization, while separate native isolation and Playwright trusted-click tests cover the production listener. The manual preview uses the production trusted-click path with only availability/launch simulated. No tests launch a user's app or use their browsing data.

## Review follow-up — November 11, 2026

Copilot identified that a page window-capture handler could prevent a scripted click from reaching the document listener, preserving a real tap token. The gate now installs on `window` at document start, before page handlers. A regression reproduces the failure before the fix and passes afterward; the click suite has 12 assertions. The release build number is advanced to 12 (marketing version 1.0.1) after checking App Store Connect uploads; Safari transfer remains disabled pending Apple approval.

A second review found that a canceled real click could leave authorization for a detached scripted anchor, whose event never reaches `window`. Consumption now rejects the retained event when its default action was canceled. The detached-anchor regression fails before this fix and passes afterward; all 13 click checks use real default activation for accepted gestures. Reader coverage now loads synthetic first- and third-party images through the production `loadHTMLString` path with blocking on and off in both normal and private profiles, rather than only inspecting the preference flag.
