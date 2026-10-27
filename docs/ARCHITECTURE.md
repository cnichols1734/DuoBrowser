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

## Implemented mobile YouTube compatibility rule — October 26, 2026

`YouTubeLayoutAdapter` installs the bundled, hand-authored `YouTubeLayout.js` at document end in the named `DuoBrowser.YouTubeLayout` content world, for the main frame only. The script exits on any host other than `m.youtube.com`. It exposes no native message handler and reads no text, form values, credentials, or history. There is no model inference, generated runtime code, or upload.

A hidden, noninteractive probe measures CSS horizontal safe-area env values. The rule recognizes body padding equal to those values, a full-width body, a responsive `ytm-app`, and an independently protected fixed/sticky header. It supports the observed `ytm-header` and `ytm-mobile-topbar-renderer` variants. Only matching body padding is overridden in one owned stylesheet. Validation requires the expected content-width gain, viewport containment, and unchanged header geometry/padding. Failure restores the author's layout; repeated validation failures stop retries until explicitly updated.

A small set of root/header mutation and size observations is coalesced at 120ms, with no scroll handler or whole-document scan. Input focus, editable content, pinch scale, and document fullscreen defer new adjustments. SPA node replacement revalidates. Removing the owned stylesheet preserves later author styles. The current-tab original-layout switch and the session full-width switch control both the current document and subsequent navigations; background and newly created tabs inherit session mode. No asynchronous geometry result is applied to a later document.

WebKit is configured to allow inline media playback, so pages that request inline previews need not enter the system fullscreen player. This body-padding rule does not alter the watch player's independent sizing or replace YouTube's controls. Broader camera-aware header relocation remains separate work.
