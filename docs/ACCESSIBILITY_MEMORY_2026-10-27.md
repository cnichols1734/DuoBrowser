# Accessibility and memory follow-up — October 27, 2026

Baseline runtime: `6363b3d`. Work remains local; no credentials or accounts were used. All native checks ran on **DuoBrowser QA**, iOS 27.1. This report supersedes the earlier preview-cache and accessibility limitations only where evidence is recorded below.

## Changes and source

- `BrowserToolbar.accessibleControls`, `addressRowHeight`, `toolbarHeight`: accessibility text sizes use a full-width address row with a separate action row. Private/HTTP status remains visible and part of the spoken address label. Controls stay expanded for VoiceOver and accessibility sizes. Normal text sizes retain the existing collapsing glass layout; address text now scales with Dynamic Type.
- `AddressField.makeUIView`, `BrowserAddressTextField.keyCommands`: the native editor accepts horizontal compression and clips its own content, so long large-text URLs cannot spill over adjacent controls. Explicit Cancel and keyboard Escape end editing. Address synchronization no longer replaces in-progress input when the page URL changes.
- `BrowserViewportState.controlLift` and `ViewportView.layoutSubviews`: active system occlusion geometry lifts native controls clear of a camera intersecting their bottom band in rotated poses. The page remains full width. The unshifted band prevents a lift/reset feedback loop; portrait restores the original bottom position.
- `ViewportView.updateObscuredArea`: WebKit's bottom obscured inset follows the actual expanded toolbar height, including large-text/status rows, so compatible fixed website controls stay above it.
- `TabOverview`, `TabPreview`: headers/search scroll with content; search height grows with text; accessibility sizes use readable tab rows and a two-row footer. New-tab and Done no longer overlap the mode/count control. Each tab's Open and Close remain distinct accessible actions; decorative duplicate title/image announcements are hidden and selected/button traits explicit. Library selection uses a native menu at accessibility sizes instead of an overcrowded segmented control.
- `BrowserToolbar` accessibility sort priorities and `ActiveBrowserView` error announcement: normal toolbar focus follows Back → Page options → Address → Reload → Tabs. Error announcements are issued only when VoiceOver is running. No claim of a complete spoken-language/rotor/gesture audit is made.
- `BrowserModel.captureSnapshot`: one snapshot request per tab at a time, at most 640 pixels on either raster axis; stale/closed/cleared captures cannot repopulate the cache. `BrowserSession.trimSnapshots` enforces **8 MiB and 12 images**, preferring the selected and recently used tabs, and runs again after asynchronous completion.
- `BrowserModel.suspendIfIdle`: eligibility runs in the isolated script world, so page-authored replacements of DOM query functions cannot falsely classify an input page as static. Inline event handlers and documents exceeding the bounded scan also protect a tab. URL/method/window/transfer state is rechecked after the asynchronous query. Forms, scripts, media, frames and opener-linked tabs retain their earlier protections.

## Measured preview-cache result

A reproducible Debug harness loads 16 static reading pages and four pages with unsent form values, captures previews, invokes the app's memory-warning notification path, reopens a reclaimed tab, then closes the other 19 tabs. Both passes used the same closed simulator size and synthetic pages. Measurements are approximate decoded raster costs (`CGImage.bytesPerRow × height`), not encoded file sizes.

| Stage | Baseline | Updated |
|---|---:|---:|
| Tabs / loaded web views after creation | 20 / 6 | 20 / 6 |
| Retained preview images | 12 | 7 |
| Retained decoded preview bytes | 82,045,824 | 8,007,680 |
| After memory warning: previews / bytes | 0 / 0 | 0 / 0 |
| After memory warning: loaded views | 4 protected form pages | 4 protected form pages |
| After closing 19 tabs: loaded views | 1 | 1 |

Preview bytes decreased **90.2%**. The app's measured physical footprint stayed approximately 35 MB in both runs; this metric excludes separate WebKit processes and does not account for all shared image surfaces. Therefore this is **not** evidence of a 90% reduction in total browser memory. Dynamic pages can exceed the soft live-view target because preserving unsent work takes priority. The warning test injects the public notification into the app; it does not reproduce actual system jetsam.

## Verification

- Debug and Release simulator builds passed after the final changes; no Swift compiler warnings.
- **52 portable checks passed** (19 data/policy, 21 scroll chrome, 12 archive).
- **30 native integration assertions passed** on the final build, including camera-control geometry, isolated eligibility evaluation, actual reclaimed WKWebView deallocation, private separation, live forms, POST/opener windows, restoration and fail-closed self-signed TLS.
- **11 memory stress assertions passed**: 20-tab exercise, bounded previews, warning cleanup, protected unsent forms, static recovery, closing 19 tabs and 200-record cold restore with one loaded WKWebView. A repeat recorded approximately 23 MB app-process footprint versus roughly 35 MB in the paired comparison; this variability is another reason not to extrapolate to total device memory.
- Native UI inspected at the largest accessibility text size: address entry remains clipped to its row, separate controls remain available, status text is visible, tab rows and footer no longer overlap, and the fixture's fixed footer clears browser chrome. Address selection, typing and navigation were exercised.
- Dark mode plus Increase Contrast and Reduce Transparency produced opaque dark native surfaces with legible light controls. Reduce Motion was enabled during inspection; this was not a frame-time benchmark.
- With simulator VoiceOver enabled, the visible focus ring traversed Back → Page options → Address → Reload → Tabs. Full speech, rotor, gesture and activation behavior was not established by automation and remains device QA.
- An unsent fixture value survived rotation. The rotation check exposed a camera overlapping Tabs; after the fix, landscape controls visibly cleared the bottom camera and returning to portrait restored their lower position. Final geometry received a fresh build and native test run; memory policy was unchanged from its measured run.
- The earlier 38 DOM cases and eight-site smoke are documented in the production implementation report; they were not rerun in this follow-up because page adaptation code did not change.

The QA simulator was returned to closed portrait, Large text, light appearance, Increase Contrast off, Reduce Motion off, Reduce Transparency off and VoiceOver off. Keyboard capture was restored off. Device Hub sometimes needed a pose change to refresh its rendered Settings view; no physical-device behavior is inferred from that tooling issue.

Raw local receipts are in ignored `work/native-accessibility-memory-checks.txt`, `work/memory-before.txt`, `work/memory-after.txt` and `work/memory-final.txt`. Simulator evidence does not establish physical-device credential, jetsam, thermal or battery behavior.

## Remaining work

Physical-device VoiceOver speech/rotors/gestures and Braille, Switch Control, full keyboard access, broader languages and right-to-left text, physical pinch/touch, long-session memory including WebKit child processes, energy/thermals, actual low-memory termination, and authenticated website compatibility remain release gates. Website content chooses its own typography/dark styling; we do not force arbitrary sites to recolor or scale text. Some complex camera collisions remain deliberately unchanged.

For the owner's credential test, use [the iPhone password/passkey checklist](IPHONE_PASSWORD_PASSKEY_CHECKLIST.md). The existing build can be used for password-provider testing after normal device signing. Arbitrary-site passkeys still require the correct browser eligibility/provisioning; phone AutoFill settings alone cannot supply it.
