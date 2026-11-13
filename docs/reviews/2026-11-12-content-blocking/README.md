# Maintained filters review

The app now bundles EasyList and EasyPrivacy, with optional EasyList Cookie List
filtering. The independent converter supports a bounded declarative subset;
unsupported rules are omitted. This is not an ad-blocking effectiveness score or
uBlock/AdGuard parity claim. See [licensing and supported syntax](../../MAINTAINED_FILTERS.md).

## Completed checks

- Debug and Release simulator builds; 221 portable assertions; 186 web assertions;
  strict SwiftLint; repository and secret scanning checks. Final startup/cache/stale
  changes passed both builds and the complete native suite: **313 assertions**
  (24 setup, 29 Reddit, 21 tabs, 93 core, 95 upgrades, 34 settling, 4 cookies, 13 memory).
- All bundled sources compiled in a separate native macOS WebKit probe.
- Device Hub interaction on the iOS 27.1 Duo simulator: Settings → Filter Lists,
  opt-in cookie filtering, successful live Update Now with disabled progress state
  and completion feedback, credits and the bundled full license text.
- Checked closed/open/partially folded display layouts, rotation, light/dark
  appearance, maximum accessibility text and Reduce Motion. Scrolling exposed
  the update action and status at maximum text size. Returned the QA simulator to
  normal text size, light appearance and Reduce Motion off.
- [Dark filter settings](filter-settings-dark.png) records the actual native UI.

## Regression follow-up

Initial iOS testing exposed repeated source conversion on every process launch
and slow first preparation on a fresh simulator. Browsing now starts with the
small bundled baseline while the maintained catalog prepares in the background.
Protection reports that state honestly; full rules activate without reloading.
A bounded manifest now reuses both complete WebKit variants only when source
fingerprints, converter version and every compiled identifier validate. Missing
or damaged cache entries rebuild; an optional manifest-write failure never
disables active protection. First preparation still converts and compiles the
bundled data; Filter Lists exposes that preparation state. Automatic refresh
rechecks normal foreground eligibility after preparation and before networking.

The synthetic Reddit handoff test raced WebKit's scroll compositor with the
larger cosmetic stylesheet. Waiting for rendering and the native scroll offset
before simulating the next action passed all 29 routing assertions. The iframe
test now verifies non-delivery at the local fixture server because a blocked
iframe need not emit a load/error event. Identical rule sets are no longer
removed and reattached unnecessarily.

The final native suite verifies maintained rules without fallback, all six cache
checks, real navigation during held preparation, draft-preserving promotion,
zero automatic downloads after revoked refresh permission, and stale callback
rejection. No hardware performance, battery/endurance, spoken
VoiceOver, real-site/video-ad effectiveness or App Store acceptance is claimed.
