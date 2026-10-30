# Proposed architecture

## Native foundation

Start with SwiftUI, Swift concurrency, and a UIKit-backed WKWebView. Keep a stable web-view instance per active tab; do not reconstruct it on fold or chrome changes. Separate tab/session state from view layout. WebKit supplies rendering, but bookmarks, tab restoration, downloads, permissions, privacy controls, and many browser integrations remain our work.

Use a public-API-only `DisplayGeometry` layer. Query `UIView.reservedRegions(kind: .occlusion)` and `.division`, incorporating each region's margins and active state. Observe layout/scene/trait changes. Do not equate safe-area insets with the exact camera rectangle, or assume that a status-bar hiding request removes all system UI.

First measure WKWebView bounds, scroll insets, document viewport metadata, CSS viewport, and reserved regions separately. A page may add its own safe-area padding. Blanket negative insets or forcing `viewport-fit=cover` everywhere can create new problems; changes need a reversible policy and evidence.

## Page adaptation pipeline

```text
Current display regions + browser-control regions
                         ↓
Map into the page's current visual viewport
                         ↓
Bounded DOM scan near overlapping regions
                         ↓
Deterministic candidate adjustments
                         ↓
Optional on-device classification of ambiguous candidates
                         ↓
Validate → apply → measure → animate → retain or roll back
```

1. Geometry conversion accounts for view coordinates, WebKit insets, visualViewport offsets and scale, pinch zoom, scrolling, and frame boundaries. Test known anchors at multiple zoom levels rather than assuming a point equals a CSS pixel.
2. Inspect a bounded set of visible elements near exclusions. Measure controls, fixed/sticky headers, text, parent layout, and clipping. Avoid whole-page scans on every scroll.
3. Prefer local offsets or a small header reflow. Never remove essential content, disable controls, rewrite links, or silently change form values. Use a conservative inset/original view when there is no validated local solution.
4. Keep an adjustment ledger with node identity, prior properties, and document generation. Restore only changes we own; preserve later website changes. Bound MutationObserver work and avoid loops caused by our own mutations.
5. Before committing, verify visibility, viewport containment, clipping, overlap, hit testing, focus, and accessibility. Defer motion while the user touches or types in a candidate. Abort if navigation, layout, or node identity changed.
6. Animate validated changes using measured before/after positions where compatible with the page's existing transforms. Reflow must still produce correct layout and hit targets; a visual translation alone is not sufficient. Roll back unstable results.

Start with the top-level document. Cross-origin frames, closed shadow roots, canvas/WebGL interfaces, CSS transforms, and hostile or repeatedly changing pages need explicit fallbacks. Do not claim arbitrary websites can always be repaired.

## Optional Apple Intelligence

Use Foundation Models only after rules-based adaptation is measured. Apple advises against treating the on-device model as a code generator. Feed a compact, sanitized list of roles and layout facts; request a typed choice among permitted actions, not executable CSS or JavaScript.

All geometry and correctness decisions stay deterministic. Check model availability, enforce timeouts and bounded work, and ignore stale responses. Do not put inference in the scrolling or animation frame loop. Cache only appropriate nonprivate structural decisions, with an invalidation policy. In private sessions, keep any cache in memory and clear it with the session.

Page text is untrusted data and can contain prompt injection. Do not pass passwords, form values, cookies, tokens, complete page text, or browsing history to the classifier. The model cannot navigate, click, transmit, or invoke arbitrary native functions. Model failure must not delay basic browsing.

## Web/native boundary

Place injected code in a named WKContentWorld to isolate JavaScript globals. The DOM is shared across content worlds, so this is not a secrecy boundary for mutations. Validate bridge message schemas, size, frame/origin, document identity, and allowed operations. A web message must never become arbitrary native code or a general filesystem/network command.

Keep certificate validation and platform transport protections intact. Handle new-window navigation, external schemes, downloads, dialogs, permission prompts, and web-process termination deliberately as browser features are added.

## Quality and scope

Safari-level quality is a product goal, not a property inherited by wrapping WKWebView. Treat passkeys/autofill, media, WebRTC, downloads, content blockers, default-browser eligibility, and accessibility as separate verified capabilities. Do not assume access to Safari's private Reading List, iCloud tabs, extension store, or history.

No account or cloud AI service is needed for the first experiment. Collect local synthetic-fixture diagnostics by default; redact URLs and page contents from any shared evidence. See ROADMAP.md for measurable acceptance criteria.

## Implemented tabs and chrome — October 26, 2026

`BrowserSession` owns one `BrowserModel`/`WKWebView` per open tab and a selected UUID. Switching reparents the same web view; it does not reload the page. Restored background tabs defer navigation until selected. A validated local archive stores URLs, order, IDs, fixture state, and selection. It excludes non-HTTP(S) destinations and credential-bearing URLs. This is basic URL restoration, not full back-forward or form-state restoration.

Tab previews use `WKWebView.takeSnapshot`, are downsampled, and remain in memory. Snapshot generations reject stale completion after closure. Closing releases observation/delegate hooks and stops loading. There is no private mode in this implementation, no snapshot upload, and no page text collection.

`ScrollChromeState` produces continuous progress with a reversal deadband and endpoint settling. A separate observable chrome object updates only `BrowserToolbar`, keeping per-scroll updates away from WebKit layout. One persistent domain label and native `glassEffect(.regular)` capsule change together; side controls fade at the outside and are removed before compact mode. The toolbar reclaims horizontal safe-area width while retaining keyboard and bottom placement. System Liquid Glass rendering handles material appearance, with no hardcoded gray blur or tint.

## Implemented site-independent gutter fitting — October 27, 2026

`PageLayoutAdapter` installs bundled `PageLayout.js` in the named `DuoBrowser.PageLayout` content world at document end, for the main frame. HTTP(S) pages and the local fixture are eligible. It uses no host names, site selectors, native message handlers, model calls, page text, form values, credentials, or history. No data leaves the device.

The deterministic detector measures horizontal CSS safe-area env values, then examines at most 160 structural elements across four levels. It recognizes one full-width body or root wrapper (within two levels of body) whose padding matches an inset and whose child can expand. Multiple candidates, transforms, existing horizontal overflow, ordinary spacing, or missing protected top bars are conservative fallbacks. Root-wrapper matching extends the previous YouTube-only rule without keeping any YouTube-specific branch.

Top bars are recognized from measured position, width, and independent padding. Up to 96 nodes per top bar are snapshotted before applying the rule. Validation checks expected content-width gain, viewport containment, unchanged header/descendant rectangles, and no new horizontal overflow. Failure removes the one owned stylesheet and marker. Later author inline styles are preserved. Three failed validations stop retries until an explicit update.

A 160ms coalescing timer observes only selected structural nodes, their immediate children, and their sizes. No per-scroll inference or whole-page DOM scan runs. Typing, editable content, pinch scale, and document fullscreen defer new adjustments. Document-local globals prevent geometry from one document being reused in another; the native adapter passes only the current enabled flag. The original-layout switch and session full-width switch control current and future documents. The preference lasts for the current live tab.

This is a pattern recognizer with rollback, not proof that every site layout can be inferred correctly. It currently requires an independently inset top bar; it does not invent camera-safe placement for arbitrary controls, override intentional article widths, edit subframes/closed shadow roots, or resize independently positioned media players. A complete camera collision engine still needs runtime reserved-region mapping and broader fixture/device validation.

WebKit allows inline media playback so site-requested inline previews can remain in the page.

## Next AI experiment (not implemented)

Apple's on-device `SystemLanguageModel` can classify a compact description and produce constrained Swift data via guided generation. The installed iOS 27.1 SDK exposes these APIs. Availability must be checked at runtime; using the Foundation Models framework does not itself mean a request is on-device, so the experiment must explicitly select `SystemLanguageModel.default`, with no server or Private Cloud Compute fallback.

Generate a small set of permitted operations from measured geometry first: keep the original layout, remove a verified gutter, inset an existing header group, or relocate an isolated control. Only operations actually implemented and validated may appear in the model's schema. Feed bounded structural roles and numbers, never raw HTML/CSS, page instructions, credentials, form values, or browsing history. Ask the model to select a candidate ID; never execute generated code or use its claimed confidence as a correctness check.

Revalidate document identity, element identity, viewport geometry, clipping, focus, hit targets, and collisions after selection. Cancel stale requests on navigation/pose changes, enforce a deadline, keep ephemeral decisions local, and fall back immediately on unavailable/refused/invalid responses. Model requests belong on new ambiguous layouts, not scrolling or animation frames. Do not block browsing while waiting.

Before enabling this layer, evaluate the deterministic collision operations on a varied held-out fixture corpus and eligible physical hardware. Compare successful repairs, broken actions, fallback rate, latency, and energy with and without AI. Keep AI only if it improves those outcomes. No model-quality or hardware-performance claim has been established by the current simulator work.

## Production foundations — October 27, 2026

The [production implementation report](PRODUCTION_IMPLEMENTATION_2026-10-27.md) supersedes the initial tab/storage description above. Models now create web views lazily, profiles separate persistent and private stores, and validated atomic app archives contain only normal tab records, history, bookmarks and normal site preferences. Private state and opaque interaction state never enter the archive. Static-only background reclamation preserves interactive/unsent work; it is a soft memory target, not an OOM guarantee.

WKUIDelegate provides native dialogs, origin prompts, context actions and supplied-configuration child windows. WKDownload uses unique temporary destinations and native Files export. WebKit retains default file/photo upload presentation and certificate verification. No arbitrary native message bridge is added.

`ViewportView` forwards actual occlusion frames (which already include system margins) into a named JavaScript content world. `CameraAvoidance.js` samples bounded hit-test locations and attempts only local verified control translations. Existing gutter fitting remains separate and reversible. Public `obscuredContentInsets` replaces the earlier bottom scroll-padding workaround so WebKit can reposition fixed/sticky website controls. No AI inference occurs.

## Scroll settling — October 28, 2026

`CameraAvoidance.js` now waits for both touch release and 240 ms without scroll events, including nested scrolling. It samples a bounded grid within actual native reserved regions, groups small related controls, and considers short semantic text blocks. Text translates sideways into verified free space or, for supported ordinary block flow, narrows inward from the obstructed edge. The paragraph's top stays fixed: no vertical translation or margin above it is used to clear an occlusion. The minimum remaining width is 180 CSS pixels and 60% of the original; at most 180 pixels are reclaimed. A full-width expanded island therefore falls back when neither side has enough room. Transformed, clipped, large or complex layouts also fall back. At most 12 candidates and 48 motion units participate; descendant scans have explicit caps.

The final layout is measured synchronously before painting. Line wrapping is stable during scrolling; a paragraph may rewrap once after the pause. A 420 ms Web Animations transform and subtle opacity transition carry the fitted block inward from its original edge. Glyphs are never scaled, and width/padding/margin is never animated per frame. Following content preserves its normal gap and moves only by any natural text-height change. A new gesture pauses the current presentation; settling then measures and replaces stale work. Styles are owned by a document-local stylesheet and markers, so rollback retains later author inline changes. Geometry changes use the latest native message; no cache, broad bridge or page-content export is introduced. Before removing old fitting, the transaction anchors the first visible reading block, or a real visible character when its paragraph starts offscreen. It adjusts the document scroll offset synchronously to preserve that screen position before and after reflow. Internal scroll events do not pause the ensuing horizontal animation, and that animation does not replay an obsolete block-top offset for the anchored text. Destinations are revalidated after correction. Changes that would clamp the anchor at a document edge or invalidate a destination retain the previous fitting.

Native Reduce Motion and VoiceOver state are forwarded in the isolated content world, with live accessibility notifications. Reduced motion applies an immediate correction after the idle delay; VoiceOver preserves reading-block positions. Editing, text selection, fullscreen and pinch zoom defer new adjustments. Original Layout and page teardown cancel all pending work and remove owned styles. The separate gutter fitting module also defers reflow during touch and scrolling.

The simulator-only `Tests/IslandLab` companion starts a synthetic ActivityKit Live Activity with a WidgetKit Dynamic Island presentation. It is a separate app generated under ignored `work/`; neither ActivityKit nor the widget is added to DuoBrowser's shipping target. The **Time, Signal & Battery** switch in Page options is available in Debug and Release, remembers the user’s choice, and can display the activity while retaining a full-width page.

Nested news layouts: local text flow may pass through grid/flex shells (24 ancestor and 192 sibling limits); direct grid text remains unsupported. Sibling/shell geometry is checked after reflow. Only visible, safe motion units animate; stationary or offscreen subtrees need no deep scan. Compact control rows can narrow by at most 120 CSS pixels while preserving action dimensions, vertical positions and hit testing. Offcanvas panels retain their geometry and are never made descendants of a newly transformed row. Stored action references keep fitted rows eligible on later passes. A reading anchor must be visible outside the site's existing compact sticky bars.
