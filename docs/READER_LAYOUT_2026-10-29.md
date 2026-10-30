# Reader width, photos and article fitting

## Changes

Reader now opens a full-screen WebKit surface with 24-CSS-pixel reading margins instead of the inset SwiftUI column. It uses the existing runtime reserved-region conversion and camera-fitting engine. Only colliding paragraphs narrow beside an obstruction; ordinary paragraphs use the available width, and fitting is removed when the obstruction no longer intersects. Original-page text, forms and scroll state remain separate.

Extraction preserves headings, paragraphs, article-header photos, captions and inline-image order. It handles visible editorial images marked presentation-only and direct text around nested paragraph/list containers. Visible article headlines replace SEO page titles. The document is built from escaped strings and validated HTTP(S) image URLs, never copied source HTML or generated executable code. Page JavaScript is disabled and the fixed CSP blocks scripts, connections, frames, forms and objects. Images use the source tab’s exact WebKit storage profile and blocker setting; private images remain ephemeral. Reader’s model never joins the saved tabs/history session and is released on dismissal.

Limits remain explicit: 5,000 visited nodes, 300 blocks, 40 images, 80 levels of traversal, 8,000 characters per text block, approximately 108,000 total text characters, and bounded image dimensions/URLs/alt text. Hidden, form and editable content is excluded. Reader is not an offline library; unavailable images retain WebKit’s alt-text fallback. Short or unavailable articles keep the original-page explanation.

## Main-page fitting

Two generic article patterns were reproduced as falling back before this change: non-scrolling wrappers that suppress horizontal overflow and ordinary column-flex article flow. Both now fit after scrolling stops, with measured pre/post geometry and rollback. Actual scrolling/clipping containers, reverse-flex layouts and changes that would newly clip text remain unsupported. Existing paragraph-size, descendant-scan and reading-anchor bounds remain in place; this does not claim universal website compatibility.

## Evidence and limits

The owner’s open New York Times article showed the original Reader’s right-side gap. After the app reload, the site presented a subscription screen. Final live-article behavior could not be verified through that screen; no access workaround was attempted. Committed visual evidence uses loopback synthetic content only.

Native checks exercise ordered image loading, full width, camera fit/restoration, source-form preservation, private-store identity, page-script blocking, escaped markup, temporary-view cleanup and both new main-page wrapper patterns. The verification summary in the PR records completed build/test results. Hardware touch/performance, full spoken VoiceOver and authenticated-site breadth remain unverified.

## Verification — October 29

- Debug and Release simulator builds succeeded; strict SwiftLint and diff whitespace checks passed.
- 62 Swift/policy checks and 167 browser/DOM assertions passed (25 page layout, 44 Reader, 14 camera avoidance, 71 settling, 13 nested layouts).
- Native WebKit checks passed 30 browser, 55 upgrade/Reader and 34 camera-settling assertions. The full run subsequently failed cookie persistence across relaunch; the focused persistence/memory rerun is recorded below.
- Visually exercised Reader scrolling, photo/caption order, dark appearance, dismissal, closed/open/partially folded poses and rotation. The source page remained available after dismissal. Done and reading settings stay grouped at the leading side.
- Synthetic screenshots: [full-width Reader](images/reader-layout/full-width.png) and [second photo with caption](images/reader-layout/photo-caption.png).

This pass did not complete the full VoiceOver, larger-system-text, pinch-zoom, keyboard and Reduce Motion matrix for the new Reader surface. Native tests cover geometry changes and rollback; physical-device touch, battery and performance remain unverified.
