# Production implementation and release gates — October 27, 2026

The source-cited [audit](PRODUCTION_AUDIT_2026-10-27.md) was completed and committed as `e9d0e8d` before implementation. Its baseline statuses are intentionally frozen. This document records the subsequent changes and remaining gates. The browser is **not yet approved for production release or established as Safari-equivalent**.

## Implemented after the audit

| Area | Source / methods | Current behavior and limits |
|---|---|---|
| Profiles and private browsing | `BrowserSession.store`, `switchMode`, `closePrivateTabs`, `endPrivateSession`, `saveNow`; `PrivacyCurtain.cover` | Explicit default persistent normal store; one separate nonpersistent private store per session. Private tabs, automatic history, layout preferences and previews stay out of archives; private previews are not captured. Closing the final private tab releases/clears its store. All app windows get a background snapshot cover. User-saved bookmarks and exported files intentionally persist. No network anonymity claim. |
| Durable state / crash recovery | `BrowserArchiveStore.load/write/replace`, `BrowserArchive.validated`, `TabArchive.validated`; `BrowserSession.scheduleSave/saveNow` | Atomic protected local files excluded from backup, last-known-good recovery copy, decode/file/tab/library bounds, 750ms write coalescing, legacy archive migration. History deletion replaces both generations. Normal URLs/order/selection and best-effort scroll restore. Web-process termination offers explicit reload, without an automatic POST retry. Cold form values and full back-forward stacks are intentionally not persisted. |
| Memory and tab lifecycle | `BrowserModel.webView`, `activate`, `suspendIfIdle`, `close`; `BrowserSession.compactInactiveTabs`, `trimSnapshots` | Lazy web-view construction for restored background tabs; 200-tab archive limit; about 12 retained previews, cleared on memory warnings. A soft target of six loaded views (two under memory warning) applies only to eligible static reading documents. Forms, scripts, contenteditable, media, frames, canvas, transfers, POSTs and opener-connected tabs remain live. High-memory dynamic sites can still exceed this target; hardware endurance testing remains necessary. |
| Navigation and security | `WebAddress.resolve/valid`; `BrowserModel.decidePolicyFor`; `BrowserPresentation` WKUIDelegate extension | Robust host/port/search parsing and credential/executable-URL rejection; native select-all editor; exact internal about:blank/srcdoc handling (opaque WebKit URLs can have an empty URL.path); full supplied-configuration popup creation preserves POST and requested opener. Three popups per 10 seconds and three dialogs per document bound abusive presentation. Native origin-labeled alert/confirm/prompt completes once even on cancellation. User-initiated tel/mail/sms/maps handoffs ask before leaving. Normal HTTP(S) links stay in the web view; native link actions open/copy/share. Default system certificate validation and ATS remain intact; HTTPS upgrade and fraudulent-site warnings are explicitly enabled. There is no certificate bypass. HTTP pages display “Not Secure.” |
| Permissions / uploads | `BrowserModel` configuration; `BrowserPresentation` media and geolocation delegate; project purpose strings | Secure origins use WebKit's `.prompt`; insecure origins are denied for media/location. Camera, microphone and foreground-location purpose descriptions are present. WebKit's standard file/photo chooser is retained; no broad photo-library entitlement or credential scraping. Actual hardware grant/deny/revoke flows remain unverified. |
| Downloads | `BrowserDownloads.add`, `decideDestinationUsing`, `exportNext`, `cancelAll` and document-picker callbacks | WKDownload action/response routing, unique sanitized staging paths, five outstanding transfers/exports per tab, native Files export, explicit cancellation, errors and cleanup. Private closure removes its staging files; app startup removes old staging leftovers. Exported Files remain user-owned. Background/resumable transfer across app termination is not implemented. |
| History / bookmarks | `BrowserSession.onVisit`, `addBookmark`, `deleteHistory/deleteBookmarks`; `BrowserLibrary` | Successful main-frame navigation history (1000 entries), bookmarks (500), search/open/delete and clear history in one native library. Automatic private visits excluded. Explicit bookmark save is allowed in private mode. A separate favorites dashboard, sync and complete SPA-history capture are not claimed. |
| Find / share / site mode / refresh | `BrowserToolbar.pageMenu`, `BrowserPresentation.share`, `BrowserModel.configure`, `refreshPage` | Native find interaction and sharing; per-host desktop/mobile preferred content mode; UIRefreshControl; inline and PiP enabled. Website decisions and DRM/autoplay policies still apply. Native semantic colors/glass remain system-controlled; websites choose their own dark mode. |
| Duo geometry | `ViewportView.layoutSubviews/updateObscuredArea`; `PageLayoutAdapter.updateGeometry`; `CameraAvoidance.js`; existing `PageLayout.js` | Actual active UIKit occlusion frames mapped into WebKit coordinates. Frames already include margins; no double expansion. Bottom obscured insets adjust fixed/sticky content, with no side rail. Camera moves are bounded to eight small controls and free destinations, defer during editing/pinch/fullscreen, verify hit targets and rollback, and restore obsolete corrections after geometry changes. No model or generated page code. Camera corrections currently apply immediately; chrome retains its smooth native animation. Unsupported collisions are a release limitation, not a hidden universal-success claim. |
| Minimal UI | `BrowserToolbar`, `TabOverview`, `BrowserLibrary`, `AddressField` | Back/address/tabs stay the permanent controls. One existing page menu contains contextual actions; completed-download actions appear only when needed. One library sheet holds bookmarks/history. Normal/private selection is in the overview's bottom control, with a full-width grid. Diagnostics only appear in Debug builds. |

## Important finding during implementation

An initial native experiment transferred WebKit `interactionState` while the original view remained alive and preserved a field. A stronger test then released the original view and **lost the unsent value**. The implementation was changed before delivery: pages with form controls or scripts are not automatically reclaimed. Regression tests explicitly check that such a page stays live and retains its value. Static reading pages can release their view, explicitly resume their current GET history item, and restore scroll through the loaded document. This avoids clamping against a stale UIScrollView contentSize. This does not establish arbitrary SPA state restoration and must not be described that way.

## Verification

All checks ran locally on October 27, 2026. Native work used only **DuoBrowser QA**, iOS 27.1. The user's existing simulator and physical device were not used.

| Verification | Result | What it establishes |
|---|---|---|
| Debug and Release generic iOS Simulator builds | Passed | Both architectures compile. No Swift compiler warnings; Xcode's nonblocking AppIntents metadata notice remains. No signing/distribution claim. |
| Portable Swift suites | **52 passed**: data 19, scrolling 21, archives 12 | URL policy, bounded persistence/recovery/deletion, tab records and chrome state behavior. |
| Real Chromium layout fixtures | **38 passed**: gutter 24, camera 14 | Bounded corrections, rollback, author-style preservation, hit targets, editing/zoom deferral, scaling and observer convergence. Safe-area probe values are substituted; this is not native hardware geometry evidence. |
| Native WebKit integration harness | **25 passed** | Private cookie/localStorage isolation and teardown, archive exclusion, srcdoc frames, live form retention, POST new windows/opener/close, once-only dialog cancellation, bottom fixed-footer clearance, static reclamation/scroll restoration, untrusted TLS rejection, filename sanitization and lazy cold restore. Crash-message assertion invokes the delegate directly, rather than killing WebKit. |
| Actual app termination/relaunch | Passed | Separate persistent test store retained its cookie and localStorage; read phase then cleared the test store. A write-phase assertion also confirmed the store is persistent. This is not a real-account login test. |
| Native UI on synthetic fixture | Observed working | Address select-all replacement; origin-labeled alert; native Files export of a 28-byte fixture; staging cleanup; WebKit upload menu and selection of that same file; find with two matches/next; bookmark and library; native share sheet opened and dismissed without sharing. Camera/photo capture was not exercised. |
| Duo poses and tab UI | Observed working | The same unsent field value survived closed → open → partially open → closed. Bottom controls stayed centered. Full-width overview, bottom normal/private menu, and closing the final private tab returning to normal were verified. Field retention is evidence against a reload in this fixture, not proof for every website. |

### Eight-site native regression smoke

Each site loaded at a **466 × 678 point** native web-view size. The document viewport was **466 CSS pixels**, with **zero horizontal overflow**, on all eight. The test used an ephemeral profile and did not sign in, submit forms, add purchases, or accept account agreements.

| Site | Final host | Body width (CSS px) | Scroll reached (CSS px) |
|---|---|---:|---:|
| Amazon | www.amazon.com | 450 | 600 |
| Reddit | www.reddit.com | 466 | 600 |
| Google | www.google.com | 466 | 114 |
| Wikipedia | www.wikipedia.org | 466 | 600 |
| Facebook | m.facebook.com | 466 | 0 |
| Instagram | www.instagram.com | 466 | 10 |
| NY Times | www.nytimes.com | 466 | 600 |
| Walmart | www.walmart.com | 466 | 600 |

Amazon's body margins were preserved while its document viewport used the full width. The Meta login pages were short; their small scroll values are not infinite-feed tests. Back navigation became available after the first destination. This smoke run preceded the final srcdoc-policy and static-restoration fixes; the final 25-check native suite and fold/UI checks include those fixes. The final normal browser was left on Wikipedia.

Earlier search/menu/cart/login-screen interactions are recorded separately in [the baseline site report](SITE_QA_2026-10-27.md). Those observations do not certify the final implementation's authenticated flows. Raw local receipts and build logs remain in ignored `work/`; reproducible commands and synthetic fixtures are in `Tests/README.md`.

### Current requirement status

“Implemented” below means application integration exists with the coverage above, not release certification. Sources and methods are in the implementation table and frozen baseline audit.

| Requirement | Current status | Remaining boundary |
|---|---|---|
| Password AutoFill / third-party managers / passkeys | **Unverified** | Signed-device/provider/relying-party matrix and browser eligibility. No credential access was added. |
| Persistent cookies and login sessions | **Partial** | Persistent cookie/localStorage restart proven; real SSO/login/logout and session-cookie policies unverified. |
| Review history | **Implemented** | Search/delete/clear successful main-frame visits; complete SPA-history coverage remains limited. |
| Private browsing | **Partial** | Ephemeral profile and app-owned exclusions verified; hardware snapshots, OS interruption and forensic/privacy review remain. |
| Tab lifecycle / restoration / memory | **Partial** | Lazy startup/static reclamation/previews bounded; live dynamic pages intentionally protected, cold full history/forms not restored. |
| Back/forward / gestures / scroll | **Partial** | WebKit integration and static scroll restore present; full gesture/POST/SPA matrix remains. |
| Downloads and uploads | **Partial** | Files round trip observed; interrupted/large downloads and photo capture still unverified. |
| Camera / microphone / location | **Partial** | Purpose strings and secure-origin prompts integrated; hardware grant/deny/revoke pending. |
| New windows / external schemes / dialogs | **Implemented** | Supplied-configuration POST/opener/close and dialog cancellation tested; external app handoffs require broader device coverage. |
| Search/address reliability | **Implemented** | Parser tests and native select-all verified; multilingual/spoof-like URL and accessibility matrix remains. |
| Crash recovery | **Partial** | Atomic archive backup, lazy restore and explicit reload message; actual process-crash/reboot endurance pending. |
| HTTPS / certificate errors | **Implemented** | System trust retained, known-host HTTPS upgrade, HTTP label, invalid TLS blocked; no bypass. Additional certificate variants remain to test. |
| Camera avoidance / per-site disable | **Partial** | Geometry-driven bounded corrections and per-host rollback; ambiguous collisions stay unchanged. |
| Accessibility / safe areas | **Partial** | Native labels/materials, Dynamic Type-aware controls and full-width layout; full assistive-technology matrix pending. |
| Tab previews / management | **Partial** | Search/new/select/close and private grouping; reorder and normal close-all not added. |
| Long-press links | **Implemented** | App-owned open/new/copy/share actions; full native gesture matrix pending. |
| Find on page | **Implemented** | Native find enabled; matches/next/dismiss observed. |
| Bookmarks / favorites | **Partial** | Save/search/open/delete library implemented; rename and a separate favorites surface absent. |
| Pull to refresh | **Implemented** | Native refresh control and completion/error cleanup; gesture/POST edge cases pending. |
| Dark mode | **Partial** | System-native appearance; page dark styling remains website-controlled; contrast matrix pending. |
| Native sharing | **Implemented** | System sheet observed; no outgoing share submitted. |
| Desktop/mobile toggle | **Implemented** | Per-host preferred content mode applied before navigation; website response varies. |
| Video / picture-in-picture | **Partial** | Inline/PiP settings enabled; actual media/DRM/interruption matrix unverified. |
| Fold/unfold without unnecessary reload | **Implemented** | Stable view architecture and retained unsent input across all three poses; broader sites/rotation pending. |
| Bottom one-handed controls | **Implemented** | Centered native glass controls and low collapsed pill retained. |
| Per-site layout preferences | **Implemented** | Full width, original layout and desktop choice persist normally; private preferences stay in memory. |
| No wasted horizontal space | **Partial** | Full-width native/document viewport established; legitimate max-widths preserved and independently constrained site components may still need fallback. |

## Remaining release gates, in priority order

1. **P0 credentials and browser eligibility:** signed physical-device Apple Passwords / third-party manager / OTP matrix; correct iOS managed-browser capability and arbitrary-relying-party passkey registration/authentication/cancellation. No Apple entitlement approval, associated-domain workaround, distribution profile or real login test has been invented. This requires the owner's Apple developer configuration and authorized accounts/hardware.
2. **P0 privacy and lifecycle endurance:** app-switcher capture on hardware, OS termination/reboot, WebKit process crashes, low-memory runs with many dynamic pages, and private downloads/pickers during interruption. The static-page policy deliberately favors unsent work over aggressively reaching the soft memory target. Review HTTP-auth challenges and complex SSO as additional compatibility cases.
3. **P0 geometry / accessibility:** live camera collisions that lack a verified free destination still fall back; closed/open/partial/rotation, keyboard, pinch, changing system occlusion, VoiceOver focus/order, maximum Dynamic Type and contrast/Reduce Transparency need a broader device matrix. Do not assume synthetic geometry tests prove all layouts or all assistive technology behavior.
4. **P0 permission and transfer edge cases:** physical camera/mic/location grant/deny/revoke and cross-origin frames, photo capture, interrupted downloads, network loss, very large files, and file-provider cancellation. Do not claim a successful Files selection proves hardware capture or all providers.
5. **P1 compatibility and performance:** authenticated states on the eight sites, genuine infinite-feed endurance, actual media/PiP/DRM and interruption, keyboard find/share behavior, dark/high-contrast appearance, physical scroll/animation, memory, battery and thermal profiles. Keep optional AI out of release until it demonstrates a measurable benefit over these deterministic rules.
6. **Distribution:** final identity/icon, team and signing, default-browser request/approval, privacy disclosures and distribution choice. Nothing has been published or uploaded, and there is no remote repository.
