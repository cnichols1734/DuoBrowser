# Starter validation

October 26, 2026, America/Chicago.

## Confirmed

- Xcode 27.1 Debug simulator build succeeded for arm64 and x86_64 using the shared DuoBrowser scheme and iOS 27.1 deployment target.
- No Swift compiler warnings remained after correcting the WebKit navigation decision-handler actor annotation. Xcode emitted its standard AppIntents metadata-skipped notice because this app has no AppIntents dependency.
- A dedicated **DuoBrowser QA** iOS 27.1 simulator was created and booted. Identifier: `3ABC97EF-86C9-42F1-A7CF-63089F2FD617`.
- `simctl install` succeeded and `simctl appinfo` confirmed `dev.local.DuoBrowser`, version 0.1.0 (1).
- `simctl launch` succeeded and returned process ID 73046. This confirms launch, not completed interaction testing.
- Local documentation links and Git whitespace checks passed.

## Still to verify

During the initial setup, the Device Hub UI remained on another simulator. Attempts to select the new simulator were rejected after the tool detected user changes. Attempts to open Xcode through Computer Use timed out; the project file is available to open manually. The subsequent full-width verification below supersedes the initial visual-inspection gap for closed-display rendering only.

Run the app on DuoBrowser QA, then check:

1. Fixture content loads, its test button works, and keyboard input retains its value.
2. Full-width and safe-area modes change the actual CSS viewport as expected.
3. Reserved-region overlays track the camera and fold across poses.
4. URL/search entry, back/forward, reload/stop, errors, and new-window links behave correctly.
5. Keyboard, pinch zoom, rotation, and the last lines of a page remain usable.

The starter has no automated UI suite yet. Camera-avoidance behavior, AI, native accessibility review, hardware performance, energy, private browsing, tabs, and Safari comparison are future milestones. No area-gain percentage or Safari-equivalence claim is established.

## Full-width follow-up — October 26, 2026

- The owner's screenshot showed the fixture at 382 × 644 CSS pixels, with a full-height white strip on the right. The model's full-width flag was false, so the web view was constrained to its safe-area layout frame.
- Full-width rendering is now on by default in both model and viewport view. The status bar is hidden in this mode, and the menu calls the option “Full-width page”. Switching it off restores the conservative comparison mode.
- The updated simulator build passed, with no Swift compiler warnings. The AppIntents metadata-skipped notice remains expected.
- Installed and relaunched on DuoBrowser QA. Visually inspected a live Apple webpage filling the closed display from left to right, with no dedicated blank right-hand strip and no clock/connectivity indicators over the page. The bottom browser controls also occupy the available width.
- Camera avoidance is still separate work: this change removes the full-height gutter, but does not relocate arbitrary site controls around the physical camera.
- A follow-up attempt to select the local test page was rejected after a user UI change. No new CSS-width measurement, open-pose, keyboard, pinch-zoom, or automated interaction result is claimed for this pass.

## Scrolling controls follow-up — October 26, 2026

- Disabled automatic safe-area adjustment of the native vertical scroll indicator and set its right inset to zero. During native scrolling, the indicator was visually confirmed at the display's right edge, including with the keyboard open.
- Added a direction-aware scroll policy: sustained downward movement collapses the controls to a site-name pill; upward movement, returning to the top, tapping the pill, navigation, or an error restores the controls. Separate thresholds avoid flicker on small reversals. Page dimensions and the bottom content inset remain stable during the transition.
- A native fast-fling check exposed a first-event overshoot at the page bottom. The policy now compares clamped offsets, counting the real travel while ignoring elastic bounce. Regression checks cover both overshoot and rebound.
- All 16 portable scroll-policy checks passed. They cover directions, thresholds, bounce, fast flings, short pages, programmatic scrolling, tap-to-reveal during deceleration, and expansion suppression. See `Tests/README.md`.
- The final Debug simulator build passed with no Swift compiler warnings; the AppIntents metadata notice is expected. Installed and relaunched the resulting app on DuoBrowser QA.
- Native interaction checks passed on the closed Duo fixture: downward scroll collapsed the controls; tapping the pill restored them; a new downward scroll collapsed them again; upward scroll restored them. URL editing showed the keyboard and kept full controls visible during further scrolling. Submitting the empty field dismissed the keyboard without navigation.
- The full-width fixture reported **466 × 678 CSS pixels at scale 1** with the keyboard closed, and **466 × 413** with URL entry active. This is a fixture measurement, not a Safari comparison or a usable-area percentage.
- The transition respects Reduce Motion in code, and VoiceOver/accessibility text sizes keep controls expanded. Native VoiceOver, larger-text, Reduce Motion, pinch zoom, rotation, open/partially folded poses, and physical-device motion/performance checks remain outstanding for this change.

## Liquid Glass, centered chrome, and tabs — October 26, 2026

- Replaced the material capsule with native SwiftUI Liquid Glass (`.regular`, interactive controls, no custom tint or color-scheme override). Uses the system renderer; Clear/Tinted setting variants and Reduce Transparency have not been manually compared on hardware.
- Native closed-Duo screenshots confirmed that expanded controls are centered across the physical display, with symmetric outer Back/Tabs buttons. The tab overview also fills the full width, with two columns, previews, search, close buttons, centered tab count, plus, and Done.
- Scroll progress now continuously drives capsule size, label size, and position. The owner's live feedback identified side controls crossing the compact pill; they now fade near their outer positions and are removed before compact mode. Native screenshots confirmed only `apple.com` remains when compact. Tap and upward scroll restored both side buttons.
- A second owner correction separated vertical positions: the expanded bar moved down by up to 12 points; the compact pill lands 8 points above the bottom edge using the current bottom safe inset. The final installed build was visually inspected in both positions, and tapping the low pill successfully expanded the controls upward. Keyboard mode disables this downward offset.
- Fixed address-field focus while moving from the domain label to editing. Native URL entry loaded `https://example.com` in a second tab. The original Apple tab remained available. Tab creation, selecting Apple, closing the temporary Example Domain tab, and displaying current page previews passed.
- Relaunching the app restored two tab records and the selected `example.com` URL. Selecting the restored Apple tab then loaded it. Closing Example Domain reduced the overview to one tab and left Apple selected.
- All **21 scroll policy** and **12 tab archive** checks passed. The final Debug simulator build succeeded for the generic simulator destination with no Swift warnings; the expected AppIntents metadata-skipped notice remains. Installed and launched on DuoBrowser QA.
- Remaining QA: full in-page form/zoom/history preservation matrix, search filtering with many tabs, popup edge cases, closing the final tab, memory pressure, and exhaustive keyboard interactions. An open-pose attempt was rejected when Computer Use detected a user interaction; open/partially folded poses, rotation, native VoiceOver, larger text, Reduce Motion, system glass variants, and physical-device performance remain unverified in this pass. No measured animation frame-rate or pixel-identical Safari claim is made.
- Persistence is deliberately basic: IDs, tab order, HTTP(S) URLs, fixture state, and selection. Page history, forms, scroll positions, and preview images are retained only in the live session. Private browsing and tab groups are not implemented.

## YouTube right-gutter diagnosis — October 26, 2026

Reproduced the owner's mobile YouTube search in the closed Duo QA simulator using temporary read-only geometry diagnostics. Removed the instrumentation afterward.

- Native WKWebView bounds: **466 × 678 points**. Right content and adjusted-content insets: **0**. Native right safe-area inset: **84**. Obscured content insets: **0** on all sides.
- YouTube reports `innerWidth`, root `clientWidth`, and visual viewport width of **466 CSS pixels**, scale **1**. Its viewport meta already includes `viewport-fit=cover`.
- HTML and BODY bounds both span **466 CSS pixels**. BODY computed padding is **0px left / 84px right**; the `YTM-APP` content box is only **382px** wide.
- This confirms that the visible full-height strip comes from page-body padding, not a narrowed native web view. The 84px padding exactly matches the device's right safe-area inset. The diagnostic inspected computed values; it did not trace the authored CSS declaration.
- For comparison, the Apple page measured a 466px-wide body with **0px right padding** in the same browser.
- No website CSS was modified in this diagnostic pass. Selective root-padding correction with local header/camera protection remains implementation work; expanding the native viewport alone cannot remove a site's own padding.

## Project registration

The Git repo and Xcode project exist locally. They have not been registered as a project in the chat app, and this chat has not been moved. The available tools cannot create a local project; Computer Use explicitly disallows controlling the Codex app. Add the repo folder manually using the path in README.md.

## YouTube feed correction — October 26, 2026

- Implemented the site-specific body-padding adapter described in ARCHITECTURE.md. Temporary native diagnostics reported an applied result of **382 → 466 CSS pixels**, reclaiming **84px**, after toggling the correction on. Original-layout on restored the visible gutter; turning it off widened the same content again without reloading.
- Visually confirmed full-width home-feed video thumbnails, Shorts grids, and search results on closed DuoBrowser QA. Native scrolling kept previews full width and collapsed the toolbar to its low pill. YouTube's header overflow menu opened successfully beside the camera. A video opened and played in the system player; closing playback and browser navigation remained functional.
- This exercise exposed the starter's default WebKit inline-media setting. The final build now enables `allowsInlineMediaPlayback` so site-requested inline previews can remain in the page. This does not bypass media gesture policy or modify site player controls.
- All **16 synthetic layout checks**, **21 scroll policy checks**, and **12 tab archive checks** passed. Fixtures cover two observed header variants, safe padding recognition, restoration, DOM replacement, focus/editable/zoom deferral, frame/origin boundaries, geometry changes, and convergence. They use Chromium with substituted safe-area probe values, not a claim of native pinch or hardware validation.
- Final generic iOS Simulator Debug build passed for both architectures. No Swift compiler warnings; only the expected AppIntents metadata notice. Installed and launched on DuoBrowser QA without the temporary diagnostics. No browsing content was saved as a deliverable or uploaded.
- Final-build pose check: search results adapted to a four-column Shorts row on the open display, then returned to two full-width columns when folded closed. The visible content and browser controls stayed present. This is a visual open/closed check, not the complete pose/accessibility matrix.
- Known scope: the watch-page video player independently reserves horizontal space and can still show its own right gutter. This correction fixes feed/previews and body content only. General camera collision handling, native pinch, VoiceOver/larger text/Reduce Motion, rotated/partially folded layout, physical device performance, and extended site-variant coverage remain to verify.

## Site-independent gutter fitting — October 27, 2026

- Replaced the YouTube-specific adapter with a general body/root-container pattern detector. The bundled runtime has no host-name checks or site-element selectors. The earlier YouTube entries above describe historical implementation and evidence.
- All **24 synthetic browser layout checks passed** with the exact bundled script. They exercise unrelated origins and ordinary HTML containers, header descendant preservation, overflow rollback, scan limits, ambiguity, author-style restoration, focus/zoom deferral, late hydration, SPA replacement, side-inset changes, observer convergence, and working header actions. Chromium uses substituted safe-area probe values; these results do not establish native pinch or universal compatibility.
- Generic iOS Simulator Debug build succeeded for both architectures. No Swift compiler warnings; the expected AppIntents metadata notice remains. Installed and launched the final runtime on DuoBrowser QA without temporary geometry diagnostics.
- Native closed-display YouTube search retained full-width preview columns with the general detector. No site-specific fallback was retained.
- The bundled viewport lab uses ordinary body/main/header elements with independently padded header controls. On the closed display, its actual native measurements were **466 × 678 CSS pixels**, scale **1**, and **466px content width**. Enabling Original page layout restored **382px content width**; disabling it restored **466px**, without reloading. The header test action worked and its result survived both changes.
- Opening the device produced a **951 × 669** viewport. The ruler spanned the display while the intentional article max-width remained **716px**. Folding closed restored the **466px** content measurement and retained the test-action result. Automatic fitting was left enabled.
- No Foundation Models runtime or AI inference was added. Official APIs and the installed SDK were checked; the bounded on-device selection experiment is documented in ARCHITECTURE.md. Model effectiveness, availability on eligible hardware, latency, and energy remain unmeasured.
- Remaining coverage: native pinch and in-page keyboard matrix, rotated/partially folded poses, VoiceOver/larger text/Reduce Motion, physical-device checks, broader independent-site validation, general camera-control relocation, and independently sized watch-page players. The detector preserves unsupported layouts rather than promising a correction for every site.

## Eight-site native smoke test — October 27, 2026

Exercised Amazon, Reddit, Google, Wikipedia, Facebook, Instagram, NY Times, and Walmart in the installed app. See [the full site matrix](SITE_QA_2026-10-27.md) for exact interactions, findings, and limits. Main open findings are camera/control collisions, bottom site UI overlapping browser chrome, Google's remaining results gutter, left-weighted Meta login layouts, and a native link-menu path opening Safari. All eight loaded, but this is not an eight-site pass: authenticated flows and some sticky/infinite-scroll states remain unverified. Walmart's cart survived an open/closed fold check. No application code changed; no new build or automated-test result is claimed for this documentation-only pass.
