# Browser productivity upgrades — October 29, 2026

This change builds on the camera-settling branch in PR #4. The feature PR is stacked against that branch; merge/rebase order must preserve those layout changes. Owner review and merge authority remain unchanged.

## Using the features

- **Unified search:** tap the existing glass address capsule. The search sheet searches open tabs across workspaces, bookmarks, and history locally. Matching tabs appear first and say “Switch to tab”; bookmark/history duplicates of open destinations are suppressed. Submit explicitly to navigate or search DuckDuckGo. No remote suggestions or search telemetry run while typing. Private searches show private tabs and deliberately saved bookmarks, never normal tabs/history.
- **Workspaces:** Page options → Workspaces, or the workspace selector in Tabs. Create/rename up to 20 workspaces, each with up to 40 characters in its name. Long-press a tab to move it. Removing a workspace keeps its tabs in the first workspace. Workspaces share normal website cookies/logins; they are not isolated profiles. Private tabs remain outside normal workspaces.
- **Pinned tabs:** Page options → Pin Tab, or a tab's context menu. Pins appear first with a pin indicator and survive normal-session restoration. Private pins last only for that private session. Explicit Close still closes a pinned tab.
- **Peek:** long-press a web link → Peek. The sheet has back/forward/reload, Close, and Keep as Tab. Keeping adopts the same live WKWebView, preserving its forms and navigation. Closing does not alter the source page. Unkept previews are absent from app history, snapshots, and the session archive. A preview uses the source's normal/private website store, so normal website cookies and network requests still occur. Pop-up child windows are disabled inside Peek. Previews remain live across backgrounding but are not restored after process termination.
- **Reader:** Page options → Reader on a loaded article. Text is extracted locally from semantic article/main content into native SwiftUI. Font size, line spacing, and system/light/sepia/dark appearance are available. Done returns to the untouched original document and its scroll/form state. Navigation and cancellation invalidate stale extraction. Unsupported or short pages explain why Reader is unavailable. This version is text-only: no images, interactive links, offline library, or AI summaries. Reader appearance settings last for the current presentation.
- **Basic ad/tracker blocking:** enabled by default for HTTP(S) pages, with an explicit per-site reload action under This Website. The bundled baseline covers 19 known advertising/measurement domains for third-party subresources. It does not claim comprehensive ad removal, anti-fingerprinting, video-ad removal, or Brave parity. First-party resources and main documents are not targeted. There is no remote filter subscription, request interception, request counting, or browsing telemetry. List updates ship through reviewed app changes. A compilation failure leaves browsing available and reports “Protection unavailable.”

## Architecture and privacy

`BrowserSession` owns workspace membership and preview lifetime; `BrowserArchive` retains the existing archive version with optional additive fields for old-install migration. Validation deduplicates/bounds workspaces and repairs orphan membership. Private tabs and preferences never enter that archive. Workspace removal changes organization without deleting tabs.

`Reader.js` is bundled, read-only code evaluated in a named isolated content world. It scans at most 5,000 elements, emits at most 300 text blocks, limits each block to 8,000 characters and total text to about 108,000 characters. It omits form/editable/navigation/hidden content. Native validation accepts only known block kinds and bounded strings. Text renders verbatim, never as HTML or generated code. The original DOM is not rewritten.

`ContentBlocking` compiles a single shared `WKContentRuleList`. Main-frame navigation waits for the rules before proceeding; stale or closed-tab policy work cancels. The same pipeline applies to restored tabs, private tabs, Peek, and child windows. Rules contain static domain patterns only. Private exceptions remain memory-only. The test-only rule substitution is excluded from Release.

Existing `PageLayout.js` and `CameraAvoidance.js` are unchanged. Browser glass controls and runtime reserved-region handling remain in place. Search, Reader, workspaces, and Peek use native sheets and safe areas.

## Validation

- Debug and Release simulator builds: passed with Xcode 27.1.
- Portable checks: 62 assertions (21 scroll chrome, 12 tab archive, 29 browser data); repository policy and syntax checks passed.
- Browser/DOM checks: 118 assertions (25 page layout, 16 Reader, 14 camera avoidance, 50 settling, 13 nested layouts).
- Full native run: 106 assertions passed (30 browser, 32 upgrades, 30 settling, 3 process persistence, 11 memory). Final upgrade rerun: all 33 assertions passed, including restored-title search after WebKit publishes a late title.
- SwiftLint 0.65.1: zero violations; patch whitespace clean.
- Closed-display UI: exercised address entry/keyboard, cross-workspace tab search, workspace creation/switching, pinning, Peek/Keep as Tab, Reader presentation/dismissal, and per-site blocker reload. Reader's duplicated heading and Peek's unintended side toolbar were corrected during visual review.

Screenshots use loopback synthetic content only: [original page](images/browser-upgrades/original-page.png), [Reader](images/browser-upgrades/reader.png), [unified search](images/browser-upgrades/unified-search.png).

The native suite checks camera control clearance and the existing layout suites cover geometry/rollback. This feature pass does not claim a complete manual matrix for open/partially folded poses, rotation, pinch zoom, larger text, Reduce Motion, spoken VoiceOver or changing system occlusions. These remain review/release gates, along with physical touch, credentials, battery/endurance, broad authenticated-site compatibility and App Store approval. Simulator evidence does not replace hardware checks.
