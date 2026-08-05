## v5.16.4.8

- Tapping the currently selected quick color again opens the color editor and replaces that color slot.
- Saved custom quick colors independently for Pen and Highlighter.
- Kept paper horizontally centered throughout pinch zoom and vertical navigation.
- Reserved one-finger touch for vertical scrolling in every tool while Apple Pencil/stylus input continues drawing and editing.

## v5.16.4.7

- Restored reliable pinch zoom with a native `InteractiveViewer` for continuous pages.
- Moved Highlighter back into the Pen tools group and unified its floating settings panel.
- Reworked handwriting filtering and curve rendering to remove visible angular joins at high zoom.
- Kept active-pen second tap as read mode, where the page can be panned freely.

# Changelog

## 1.1.15

- Tapping the already-selected Pen tool now switches to read-only navigation mode.
- Read mode disables ink input and allows free page panning and scrolling.
- The contextual floating tool-options card hides while read mode is active.
- Tapping Pen again restores the last selected pen and its settings.

## 1.1.14

- Added Goodnotes-style precision and whole-stroke eraser modes.
- Added independent eraser sizing, continuous eraser sweeps, highlighter-only erasing and automatic return to the previous pen.
- Added a live eraser cursor and kept typed text protected from the ink eraser.
- Added pressure sensitivity controls and stored sensitivity with every stroke.
- Rebuilt fountain and brush rendering as smooth variable-width ribbons with Catmull-Rom interpolation.
- Kept ball-pen width stable and improved highlighter blending.

## 1.1.13

- Rendered handwriting with quadratic curves and interpolated Pencil samples.
- Prevented light Apple Pencil pressure from collapsing normal pen strokes into hairlines.
- Kept stroke widths, text and selection controls proportional in continuous zoom.
- Anchored pinch zoom under the fingers and discarded stale scroll corrections to reduce jumping.
- Preserved each imported PDF page aspect ratio, including landscape and mixed-size PDFs.
- Updated page thumbnails to follow the real PDF page orientation.

## 1.1.12

- Replaced snap-style vertical PageView navigation with continuous blog-style scrolling.
- Pages are stacked in one scrollable document with spacing between sheets.
- Scrolling updates the active page and page thumbnail automatically.
- Selecting a thumbnail scrolls smoothly to that page in continuous mode.
- Stylus input remains available on the active sheet while touch scrolling stays natural.

## 1.1.0

- Reworked the library into a responsive, platform-neutral layout.
- Added compact bottom navigation and wide-screen navigation rail.
- Added system/light/dark appearance modes.
- Fixed phone grid sizing and editor toolbar overflow.
- Added compact mobile page controls.
- Fixed live ink repainting, straight-line storage, text selection/movement and text erasing.
- Implemented folder moves, safer folder deletion and correct created-date sorting.
- Prevented sample notes from returning after deleting all data.
- Fixed Android plugin registration so sharing and file-path plugins can load normally.
- Replaced hard-coded Flutter paths with a portable PowerShell runner.
- Added store and launch tests.

## 5.16.4.4
- Split Highlighter into its own top-level drawing tool beside Pen.
- Tapping an active Highlighter opens a dedicated floating settings panel.
- Pen settings now contain only Ball, Fountain, and Brush pen styles.
- Highlighter remembers its own width and color, with dedicated presets.
