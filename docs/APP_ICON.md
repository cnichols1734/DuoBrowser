# DuoBrowser app icon

The owner-selected artwork is a cyan-to-blue globe inside a white open-book / folding-screen outline, on a full-bleed dark navy background. It replaces the earlier compass and two-panel D concepts.

Source supplied by the owner on October 27, 2026: `Blue Globe Open Book Icon.png` (1254 × 1254, opaque PNG). At the owner's request, the built-in image editor removed the exterior white surround and extended the navy background to every edge and corner, retaining the central logo's composition and colors. The result was exported at 1024 × 1024 using macOS sips. The original supplied file remains unchanged.

Asset: `DuoBrowser/Assets.xcassets/AppIcon.appiconset/DuoBrowser-Icon.png`. The AppIcon catalog is included in the target resources and selected in both Debug and Release build settings. Xcode supplies required app-icon renditions and iOS supplies its additional corner mask. This is a raster asset; custom dark/tinted variants are not included. The product demo closing card uses the same asset.

## Verification

Simulator build and asset catalog compilation passed. The source is an opaque 1024 × 1024 PNG. Installed and visually verified on DuoBrowser QA: the dark background fills the icon with no exterior white border. The demo closing card was visually checked; the re-export remains 28 seconds and decodes without errors. No browser logic changed.

## Background edit prompt

Edit this exact app icon. Change ONLY the outer background: remove all of the white exterior surround/border outside the dark rounded tile, and extend the existing near-black navy background seamlessly to all four edges and all four corners of the square canvas. Output a full-bleed opaque square app icon; no rounded tile silhouette, no outer white border, no margin. Preserve the central white open-book/folding-screen outline and the cyan-to-blue globe exactly: same position, size, proportions, strokes, colors and details. Do not enlarge, crop, redraw or restyle the central logo. The WHITE logo strokes must stay white; only the exterior white surround becomes the dark navy background. iOS will apply its own rounded corners. No added elements, text, shadows, or effects.
