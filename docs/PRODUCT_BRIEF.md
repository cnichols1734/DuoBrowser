# Product brief

Status: direction approved by the owner on October 26, 2026: ‘Yes, use this direction.’ Detailed timings and implementation behavior still require prototype validation.

## 1. Feature summary

A native browser that uses the Duo's display generously while keeping websites readable and interactive. The closed outer screen is the first priority; opening the device should retain the same tab, page, reading position, and navigation model.

## 2. Primary action

Open a site and use it comfortably, including controls that would otherwise sit beneath the camera or system overlays.

Success means measurably more usable page space than Safari on the same device, with no loss of essential site actions. Full-width backgrounds alone do not count.

## 3. Design direction

Follow the content-first direction in ../.impeccable.md: calm native chrome, clear site identity, and restrained, fluid transitions. Safari supplies the familiarity benchmark; Brim supplies an example of camera avoidance. Branding remains open.

## 4. Layout strategy

- Outer display: full-width web canvas where proven safe, a compact floating address/control cluster, and no permanently reserved full-height browser rail.
- Inner display: preserve control relationships and page state; show optional tab navigation only when space supports it. Do not automatically split the website or reload it on opening.
- Exclusions: derive camera, expanded system occlusion, fold, keyboard, and browser-control areas from current geometry. Reclaim space around these areas, not underneath essential interaction.
- Proposal: bottom address entry on both displays; compare its reachability against a compact edge alternative during the first prototype.

## 5. Key states

| State | Required behavior |
| --- | --- |
| New tab | Address/search field, recent or bookmarked destinations when available |
| Loading | Stable controls, progress, stop/retry; no oscillating layout |
| Normal page | Clear site identity; back, tabs, share, and page options reachable |
| Expanded page | Controls collapse with a persistent, accessible way to reveal them |
| Camera collision | Minimal displacement; original action and focus remain intact |
| Unsupported layout | Original layout or conservative inset; a clear restore option |
| Fold/rotate/zoom | Recompute geometry, cancel stale work, preserve page state |
| Keyboard/form | Keep focused input and submit controls reachable; stop moving active controls |
| AI unavailable | Browsing and deterministic adaptation continue |
| Private browsing | Distinct state; no persisted page history or adaptation data |
| Failure/offline/crash | Explain failure, retry, and restore tabs without a loop |

## 6. Interaction model

Tap the address field to edit, use standard back/forward gestures, and open tabs through a compact control. Scroll may collapse chrome, but essential controls must remain recoverable without relying only on an invisible gesture.

On collision, measure the original and final positions, commit a validated layout adjustment, and animate the visual difference. Proposed initial timing: 180–240 ms, decelerating, with no repeated bounce. Recheck hit targets and reading order. Reduce Motion uses an immediate update or subtle fade.

Provide page options for **Fit around camera**, **Original layout**, and **Always use original layout on this site**. For the experiment, adaptation is explicitly enabled so results can be compared. A production default is a later decision.

## 7. Content requirements

Use ordinary browser language: “Search or enter website”, “Tabs”, “Reload”, “Private”, “Original layout”. A fallback can say “This page works better in its original layout.” Avoid exposing CSS, prompts, or model status in normal browsing controls.

Plan for long URLs, right-to-left sites, very large text, empty history, many tabs, and pages that change after loading. No welcome dashboard should displace the address field as the primary task.

## 8. Implementation references

Use Apple's Duo layout guidance and reserved-region APIs in RESEARCH.md. During implementation, consult the Impeccable spatial, interaction, motion, and responsive references where useful; native Apple patterns take precedence over web-specific styling recipes.

## 9. Open questions

- Approved: familiar native feel and floating bottom controls. Validate their reachability in the prototype.
- Choose a product name later; DuoBrowser is only a repo name.
- Which 5–10 sites matter most in the owner's daily browsing? Until supplied, use varied synthetic fixtures and public sites.
- Decide the default adaptation mode after real-site testing and review of default-browser requirements.
- Decide broader iPhone/iPad support after the Duo experiment succeeds.
