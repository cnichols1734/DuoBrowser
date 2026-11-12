# Setup centering — November 12, 2026

The owner’s screenshot showed the introduction aligned to the narrower camera-safe region instead of the display. Every setup step inherited the same asymmetric horizontal safe area.

Setup now uses the full horizontal bounds while preserving vertical safe-area behavior. Welcome, transfer, default-browser and tour headings and actions share that center axis. Progress has an independent centered position, so different Back and Skip widths cannot shift it. Transfer rows retain readable leading alignment inside the centered column. Accessibility-sized actions remain in the scroll view.

Only top controls that actually overlap an active system occlusion receive vertical clearance. UIKit reports the current reserved frames and margins; the shared navigation row moves below those rectangles, leaving the page’s horizontal axis unchanged. No camera position, pose-width rule or persistent full-height camera rail is introduced. Measurements use the setup coordinate space and remove existing clearance before recalculation to avoid oscillation.

Twelve new native assertions exercise measured obstruction clearance, an unoccupied camera edge, multiple obstructions, all four steps with left/right asymmetric safe areas and maximum accessibility text. Existing setup transfer, cancellation, review, persistence and reentry checks remain in the same batch. The expected Setup receipt is 36 checks.

Debug and Release simulator builds, 328 portable assertions, source parsing, strict SwiftLint and repository/whitespace checks pass. The 12 new native assertions compile. Runtime and visible closed/open/partial/rotated checks are pending the coordinated simulator slot and will be recorded separately; source review is not evidence of visual centering. Simulator evidence does not establish hardware touch, battery, real Safari transfer eligibility or full spoken VoiceOver behavior.
