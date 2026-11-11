# Guided setup verification — November 11, 2026

## Result

Optional first-run setup and Page options reentry work in the iOS 27.1 Duo simulator. The production transport is BrowserKit direct transfer with file support disabled. Apple's managed Default Web Browser capability is not yet assigned: the request was submitted as Y9UACWK77A, and signed provisioning still refuses it. No real Safari data was accessed, and no new distribution was performed.

## Automated verification

- Debug and Release simulator builds: passed with Xcode 27.2, retaining the iOS 27.1 deployment target. Existing native-harness compiler warnings and App Intents metadata notice remain; no new application compiler warnings were emitted.
- Portable checks: 139 assertions, including 28 import assertions.
- Browser/DOM fixtures: 167 assertions.
- Strict SwiftLint: zero violations.
- Complete native suite: 23 setup, 24 tabs/zoom, 93 core, 55 upgrades, 34 camera settling, 4 cookie persistence, and 13 memory assertions.
- The focused setup suite was run again after the final UI changes. Test transport is injected only by the Debug native harness. Release uses the actual BrowserKit manager.

The setup checks exercise invalid activity tokens, private-session rejection, missing capability, pending progress/preferences, review-before-save, an undated Reading List item, duplicate saves and tokens, canceled/stale async work, stream failure, a rejected file response, failed durable writes and staged-data cleanup. Portable checks cover category combinations, hierarchy, localized Favorites folder selection, empty folders, repeat-import deduplication, invalid URLs/dates, cycles, missing parents, size/capacity bounds, legacy loading and persistence.

## Interactive simulator checks

Device Hub accessibility actions exercised Welcome → Transfer → Default Browser → Tour → Start Browsing, Skip Setup and Page options reentry. A History toggle persisted across partially open/open/closed poses and a process relaunch. Rotation preserved the active step. Light/dark appearance and maximum accessibility text were inspected; the first large-text footer consumed too much height and was corrected to scroll with content at accessibility sizes. The final import confirmation is the primary footer action; skipping is secondary.

The Debug `--browser-checks --setup-preview` scenario uses only example.com records and an injected transport. The actual review UI was used to select the Favorites folder, deselect History, and confirm the import. The resulting counts were one bookmark, one favorite, zero history entries and one Reading List entry. This validates UI selection/persistence behavior, not Safari/system transfer eligibility.

![Synthetic selective transfer result](selected-transfer-result.png)

## Remaining checks

Apple approval, signed-device Safari source/category sheets, actual bookmark/profile metadata, cold/warm system transfer return, and the system default-browser picker remain unverified. Physical touch/frame pacing/energy, spoken VoiceOver, live system occlusion, and page pinch/keyboard interaction while a real system transfer is active remain device acceptance work. The walkthrough itself has no keyboard input. Existing automated browser and Reduce Motion regressions pass; they do not replace these device checks.

The newly created QA simulator initially stalled host tools during startup. It recovered after restarting that test simulator, and the complete suite subsequently passed. No existing browsing data was used or deleted.
