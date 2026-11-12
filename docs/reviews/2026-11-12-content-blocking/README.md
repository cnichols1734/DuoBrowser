# Maintained filters review

The app now bundles EasyList and EasyPrivacy, with optional EasyList Cookie List
filtering. The independent converter supports a bounded declarative subset;
unsupported rules are omitted. This is not an ad-blocking effectiveness score or
uBlock/AdGuard parity claim. See [licensing and supported syntax](../../MAINTAINED_FILTERS.md).

## Completed checks

- Debug and Release simulator builds; 221 portable assertions; 186 web assertions;
  strict SwiftLint; repository and secret scanning checks. Final Debug also passes
  with the compiled-cache optimization. Release/native follow-up is pending below.
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

Initial iOS testing exposed repeated source conversion on every process launch.
A bounded manifest now reuses both complete WebKit variants only when source
fingerprints, converter version and every compiled identifier validate. Missing
or damaged cache entries rebuild; an optional manifest-write failure never
disables active protection. First preparation still converts and compiles the
bundled data; Filter Lists exposes that preparation state.

The synthetic Reddit handoff test raced WebKit's scroll compositor with the
larger cosmetic stylesheet. Waiting for rendering and the native scroll offset
before simulating the next action passed all 29 routing assertions. The iframe
test now verifies non-delivery at the local fixture server because a blocked
iframe need not emit a load/error event. Identical rule sets are no longer
removed and reattached unnecessarily.

Final full iOS suite, six compiled-cache assertions and Release build are pending
on these follow-up changes. No hardware performance, battery/endurance, spoken
VoiceOver, real-site/video-ad effectiveness or App Store acceptance is claimed.
