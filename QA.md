# SnapMark 1.0 — verification report

Date: 2026-11-10. Host: macOS 27.2, Apple Silicon, Swift 6.2.4 Command Line Tools. One built-in Retina display, 1920 × 1243 points, backing scale 2, 3840 × 2486 backing pixels.

## Automated verification

Command: `./scripts/test.sh` — exit 0. **25 checks passed: 15 core checks and 10 native checks.**

Core checks exercise real Core Graphics/Core Image rendering and real temporary filesystem stores:

- Negative display origins and Retina coordinate conversion.
- Crop clamping; undo/redo and redo invalidation.
- PNG dimensions and opaque concealment baked into export.
- Blur affects mask interior while leaving exterior unchanged.
- Flattened history persistence, reload and retention limits.
- Atomic-write rollback leaves existing state and files intact.
- Wide text metrics and Cyrillic text/mask orientation.
- Delete/reload consistency and corrupt-index preservation.
- Pen/highlighter/line/arrow/rectangle/ellipse/step/text visible raster output.
- JPEG transparency composited onto white.
- Horizontal line resizing and text resizing.
- Filesystem deletion failure (real immutable file) remains persisted and retryable.

Native checks compile the actual AppKit/SwiftUI application sources and exercise:

- Capture configuration retains 2× Retina pixels.
- Reopening the app preserves an active editor.
- Closing an editor releases its controller and screenshot session.
- Visible resize handles enter resize mode.
- Clearing existing text removes it.
- Live Cyrillic field-editor input is committed before image export.
- Native menu Copy/Save commands invoke actions directly.
- Native OCR close cancels the request; progress/result reuse one window.
- A cancelled OCR task cannot clear a later request's busy state or handle.
- Actual Apple Vision recognition of English and Russian sample text. Russian language support was available and the Cyrillic fixture was recognized.

The test runner is an autonomous throwing-assertion executable because this Command Line Tools installation contains neither XCTest nor Swift Testing. No downloaded dependencies or mocked image/filesystem behavior are required. The native OCR race test uses a controlled asynchronous recognizer to reproduce cancellation ordering; a separate check runs the real Vision recognizer.

## Manual checks in the built app

- Launch, welcome screen and menu-bar residency.
- Russian and English interface labels; live language switching.
- Dark/system appearance and compact matte editor toolbar, including accessibility labels for all tools.
- Real screen-capture permission denial/explanation and final permission grant through System Settings. Old ad-hoc permission state was reset only for `local.snapmark.app`; the exact final app was added via System Settings and Quit & Reopen. Final switch was observed on.
- Real region selection, immediate overlay editing and arrow drawing; Undo became available.
- Cancelled save dialog returned to the same editor with the edit intact.
- Successful copy closed the editor and created a flattened history entry.
- **Final Retina result: clipboard PNG and newest history entry both 550 × 250 pixels.** The earlier 1× configuration produced 275 × 125 for the same pointer selection; the final ScreenCaptureKit configuration fixes this.
- History browsing, selection and reopening a finished sample for new annotations.
- JPEG export through the native save dialog: valid 3200 × 2000 JPEG verified from disk.
- Pin command created an above-window native window at floating level 3; ordinary editor and OCR windows use their intended overlay levels.
- Debug and release builds completed; packaged app signature verified strictly.

The final `.app` is signed and its screen-capture permission is enabled at its current `outputs/SnapMark.app` location. Moving/rebuilding an ad-hoc app may require updating its permission entry. The source and documentation archives do not contain desktop captures, clipboard contents, history data, test logs or user settings.

## Not physically verified

- Mixed-DPI external displays, negative-origin physical display arrangements and a selection near every external-display edge. Coordinate math is covered automatically; no second monitor was available.
- Spaces/fullscreen application transitions and window capture spanning/occluded across physical displays. The complete-window ScreenCaptureKit filter and collection behaviors are implemented, but these arrangements were not manually exercised.
- A global hotkey triggered from a physical keyboard while another app is frontmost, and every possible system-reserved shortcut. Registration succeeded in the app; the recorder preserves an existing shortcut on registration failure.
- Light appearance and every toolbar tool in a full manual walkthrough. Rendering is covered for the drawing tools automatically; the native field editor and resize handle are also exercised automatically.
- macOS 14 on hardware; this build was run on the macOS 27.2 host.

## Implementation decisions

- New source repository in `work/SnapMark`, because the initial workspace had no repository or existing app.
- One fullscreen editor window with an embedded native material toolbar, rather than a sibling toolbar panel; this keeps focus and accessibility in one responder hierarchy.
- Autonomous CLT-compatible test executables instead of adding a network dependency for a test framework.
- History deletion tombstones retain only metadata for failed removals and retry on relaunch or explicit menu action. Source pixels and editable document objects are never persisted.
- No unresolved Important/Critical findings from the independent source review remain. Its editor ownership, OCR lifecycle, window-source filtering, menu commands and deletion issues were addressed; regression checks cover the affected behavior where it can be tested without an external display.


## 1.0.1 update — 2026-11-11

- Source repository moved to `PROGRAMMING/MY/SnapMark`; its Git history was retained locally.
- Default stroke width is now 12 px (approximately the middle of the 1–24 range) in both the editor defaults and annotation model.
- Added localized hover help to remaining buttons, shape fill, sliders, preferences, OCR actions, confirmation buttons and export format selection. Drawing tools now explain their interactions.
- Re-ran `./scripts/test.sh` after the move and code changes: exit 0, all 25 checks passed.
- Public source repository: https://github.com/quisty1/snap-mark . Application Support history and screenshots are excluded from publication.
- A rebuilt ad-hoc app can require a refreshed Screen Recording permission; the previous 1.0 real capture checks remain documented above.
