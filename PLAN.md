# SnapMark implementation contract

Approved 2026-11-10. A personal native macOS screenshot utility built with Swift 6, AppKit and SwiftUI, macOS 14+, Apple Silicon. Source is self-contained with no downloaded runtime dependencies.

## Capture and editing

Menu-bar resident, no permanent Dock icon, configurable global Ctrl–Shift–2 shortcut with registration error reporting. Region, complete window and selected-display capture through ScreenCaptureKit. Freeze display content before region selection/editor presentation. Exclude the application's own windows including pins. Retina and multiple screens supported; one region cannot span screens.

Immediate overlay editor with an on-screen compact matte contextual toolbar, system symbols, blue accent. Selection/move/resize, pen, translucent highlighter, line, arrow, rectangle, ellipse, text, step badges, Gaussian blur, pixelation, opaque concealment and crop. Color/width/fill/typeface size/weight/effect strength where relevant. Undo and redo include crop. Pan and zoom support.

Copy merged image closes editor. Save PNG/JPEG closes only on successful export; cancellation/failure keeps it open. Normal text shortcuts remain available in active text fields. Escape cancels without history. A second capture cannot silently discard the active edit.

## Additional features

Local Vision OCR of final rendered pixels including crop/masks; RU/EN with runtime language support detection, cancel and separate text copy which leaves editor open. Pin completed output in movable/resizable above-window image across Spaces. Completed copy/save/pin outputs enter flattened history; no source screenshots or editable annotations are persisted. PNG/thumbnail/versioned atomic JSON index in Application Support. Default retention 100 adjustable. Browse, copy/export/pin/reopen for new annotations/delete/clear. Failed history write does not undo successful export/copy and offers retry.

RU/EN automatic/system selection and manual override. Light/dark/system appearance. First-capture permission explanation, denial/retry handling. Local app/ZIP packaging, source archive and bilingual documentation.

## Acceptance

Automatic checks cover coordinate conversion, crop/undo/redo, masks/blur/text rendering, flattened persistence/retention/rollback/deletion, native editor lifetime/menu commands/text edits/handles, OCR cancellation identity and real local OCR. Manual visual checks cover welcome/settings/editor/history/export and permissions as access allows. Unavailable physical external-display/fullscreen conditions are recorded honestly in QA.

No cloud, accounts, networking, screen video, scroll stitching, public distribution, automatic updates, or unfinished-session recovery. Working name SnapMark. Save and pin complete the edit. Source remains in an isolated new repository; deliver app, archive and source with instructions.
