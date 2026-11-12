# Saved pages and offline reading

November 12, 2026. Feature branch evidence; no merge or release implied.

Page options → Save Page lets readers edit the title and choose Favorites, Bookmarks (including a folder), or Read Later. Library supports folder creation, renaming and moving; bookmark title/destination edits; read/unread state and filtering. Folder moves reject cycles, missing parents and excessive depth. Explicit private saves explain that the result stays in the normal Library after private tabs close.

Read Later optionally captures the current readable article through the existing isolated-world Reader extractor. Saving does not navigate or change the source document. Navigation, a closed source tab, or cancellation invalidates the save. The app stores escaped text and optional raster images, not website scripts or executable HTML. Up to eight same-origin HTTPS image requests use anonymous ephemeral sessions without cookies, credentials, cache or redirects. Image downloads are capped at 1 MiB, dimensions at 20,000 per side and 40 megapixels, downsampled to at most 1,200 pixels, and re-encoded to JPEG. The article image budget is 4 MiB; serialized snapshots are capped at 6 MB and the store at 50 MB. Unsupported, cross-origin, redirected or authenticated images can be absent; the saved article explains missing images. No video or interactive page capture is promised.

Offline Reader loads only local text and embedded JPEGs in a separate nonpersistent WebKit profile. Its CSP denies network images, connections, scripts, frames and forms. Offline content remains readable without a network connection. Removing a copy preserves its Reading List link; deleting an entry removes the copy. New offline copies and Library writes use the primary archive commit as the save boundary, with rollback if that commit fails. Removal retains the copy and reports an error if replacing either archive generation fails; it does not claim success. Reader text size, line spacing and appearance now persist.

Verification is recorded below as checks complete. All fixtures are synthetic. Hardware touch, energy, real authenticated content and full spoken VoiceOver remain unverified.

## Verification

- Debug and Release simulator builds passed with Xcode 27.2 / iOS 27.2 SDK, retaining deployment target iOS 27.1. The final file-deletion failure follow-up is awaiting the combined integration build.
- Portable suite: 210 assertions passed, including 18 saved-page policy/storage checks. All 186 web assertions passed. Strict SwiftLint: zero violations. Repository and whitespace checks passed.
- Full isolated native suite passed: setup 24, Reddit 29, tabs 24, core 93, upgrades 88, settling 34, cookie write/read 2 each, memory 13. Offline checks exercise source draft preservation, stale capture rejection, bookmark destination edits, disk snapshot/reload, read status, real embedded JPEG rendering, network-denying CSP, ephemeral rendering, removal, explicit private save vs capture, and failed durable-write rollback. A fixture initially expected four raster pixels from a four-point image on a scaled device; setting the synthetic renderer scale to 1 corrected the test, then the full suite passed.
- Three additional native deletion-failure assertions are checked in for the integration run (expected upgrade total 91). They require a thrown disk-deletion failure to preserve a retryable Library entry and durable reference. The two corresponding portable failure assertions pass. These final native assertions have not yet run on this feature branch.
- Real simulator UI: opened Save Page, selected Read Later and offline saving, saved using Command-S, opened the resulting offline article, and confirmed it changed from unread to read. Typed a custom title with real keyboard input, created a Research folder from Save, saved the bookmark into it, opened it in Library, and renamed the folder to Reading using its Edit action. The bookmark retained its typed title. Save dialogs support Command-S and Escape for hardware-keyboard use.
- Exercised closed, open and partially open poses, rotation, light/dark appearances, maximum text size and Reduce Motion. Restored Light, default text size, Reduce Motion off, portrait/closed pose and keyboard-capture off afterward. The large-text capture exposed crowded inline status metadata; the final layout stacks domain/status and removes the repeated picker label at accessibility sizes. That correction passed Release build and needs a fresh integration screenshot.
- Device Hub did not expose Save/Cancel navigation-bar buttons to its accessibility tree, and coordinate input returned `noWindowsAvailable`; the actual save action was exercised with Command-S. Full spoken VoiceOver, pinch zoom, live occlusion changes, hardware touch/energy and successful same-origin HTTPS image downloading on real sites remain unverified. Native tests prove local raster rendering and deny-network behavior; they do not establish broad site coverage.

## Captures

- [Bookmark folder in Library](library-folders.png)
- [Dark appearance after rotation](library-dark-rotation.png)
- [Reading List at maximum text size, before the final metadata-stacking correction](reading-list-large-text.png)

Use `--browser-checks --saved-pages-preview` in Debug with the synthetic fixture server for an isolated interactive preview. It uses a temporary archive and nonpersistent website data; it does not read the normal browsing profile.
