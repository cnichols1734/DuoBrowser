# Maintained content blocking

## Behavior

DuoBrowser bundles EasyList, EasyPrivacy and the optional EasyList Cookie List.
The first two are enabled by the existing global/per-site blocking preferences;
cookie-notice filtering is separately opt-in. Supported network and cosmetic
rules compile through WKContentRuleListStore. No scriptlets, downloaded
JavaScript, generic extension host or request telemetry is added.

Filter Lists shows the filter date, automatic-update preference, manual Update
Now and offline credits/licenses. Startup and normal-browsing foreground activation check for updates after four days,
with an in-process one-hour failure backoff. Downloads use fixed HTTPS source
URLs, an ephemeral cookie/cache-free session, no redirects, byte/time limits,
UTF-8/header validation and minimum converted-list sizes. All three candidate
lists must compile and the source snapshot must save atomically before any
active list is replaced. Failed updates keep working rules. The bundled lists
work offline; a clearly described 19-service fallback remains available if the
maintained sources cannot compile. The small baseline also lets browsing start
while full protection prepares on first use; the UI reports preparation and
automatically promotes existing tabs without reloading. Compilation caches are content-addressed;
obsolete app-owned compiled lists are removed after a successful installation.
A bounded source-fingerprint and converter-version manifest reuses complete
compiled variants on later launches. Missing or corrupt cache entries rebuild;
initial conversion/compilation remains required once per uncached filter set.
Automatic refresh rechecks normal foreground eligibility after preparation and
before networking. Stale preparation callbacks cannot override newer protection settings.

Updates apply to new requests in existing tabs, previews and Reader without
reloading the page. Per-site switches now also preserve drafts. Visual hiding
may need a deliberate reload; the protection view offers one. Private site
exceptions remain session-only. Filter data is public/shared and never derived
from browsing. Private browsing causes no site-specific downloads or reports.

## Licensing decision

The EasyList project's official license page explicitly offers GPLv3-or-later
**or** CC BY-SA 3.0-or-later: https://easylist.to/pages/licence.html . This project
selects **CC BY-SA 3.0 Unported** for EasyList/EasyPrivacy data. The Cookie List's
own header specifies **CC BY 3.0 Unported**. Original headers and source lists,
full license texts, attribution and snapshot hashes are in `DuoBrowser/FilterLists`.
Converted EasyList/EasyPrivacy data remains CC BY-SA 3.0. Transformations are
described in NOTICE.md and in the app. The lists are distributed separately from
the independent MIT converter/application code; no AdGuard GPL converter is
linked or copied and no app-wide license change is made. No commercial license,
subscription or new runtime code dependency is required by this chosen path.

Refresh bundled sources with `python3 scripts/update-filter-bundle.py`; review
source/licensing changes, run portable and native compilation checks, and submit
the updated snapshots through a PR. Automatic in-app updates use the same
converter and retain source attribution. Website content and trademarks are not
relicensed or bundled as part of these sources.

## Supported subset and limits

Supports literal/anchored URL patterns, wildcards, separator characters,
third/first-party restrictions, specific fetch/other/top-document/child-document and common resource types, positive/negative domain
scopes, network/document exceptions, basic CSS selectors (including native
`:has`), selector exemptions and `badfilter`. All enabled source text is converted together so network and selector exceptions
apply across sources. Network and cosmetic chunks each repeat their relevant
exceptions after blocking rules. Standard and cookie-enabled variants compile
separately, so cookie exceptions cannot weaken standard protection. A document exception
uses a top-page URL condition, so it applies to that page's resources.

Unsupported blocking modifiers, regular-expression filters, mixed positive and
negative domain scopes and non-declarative/procedural/scriptlet rules are
skipped as a whole rather than dropping conditions. A separator requires an
actual separator character; end-only matches are conservatively omitted.
Generic/element-hide exceptions can permit more cosmetic content than an ABP
engine, conservatively favoring website function. Unsupported exception modifiers remain a limitation; per-site exceptions remain
the recovery control. This is a larger maintained *supported subset*, not uBlock or
AdGuard feature parity, guaranteed video-ad removal, or a measured real-world
blocking percentage. Hiding consent notices does not choose consent.

## Verification

The portable converter tests cover scope/resource preservation, exceptions in
split lists, selector exemptions, unknown-condition rejection, disabled rules,
host boundaries, malformed/oversized sources and document allowlisting. Native
checks exercise actual fetch blocking/allowing, cosmetic hiding, draft-preserving
site toggles and last-working-update retention with synthetic fixtures.

Build/test results and simulator UI evidence are tracked in the
[review record](reviews/2026-11-12-content-blocking/README.md).
Physical-device battery/endurance, full spoken VoiceOver and representative
real-site/ad/video effectiveness require separate evidence; do not infer them
from source list size or synthetic test passes.
