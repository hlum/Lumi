# Lumi: task list

The plan and the reasoning behind it are in `tasks/plan.md`. The folder layout used in "Files" is defined in plan.md → *Folder layout*.

**How every task is done (test-first, CI-verified):**
1. **Red:** write Swift Testing tests for the task's acceptance criteria first; they fail.
2. **Green:** implement until the tests pass.
3. **Build locally:** `xcodegen generate && xcodebuild -project Lumi.xcodeproj -scheme Lumi -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds. Tests aren't run locally.
4. **Xcode Cloud** runs the full test suite on every push and pull request (set up in T02). **A task is done only when its Xcode Cloud run is green.**
5. **Device check:** only where a task says "device". The simulator has no camera, no Core ML/Neural Engine performance and no Apple Intelligence; that code is unit-tested through fakes.

Tests run on Xcode Cloud without the repository present. Any fixture a test needs (images, JSON, LUTs) must be bundled into the LumiTests target, not read from source folders. BunnyBank learned this the hard way.

**Credits rule.** Any task that adds an asset, font, model, sound or third-party code adds its entry to `Lumi/Resources/Credits.json` **in the same task**. The credits tests (created in T01) fail CI on any file without a complete entry, so nothing ships uncredited.

**iPhone only.** No iPad layout.

**Nothing is built until Checkpoint D (design approved).**

Scope: S = 1–2 files · M = 3–5 files. Anything larger has been split.

## Status
Tick a task when it's done. `[~]` = core logic built and tested, screen or device check still pending. The details for each task are below.

**Phase Q: Quality — makeup, face, body (TOP PRIORITY, added 2026-10-12)**
Lumi is a personal app that will not be released, so research/non-commercial models and app size are allowed. Details in the Phase Q section at the end of this file.
- [x] Q0 Quality bench and personal-use licence rules (12 Commons photos in `bench/`, `scripts/bench.sh push|pull`, `QualityBenchTests`)
- [x] Q1 Constrained mesh-warp engine (rigid MLS, 1/d⁴ weights, pins, local solve; `MLSWarp`). Line-preserving energy pass deferred until the body bench needs it
- [~] Q2 Face reshape on the new engine (chin, jaw, V shape, width, cheekbones, lift, eyes, nose, mouth done in `FaceHandles`; Eyes/Nose/Mouth/Brows detail tabs and forehead still on brushes)
- [~] Q3 Body reshape on the new engine (`BodyHandles`: mask edges per part, arm/torso separation, pins outside the outline, leg length stretches whole rows; side views and seated poses still weak)
- [ ] Q4 Makeup on face parsing (pixel masks, luminance-preserving colour, finishes, occlusion)
- [ ] Q5 Dense face landmarks (MediaPipe 478)
- [ ] Q6 3D body shape fit (SMPL-X) for weight/shape sliders
- [ ] Q7 Learned body-reshape flow (BR-5K model) as a second engine, compared on the bench
- [ ] Q8 Makeup transfer from a reference photo (EleGANt / BeautyREC)
- [ ] Q9 3D face fit for turned heads (3DDFA-V2 class)
- [ ] ⏸ Checkpoint Q: user compares bench sheets (and their own photos) against Meitu

**Phase D: Design (before any build)**
- [ ] ⏸ Checkpoint D: designs approved

**Phase 0: Scaffold, CI and risk spikes**
- [x] T01 Project scaffold
- [x] T02 Xcode Cloud CI and TDD harness
- [x] T03 Spike: LaMa on device
- [x] T04 Spike: real-time preview
- [x] T05 Spike: mesh-warp engine
- [x] T06 Spike: hair segmentation
- [ ] ⏸ Checkpoint 0

**Phase 1: Editing foundation**
- [x] T07 Import → edit → save, end to end
- [x] T08 Undo / redo / before–after compare
- [x] T09 Projects and drafts
- [x] T10 Brush and mask infrastructure
- [x] T11 Analysis service
- [x] T12 Face / person picker and portrait manager
- [ ] ⏸ Checkpoint 1

**Phase 2: Basic edit and color**
- [x] T13 Crop, rotate, straighten
- [x] T14 Resize, canvas, export settings
- [x] T15 Adjust panel
- [x] T16 HSL, curves, split tone, color picker
- [x] T17 Filter engine
- [x] T18 Content: filter pack v1
- [~] T19 Smart color tools
- [x] T20 AI Flash and face fill light
- [ ] ⏸ Checkpoint 2

**Phase 3: Overlays**
- [x] T21 Text basics
- [x] T22 Text styles
- [x] T23 Stickers
- [x] T24 Custom stickers
- [~] T25 Frames, doodle and marker
- [x] T26 Mosaic and face cover
- [x] T27 Watermarks
- [~] T28 Content: stickers, fonts, frames, brush materials
- [ ] ⏸ Checkpoint 3

**Phase 4: Remover, cutout, expand**
- [~] T29 Remover v1, brush and box
- [x] T30 Remover auto chips
- [~] T31 Clone tab and specialty removers
- [~] T32 Cutout and background
- [x] T33 Batch cutout
- [~] T34 AI Expand
- [ ] ⏸ Checkpoint 4

**Phase 5: Face retouch**
- [x] T35 Skin smoothing and texture
- [~] T36 Skin tone
- [~] T37 Blemishes
- [~] T38 Under-eye and wrinkles
- [~] T39 Face-shape warps
- [~] T40 Ratio, 3D and protection
- [~] T41 Eye, nose, mouth and brow warps
- [~] T42 Eye detail and teeth
- [x] T43 Manual face slim and volume
- [x] T44 Auto beauty
- [ ] ⏸ Checkpoint 5

**Phase 6: Makeup and hair**
- [x] T45 Makeup engine: lips, blush, contour
- [x] T46 Eye makeup and brows
- [x] T47 Makeup content, looks, recreate
- [~] T48 Nail try-on
- [x] T49 Hair color
- [x] T50 Hair shape
- [ ] ⏸ Checkpoint 6

**Phase 7: Body**
- [~] T51 Lower-body and torso warps
- [~] T52 Upper body, presets, auto
- [x] T53 Manual body brushes
- [~] T54 Background protection
- [ ] ⏸ Checkpoint 7

**Phase 8: Recipes, batch, collage, materials**
- [~] T55 Recipes
- [~] T56 Batch edit
- [~] T57 Collage templates
- [~] T58 Freeform, split, seamless collage
- [~] T59 Long stitch and screenshot stitch
- [~] T60 Materials, templates, wallpapers
- [ ] ⏸ Checkpoint 8

**Phase 9: Camera**
- [~] T61 Camera core
- [~] T62 Live beauty camera
- [ ] T63 Camera modes
- [ ] T64 AR "Cutie" mode and camera music
- [ ] T65 Camera extras
- [ ] ⏸ Checkpoint 9

**Phase 10: Live Photos**
- [ ] T66 Live Photo editor
- [~] T67 Live overlays and conversion
- [ ] T68 Live collage and batch
- [ ] ⏸ Checkpoint 10

**Phase 11: Video**
- [~] T69 Timeline core
- [~] T70 Clip operations and transitions
- [~] T71 Per-clip color and effects
- [~] T72 Text, stickers, keyframes
- [~] T73 Overlay video, masks, tracking
- [~] T74 Audio
- [~] T75 Captions and teleprompter
- [~] T76 Video retouch
- [~] T77 Video quality
- [~] T78 Video and Live erase
- [~] T79 Video extras
- [ ] ⏸ Checkpoint 11

**Phase 12: On-device AI**
- [~] T80 Enhancer and upscaler
- [~] T81 Old-photo restoration
- [ ] T82 Image Playground creations
- [x] ~~T83 AI Assistant~~ (dropped)
- [ ] T84 AI text replace and AI copywriting
- [ ] T85 Effects and "animate photo"
- [ ] ⏸ Checkpoint 12

**Phase 13: Utilities**
- [~] T86 ID photo
- [~] T87 Scanner
- [~] T88 GIF and emoji maker
- [ ] ⏸ Checkpoint 13

**Phase 14: App shell, polish, release**
- [~] T89 Home, Tools, search, tutorials
- [~] T90 Settings and attributions
- [~] T91 Widgets, Control, Shortcuts
- [~] T92 Long jobs and recent tasks
- [~] T93 Localization
- [ ] T94 Performance, memory, accessibility
- [~] T95 Release prep
- [ ] ⏸ Final checkpoint


---

## Phase D: Design (before any build)
The design work comes next; its tasks are defined in the design session. The outputs feed every phase below: screen designs per module, the native component behind each screen, and a reason for every custom element.

### Checkpoint D
- [ ] Designs approved by you.
- [ ] `plan.md` and `todo.md` updated with anything the design changes.

---

## Phase 0: Scaffold, CI and risk spikes

### T01: Project scaffold (S)
XcodeGen project with the Lumi app and LumiTests targets, iOS 26, and a native `TabView` shell: Home / Projects / Settings placeholders.
- **Acceptance criteria:**
  - `project.yml` generates a project that launches to the tab shell.
  - iPhone only (`TARGETED_DEVICE_FAMILY = 1`).
  - Credits system from day one:
    - `Lumi/Resources/Credits.json` (fields and allowed licenses as in plan.md → *Content and credits*).
    - `LumiTests/CreditsTests.swift` with the coverage test (every resource file has an entry) and the completeness test (all fields present, license on the allow-list).
  - The folder layout matches plan.md.
  - LumiTests contains one Swift Testing smoke test.
- **Verify:** build.
- **Deps:** Checkpoint D.
- **Files:** `project.yml`, `Lumi/App/LumiApp.swift`, `Lumi/App/RootTabView.swift`, `Lumi/Resources/Credits.json`, `LumiTests/SmokeTests.swift`, `LumiTests/CreditsTests.swift`.

### T02: Xcode Cloud CI and TDD harness (M)
- **What:**
  - Initialize git and push to a private GitHub repo (`hlum/Lumi`, matching BunnyBank). Asks you before creating it.
  - Create the App Store Connect app record and bundle ID (codename name).
  - Add a shared scheme and `Lumi.xctestplan` (unit tests, one simulator destination).
  - Commit the generated `.xcodeproj` so Xcode Cloud needs no XcodeGen install and spends no extra build minutes.
  - Xcode Cloud workflow "CI": runs on every pull request and every push to `main`; actions are Build, then Test on the latest iPhone simulator. **You create the workflow in Xcode** (Product → Xcode Cloud → Create Workflow); it can't be scripted.
  - Add a `ci_scripts/` folder only if a step needs it, using the BunnyBank pattern.
  - Bundle test fixtures into LumiTests (see the CI rule at the top).
  - Record the Xcode Cloud free monthly compute allowance that comes with your membership (verify the current hours) and keep runs lean.
- **Acceptance criteria:**
  - A push triggers an Xcode Cloud run that builds and passes the smoke test.
  - A deliberately failing test turns the run red; the test is then removed.
  - A test that loads a bundled fixture passes on Xcode Cloud.
- **Verify:** Xcode Cloud run green; `docs/ci.md` describes the workflow and the TDD loop.
- **Deps:** T01.
- **Files:** `project.yml`, `Lumi.xctestplan`, `.gitignore`, `LumiTests/Fixtures/`, `docs/ci.md`.

### T03: Spike: LaMa on device (M, device)
Integrate the LaMa Core ML package. Inpaint a crop around a mask, then blend it back at full resolution.
- **Acceptance criteria:**
  - Latency and peak memory are measured on a ~4 GB device (iPhone 11-class) and on an iPhone 15 Pro.
  - A crop/tile strategy for 12–48 MP images is written down.
  - The license of the conversion and the upstream weights is verified (expected Apache-2.0).
  - A go/no-go is recorded.
- **Verify:** build; device run; findings in `docs/spikes/lama.md`.
- **Deps:** T01.
- **Files:** `Lumi/Core/ML/Inpainter.swift`, `Lumi/Resources/Models/`, `docs/spikes/lama.md`, `Lumi/Resources/Credits.json`.

### T04: Spike: real-time preview (M, device)
Core Image on Metal in an `MTKView`. A slider drives a filter at proxy resolution with no visible lag on a 48 MP photo; export renders at full resolution.
- **Acceptance criteria:**
  - Frame time and memory are recorded.
  - The proxy-preview vs. full-res-export approach is decided.
  - Custom view justified: SwiftUI `Image` can't do 60 fps GPU preview.
- **Verify:** build; device run; `docs/spikes/preview.md`.
- **Deps:** T01.
- **Files:** `Lumi/Core/Render/MetalPreviewView.swift`, `Lumi/Core/Render/Renderer.swift`, `docs/spikes/preview.md`.

### T05: Spike: mesh-warp engine (M)
A displacement-grid warp in Metal, plus a pinch / bloat / push brush prototype.
- **Acceptance criteria:**
  - Warps a full-res image without seams or aliasing.
  - Brush strokes accumulate and can be undone.
  - The displacement field is serializable (needed for non-destructive edits).
- **Verify:** build; tests for displacement math; `docs/spikes/warp.md`.
- **Deps:** T04.
- **Files:** `Lumi/Core/Render/MeshWarp.swift`, `Lumi/Core/Render/Kernels.metal`, `LumiTests/MeshWarpTests.swift`, `docs/spikes/warp.md`.

### T06: Spike: hair segmentation (M, device)
Vision has no hair mask. Find an on-device hair-segmentation model (candidate: MediaPipe hair segmentation), convert it to Core ML, and measure quality and speed.
- **Acceptance criteria:**
  - Mask quality is checked on 10 varied photos.
  - The license allows redistribution (verified, not assumed).
  - If no model passes, a fallback is decided (person mask minus face landmarks, plus a brush) and hair tasks are re-scoped.
- **Verify:** build; device run; `docs/spikes/hair.md`.
- **Deps:** T01.
- **Files:** `Lumi/Core/ML/HairSegmenter.swift`, `docs/spikes/hair.md`, `Lumi/Resources/Credits.json`.

### Checkpoint 0
- [ ] LaMa, preview, warp and hair each have a go/no-go recorded.
- [ ] Xcode Cloud green on `main`.
- [ ] **Human review before Phase 1.** Spike results may re-shape later phases.

---

## Phase 1: Editing foundation

### T07: Import → edit → save, end to end (M)
- **What:** pick a photo with `PhotosPicker`, load it at full resolution with the correct orientation, and create an `EditDocument` holding one operation (exposure). Render through `Renderer` (a pure function of document + analysis + frame), save to Photos (add-only permission), and share with `ShareLink`.
- **Acceptance criteria:**
  - A picked photo opens in the editor.
  - The exposure slider previews live.
  - The saved photo appears in Photos with the edit applied at full resolution.
- **Verify:** build; tests for `EditDocument` Codable round-trip and renderer determinism.
- **Deps:** T04.
- **Files:** `Lumi/Core/Document/EditDocument.swift`, `Lumi/Core/Document/EditOperation.swift`, `Lumi/Features/Editor/EditorView.swift`, `Lumi/Features/Editor/EditorModel.swift`, `LumiTests/EditDocumentTests.swift`.

### T08: Undo / redo / before–after compare (S)
- **Acceptance criteria:**
  - Undo and redo work across every operation.
  - Press-and-hold shows the original.
  - Re-opening a photo restores its operation list, not baked pixels.
- **Verify:** build; undo-stack tests.
- **Deps:** T07.
- **Files:** `Lumi/Core/Document/UndoStack.swift`, `Lumi/Features/Editor/EditorModel.swift`, `LumiTests/UndoStackTests.swift`.

### T09: Projects and drafts (M)
- **What:** a SwiftData `Project` (original file, document JSON, thumbnail). Projects tab with a grid, autosave, delete and duplicate. Handles a deleted or missing original.
- **Acceptance criteria:**
  - Killing the app mid-edit and relaunching restores the draft.
  - The Projects grid lists drafts, newest first.
- **Verify:** build; persistence tests with an in-memory container.
- **Deps:** T08.
- **Files:** `Lumi/Core/Document/Project.swift`, `Lumi/Features/Projects/ProjectsView.swift`, `Lumi/Features/Projects/ProjectStore.swift`, `LumiTests/ProjectStoreTests.swift`.

### T10: Brush and mask infrastructure (M)
- **What:**
  - Paint and erase a mask with size and hardness controls; pinch-zoom while painting; box select.
  - Smart select from Vision subject and person masks.
  - The mask is a `CIImage` stored in the document.
- **Acceptance criteria:**
  - Any tool can request a mask.
  - Masks survive save and reopen.
  - Smart select picks the tapped subject.
- **Verify:** build; mask-serialization tests.
- **Deps:** T07.
- **Files:** `Lumi/Core/Mask/MaskCanvas.swift`, `Lumi/Core/Mask/BrushEngine.swift`, `Lumi/Core/Mask/MaskStore.swift`, `LumiTests/MaskTests.swift`.

### T11: Analysis service (M)
- **What:** face landmarks and rectangles, body pose, person instance masks, foreground subject masks and text regions. Uses the iOS 26 Swift Vision API; check the current request names against the docs.
- **Behavior:** results are cached per image. A per-frame API takes a temporal-smoothing hook (One-Euro filter) for Live, video and camera.
- **Acceptance criteria:**
  - One call returns all analyses.
  - Cache hits skip Vision.
  - The smoothing filter reduces jitter on a synthetic noisy track.
- **Verify:** build; smoothing tests.
- **Deps:** T07.
- **Files:** `Lumi/Core/Analysis/Analyzer.swift`, `Lumi/Core/Analysis/AnalysisCache.swift`, `Lumi/Core/Analysis/Smoothing.swift`, `LumiTests/SmoothingTests.swift`.

### T12: Face / person picker and portrait manager (S)
- **Acceptance criteria:**
  - Tap a face or person to target it; multi-select applies to several.
  - Detected people are listed per project and can be renamed ("portrait manager").
  - Edits store per-person targets.
- **Verify:** build.
- **Deps:** T11.
- **Files:** `Lumi/Features/Editor/PersonPicker.swift`, `Lumi/Core/Document/PersonTarget.swift`.

### Checkpoint 1
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: import → edit → save → reopen draft → undo all works.
- [ ] Human review.

---

## Phase 2: Basic edit and color

### T13: Crop, rotate, straighten (M)
- **What:** free crop and ratio presets (including social sizes), 90° rotation, free angle, flips, auto-straighten, perspective and lens-distortion correction.
- **Acceptance criteria:**
  - Each control round-trips through the document.
  - Auto-straighten levels a tilted horizon.
- **Verify:** build; geometry tests.
- **Deps:** T08.
- **Files:** `Lumi/Features/Crop/CropView.swift`, `Lumi/Features/Crop/CropModel.swift`, `Lumi/Core/Render/GeometryOps.swift`, `LumiTests/GeometryTests.swift`.

### T14: Resize, canvas, export settings (M)
- **What:**
  - Resize in px, mm/cm with DPI, or print sizes.
  - Blank canvas with background color/blur and alignment.
  - Export as HEIC, JPEG or PNG with quality and max-size options.
  - Compression with a size estimate.
- **Acceptance criteria:**
  - A 10×15 cm export at 300 dpi comes out as 1181×1772 px.
  - PNG export keeps transparency.
- **Verify:** build; unit-conversion tests.
- **Deps:** T13.
- **Files:** `Lumi/Features/Resize/ResizeView.swift`, `Lumi/Features/Canvas/CanvasView.swift`, `Lumi/Core/Document/ExportSettings.swift`, `LumiTests/ResizeTests.swift`.

### T15: Adjust panel (M)
- **What:** light, exposure, contrast, saturation, vibrance, temperature, tint, highlights, shadows, sharpen, grain, vignette, fade, and warm/cool/vivid presets.
- **Acceptance criteria:**
  - Every slider previews live.
  - Values persist.
  - Resetting a single slider works.
- **Verify:** build; tests mapping parameters to filter values.
- **Deps:** T07.
- **Files:** `Lumi/Features/Adjust/AdjustView.swift`, `Lumi/Core/Render/AdjustOps.swift`, `LumiTests/AdjustOpsTests.swift`.

### T16: HSL, curves, split tone, color picker (M)
- **Acceptance criteria:**
  - Curves have RGB and per-channel modes plus presets.
  - HSL has 8 hue bands.
  - Split tone and posterize work.
  - A reusable palette/eyedropper component samples colors from the photo.
- **Verify:** build; curve-interpolation tests.
- **Deps:** T15.
- **Files:** `Lumi/Features/Adjust/CurvesView.swift`, `Lumi/Features/Adjust/HSLView.swift`, `Lumi/Shared/ColorPickerPanel.swift`, `Lumi/Core/Render/ColorOps.swift`, `LumiTests/CurveTests.swift`.

### T17: Filter engine (M)
- **What:** `.cube` LUT filters with categories, intensity, favorites, recents, search and a filter manager (reorder/hide). An eraser removes the filter locally (mask from T10). Auto color fix uses Core Image's auto-adjust.
- **Acceptance criteria:**
  - Filters apply at any intensity.
  - The eraser removes the filter locally.
  - Favorites persist.
- **Verify:** build; LUT parser tests.
- **Deps:** T10, T15.
- **Files:** `Lumi/Core/Render/LUT.swift`, `Lumi/Features/Filters/FilterBrowserView.swift`, `Lumi/Features/Filters/FilterStore.swift`, `LumiTests/LUTTests.swift`.

### T18: Content: filter pack v1 (M, content)
- **What:** about 60 self-made LUTs: flash/digicam/CCD, film, camera simulation, Japanese, cinematic, Chinese color tones, basics. Each LUT gets a thumbnail.
- **Acceptance criteria:**
  - Every LUT is listed in `Lumi/Resources/Credits.json` as self-made.
  - Every LUT has a category and a localized name key.
- **Verify:** build; a test loads every bundled LUT.
- **Deps:** T17.
- **Files:** `Lumi/Resources/Filters/`, `Lumi/Resources/Filters/catalog.json`, `Lumi/Resources/Credits.json`, `LumiTests/FilterCatalogTests.swift`.

### T19: Smart color tools (M)
- **What:**
  - Extract a filter from a reference photo (color transfer in Lab space).
  - Partial adjust with a brush mask.
  - Tone unify across several images.
  - "AI color" auto-enhance.
  - Light/shadow recovery.
  - Photo dehaze (dark-channel-prior kernel).
  - Night-view enhance (denoise, shadow lift, local contrast).
- **Acceptance criteria:**
  - A reference photo's grade transfers visibly.
  - Partial adjust stays inside the mask.
- **Verify:** build; color-transfer tests on synthetic images.
- **Deps:** T16, T10.
- **Files:** `Lumi/Core/Render/ColorTransfer.swift`, `Lumi/Features/Adjust/PartialAdjustView.swift`, `Lumi/Features/Adjust/SmartColorView.swift`, `LumiTests/ColorTransferTests.swift`.

### T20: AI Flash and face fill light (S)
- **What:** a face-masked relight with a flash look (contrast, specular highlight, falloff), with slider and eraser.
- **Acceptance criteria:**
  - Brightens dark faces without blowing out the background.
  - Strength is adjustable.
- **Verify:** build.
- **Deps:** T11, T17.
- **Files:** `Lumi/Features/Relight/RelightView.swift`, `Lumi/Core/Render/RelightOps.swift`.

### Checkpoint 2
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: crop, adjust, filter and save on a 48 MP photo; preview stays smooth.
- [ ] Human review.

---

## Phase 3: Overlays

### T21: Text basics (M)
- **What:** add and edit text with system fonts plus bundled OFL fonts; size, color, gradient, stroke, shadow and alignment; move/scale/rotate gestures; an emoji and kaomoji picker.
- **Acceptance criteria:**
  - Text renders identically in the preview and in the full-res export.
  - Several text layers are supported.
- **Verify:** build; layer-model tests.
- **Deps:** T08.
- **Files:** `Lumi/Features/Text/TextLayerView.swift`, `Lumi/Features/Text/TextEditorSheet.swift`, `Lumi/Core/Document/Layer.swift`, `Lumi/Core/Render/LayerRenderer.swift`, `LumiTests/LayerTests.swift`.

### T22: Text styles (M)
- **What:** speech bubbles, art-text presets, highlighter style, warped text, template texts, and **text behind the subject** (uses the foreground mask).
- **Acceptance criteria:**
  - Text-behind-subject correctly hides behind the person.
  - Presets apply in one tap.
- **Verify:** build.
- **Deps:** T21, T11.
- **Files:** `Lumi/Features/Text/TextStylePresets.swift`, `Lumi/Features/Text/TextBehindSubject.swift`, `Lumi/Resources/TextStyles/`.

### T23: Stickers (M)
- **What:** a browser with categories, albums, search, recents and favorites. Each sticker can be transformed, faded, flipped, blended, outlined and partly erased. Up to 25 per image.
- **Acceptance criteria:**
  - All sticker operations round-trip through the document.
  - The outline follows the sticker's alpha edge.
- **Verify:** build.
- **Deps:** T21.
- **Files:** `Lumi/Features/Stickers/StickerBrowserView.swift`, `Lumi/Features/Stickers/StickerStore.swift`, `Lumi/Core/Render/OutlineOps.swift`.

### T24: Custom stickers (S)
- **Acceptance criteria:**
  - Make a sticker from the tapped subject (Vision subject mask) or a brushed region.
  - Custom stickers appear under "My stickers" and persist.
- **Verify:** build.
- **Deps:** T23, T10, T11.
- **Files:** `Lumi/Features/Stickers/CustomStickerFlow.swift`, `Lumi/Features/Stickers/StickerStore.swift`.

### T25: Frames, doodle and marker (M)
- **Acceptance criteria:**
  - Inner, outer, simple and poster frames with adjustable padding.
  - Doodle brushes with materials (patterns, neon, dashed), size and opacity, plus a smart straight-line brush.
  - A marker pen.
- **Verify:** build.
- **Deps:** T10, T21.
- **Files:** `Lumi/Features/Frames/FramesView.swift`, `Lumi/Features/Doodle/DoodleView.swift`, `Lumi/Features/Doodle/BrushMaterials.swift`.

### T26: Mosaic and face cover (M)
- **What:**
  - Mosaic styles (pixel, blur, pattern), applied by brush or box.
  - Auto face mosaic.
  - Chat-screenshot auto mosaic: detects avatars and names using face and text regions.
  - Portrait protection (the mosaic skips the subject).
  - One-tap face cover with stickers.
- **Acceptance criteria:**
  - Auto mode covers every detected face.
  - Chat-screenshot mode covers avatars and names in a sample screenshot.
- **Verify:** build; tests for the region-selection heuristic.
- **Deps:** T10, T11, T23.
- **Files:** `Lumi/Features/Mosaic/MosaicView.swift`, `Lumi/Features/Mosaic/AutoMosaic.swift`, `LumiTests/AutoMosaicTests.swift`.

### T27: Watermarks (S)
- **Acceptance criteria:**
  - A personal text or image watermark, saved for reuse.
  - Three time-stamp styles.
  - A full-screen tiled watermark.
- **Verify:** build.
- **Deps:** T21.
- **Files:** `Lumi/Features/Watermark/WatermarkView.swift`, `Lumi/Features/Watermark/WatermarkStore.swift`.

### T28: Content: stickers, fonts, frames, brush materials (M, content)
- **What:** a starter set of stickers, fonts, frames and brush materials, including **Japanese-capable OFL fonts** for the text tool. Entries go into the credits system created in T01, following the policy in plan.md → *Content and credits*, summarized below.
- **Allowed licenses:**
  - Self-made.
  - CC0 / public domain.
  - **CC-BY** (any version).
  - OFL for fonts.
  - MIT, BSD or Apache-2.0 for code and models.
  - Other free licenses that explicitly allow commercial use and redistribution inside an app (the license text is saved with the entry).
- **Allowed only unmodified:** CC-BY-SA and CC-BY-ND.
- **Not allowed:** NC (non-commercial), "personal use only", unknown or unclear license, licensed IP or trademarks.
- **Credits format:** `Lumi/Resources/Credits.json`, one entry per asset or asset group, with:
  - Files covered, title, author, source URL.
  - License name and license URL.
  - The exact attribution text the license requires.
  - Whether it was modified, and how.
  - Date added.
  - The NOTICE text for Apache-2.0 items.
- **Acceptance criteria:**
  - **Coverage test:** every file under `Lumi/Resources/` (stickers, fonts, frames, filters, makeup, backgrounds, sounds, AR effects, models) is covered by a credits entry. Self-made assets get an entry too, marked self-made.
  - **Completeness test:** every entry has all required fields and a license on the allow-list.
  - No licensed IP.
- **Verify:** build; a test checks every bundled asset has a ledger entry.
- **Deps:** T23, T25.
- **Files:** `Lumi/Resources/Stickers/`, `Lumi/Resources/Fonts/`, `Lumi/Resources/Frames/`, `Lumi/Resources/Credits.json`, `LumiTests/CreditsTests.swift`.

### Checkpoint 3
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: a photo with text, stickers, frame, mosaic and watermark exports correctly.
- [ ] Human review.

---

## Phase 4: Remover, cutout, expand

### T29: Remover v1, brush and box (M, device)
- **What:** LaMa inpaint using the crop/tile strategy from T03, with a restore brush, progress display and cancel.
- **Acceptance criteria:**
  - Removing an object from a 12 MP photo stays within the latency budget set in T03.
  - There is no visible seam at the crop border.
- **Verify:** build; tile-math tests; device run.
- **Deps:** T03, T10.
- **Files:** `Lumi/Features/Remover/RemoverView.swift`, `Lumi/Features/Remover/RemoverModel.swift`, `Lumi/Core/ML/Inpainter.swift`, `LumiTests/TileTests.swift`.

### T30: Remover auto chips (M)
- **What:** chips for People (person instance masks), Text (text regions) and Auto (both). Tapping a detected item toggles it.
- **Acceptance criteria:**
  - People removal removes the chosen passers-by and leaves the main subject.
- **Verify:** build.
- **Deps:** T29, T11.
- **Files:** `Lumi/Features/Remover/AutoDetectChips.swift`, `Lumi/Features/Remover/RemoverModel.swift`.

### T31: Clone tab and specialty removers (M)
- **What:**
  - Clone-stamp repair.
  - Fast spot heal.
  - Guided brushes for glare, lens flare, tattoos and moiré, all using LaMa.
  - Noise reduction (Core Image).
  - Glasses-glare and clothing-wrinkle fixes (brush plus smoothing).
- **Acceptance criteria:**
  - The clone source offset is adjustable.
  - Each specialty brush has a preset strength.
- **Verify:** build.
- **Deps:** T29.
- **Files:** `Lumi/Features/Remover/CloneTool.swift`, `Lumi/Features/Remover/SpecialtyBrushes.swift`.

### T32: Cutout and background (M)
- **What:**
  - Tap a subject to cut it out (foreground instance mask), then refine with a precise brush.
  - Export as transparent PNG.
  - Change the background: colors, a bundled library, or your own image.
  - Background blur.
  - Save the cutout as a sticker.
- **Acceptance criteria:**
  - Cutout plus a new background exports correctly.
  - The PNG has true alpha.
- **Verify:** build.
- **Deps:** T10, T11.
- **Files:** `Lumi/Features/Cutout/CutoutView.swift`, `Lumi/Features/Cutout/CutoutModel.swift`, `Lumi/Resources/Backgrounds/`.

### T33: Batch cutout (S)
- **Acceptance criteria:**
  - Pick up to 30 photos; each is cut out and exported as PNG or with a chosen background.
  - Progress is shown and the batch can be cancelled.
- **Verify:** build.
- **Deps:** T32.
- **Files:** `Lumi/Features/Cutout/BatchCutoutView.swift`.

### T34: AI Expand (M, device)
- **What:** LaMa outpainting in proportional or free mode, iterating over tiles for large expansions, with an expansion history.
- **Acceptance criteria:**
  - Expanding a portrait to 4:3 fills the sides plausibly.
  - Previous expansions can be re-picked.
- **Verify:** build; device run.
- **Deps:** T29, T14.
- **Files:** `Lumi/Features/Expand/ExpandView.swift`, `Lumi/Features/Expand/ExpandModel.swift`.

### Checkpoint 4
- [ ] Xcode Cloud green on `main`.
- [ ] Device check on an iPhone 11-class phone and a 15 Pro: remove people, cut out a subject, expand a photo.
- [ ] Human review.

---

## Phase 5: Face retouch

### T35: Skin smoothing and texture (M)
- **What:** frequency-separation smoothing with textured and natural modes; whole-body smoothing via the person mask; brush and eraser; skin-texture options.
- **Acceptance criteria:**
  - Pores and texture are kept at moderate strength.
  - Smoothing is confined to skin.
- **Verify:** build; tests for skin-mask construction.
- **Deps:** T11, T10.
- **Files:** `Lumi/Features/Retouch/Skin/SmoothView.swift`, `Lumi/Core/Render/SkinOps.swift`, `Lumi/Core/Analysis/SkinMask.swift`, `LumiTests/SkinMaskTests.swift`.

### T36: Skin tone (M)
- **Acceptance criteria:**
  - Whitening and tone presets, a custom picker and a palette (from T16).
  - Unify skin tone across the whole body.
  - Matte (de-shine) and highlight.
  - Per-face values.
- **Verify:** build.
- **Deps:** T35, T16, T12.
- **Files:** `Lumi/Features/Retouch/Skin/ToneView.swift`, `Lumi/Core/Render/SkinOps.swift`.

### T37: Blemishes (M)
- **Acceptance criteria:**
  - Auto acne/spot detection with tap-to-heal.
  - Concealer brush.
  - Redness removal.
  - Makeup fix (smooths cakey texture).
  - Body blemish and body-hair brushes.
- **Verify:** build; spot-detector tests.
- **Deps:** T35, T29.
- **Files:** `Lumi/Features/Retouch/Skin/BlemishView.swift`, `Lumi/Core/Analysis/SpotDetector.swift`, `LumiTests/SpotDetectorTests.swift`.

### T38: Under-eye and wrinkles (M)
- **Acceptance criteria:**
  - Dark circles, eye bags, tear troughs, smile lines and eye wrinkles are fixed in regions built from landmarks.
  - One-tap "firm".
  - Multi-face sync.
- **Verify:** build; region-geometry tests.
- **Deps:** T35.
- **Files:** `Lumi/Features/Retouch/Skin/UnderEyeView.swift`, `Lumi/Core/Analysis/FaceRegions.swift`, `LumiTests/FaceRegionTests.swift`.

### T39: Face-shape warps (M)
- **What:** double chin, pointed chin, V-face, jaw angle and jawline, face width, cheekbones, cheeks, forehead, temples, hairline, contour smoothing, and presets per face shape (round, square, long, short).
- **Acceptance criteria:**
  - Each slider is a landmark-driven displacement rule.
  - Background protection is off here (see T56).
- **Verify:** build; tests for the displacement rules.
- **Deps:** T05, T11.
- **Files:** `Lumi/Features/Retouch/Reshape/FaceShapeRules.swift`, `Lumi/Features/Retouch/Reshape/ReshapeView.swift`, `LumiTests/FaceShapeRuleTests.swift`.

### T40: Ratio, 3D and protection (M)
- **Acceptance criteria:**
  - Face position and rotation, symmetry, uneven-face fix.
  - Shading-based 3D contour.
  - Feature protection and glasses lock (warp exclusion zones).
- **Verify:** build.
- **Deps:** T39.
- **Files:** `Lumi/Features/Retouch/Reshape/RatioRules.swift`, `Lumi/Features/Retouch/Reshape/ProtectionZones.swift`.

### T41: Eye, nose, mouth and brow warps (M)
- **Acceptance criteria:**
  - **Eyes:** size, distance, height, tilt, inner/outer corners, socket, lids.
  - **Nose:** slim, wings, bridge, tip, length.
  - **Mouth:** shape, fullness, smile corners, cupid's bow, protrusion, pout.
  - **Brows:** height, spacing, peak, lift.
- **Verify:** build; rule tests.
- **Deps:** T39.
- **Files:** `Lumi/Features/Retouch/Reshape/FeatureRules.swift`, `LumiTests/FeatureRuleTests.swift`.

### T42: Eye detail and teeth (M; split when reached)
- **Acceptance criteria:**
  - Eye brightening, whites, catchlight, gaze nudge, contact-lens recolor, pupil size, eye smile.
  - Teeth whitening and stain removal.
  - Straightening (light warp).
  - Braces removal (LaMa).
- **Verify:** build.
- **Deps:** T41, T29.
- **Files:** `Lumi/Features/Retouch/Eyes/EyeDetailView.swift`, `Lumi/Features/Retouch/Teeth/TeethView.swift`, `Lumi/Core/Analysis/IrisMask.swift`.

### T43: Manual face slim and volume (S)
- **Acceptance criteria:**
  - A push-liquify brush on the face (reuses T05).
  - Face volume and lift sliders.
- **Verify:** build.
- **Deps:** T05, T39.
- **Files:** `Lumi/Features/Retouch/Reshape/ManualSlimView.swift`, `Lumi/Features/Retouch/Reshape/VolumeRules.swift`.

### T44: Auto beauty (M)
- **What:** preset packs (natural, firm, younger, bold, bare, men's, and so on) that bundle parameters. Intensity control; apply to several faces or per face. "Personalized" remembers the user's last tweaks.
- **Acceptance criteria:**
  - A preset applies in one tap.
  - Adjusting after a preset keeps the custom values.
- **Verify:** build; preset-merge tests.
- **Deps:** T36–T43.
- **Files:** `Lumi/Features/Retouch/AutoBeauty/AutoBeautyView.swift`, `Lumi/Features/Retouch/AutoBeauty/BeautyPresets.swift`, `LumiTests/BeautyPresetTests.swift`.

### Checkpoint 5
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: retouch a group photo with per-face settings; export at full resolution.
- [ ] Human review.

---

## Phase 6: Makeup and hair

### T45: Makeup engine: lips, blush, contour (M)
- **Acceptance criteria:**
  - Landmark-aligned color and texture overlays with blend modes.
  - Lipstick color, finish (matte/gloss/satin) and ombré.
  - Blush with independent style and color.
  - Contour and highlight; foundation.
- **Verify:** build; tests for overlay-placement geometry.
- **Deps:** T11, T35.
- **Files:** `Lumi/Core/Render/MakeupRenderer.swift`, `Lumi/Features/Makeup/LipsView.swift`, `Lumi/Features/Makeup/FaceMakeupView.swift`, `LumiTests/MakeupPlacementTests.swift`.

### T46: Eye makeup and brows (M)
- **Acceptance criteria:**
  - Eyeshadow, eyeliner and lashes, with separate left and right.
  - Brow shape swap and brow color.
- **Verify:** build.
- **Deps:** T45.
- **Files:** `Lumi/Features/Makeup/EyeMakeupView.swift`, `Lumi/Features/Makeup/BrowView.swift`.

### T47: Makeup content, looks, recreate (M, content)
- **Acceptance criteria:**
  - Self-made textures for lashes, liner, brows and blush shapes.
  - About 20 full looks.
  - "Recreate from reference" samples lip, blush and shadow colors from a reference face.
  - Every asset is in the license ledger.
- **Verify:** build; color-sampling tests.
- **Deps:** T46.
- **Files:** `Lumi/Resources/Makeup/`, `Lumi/Features/Makeup/LooksView.swift`, `Lumi/Features/Makeup/RecreateLook.swift`, `LumiTests/RecreateLookTests.swift`.

### T48: Nail try-on (M, device)
- **Acceptance criteria:**
  - Hand pose gives fingertip regions; nail-shaped color overlays render on them.
  - Works on a clear hand photo.
  - Fails gracefully when no hand is found.
- **Verify:** build; device run.
- **Deps:** T11, T45.
- **Files:** `Lumi/Features/Makeup/NailsView.swift`, `Lumi/Core/Analysis/NailRegions.swift`.

### T49: Hair color (M)
- **Acceptance criteria:**
  - Dye uses the hair mask from T06 and keeps the hair's luminance texture.
  - Color categories.
  - Manual dye brush.
  - Root retouch.
  - Shine and smooth.
  - Hair de-oil (reduce greasy specular highlights inside the hair mask).
- **Verify:** build.
- **Deps:** T06, T10.
- **Files:** `Lumi/Features/Hair/HairColorView.swift`, `Lumi/Core/Render/HairOps.swift`.

### T50: Hair shape (M)
- **Acceptance criteria:**
  - Hairline warp.
  - Volume and fluff (crown warp outward).
  - Fill for parting and thin spots (texture clone or LaMa inside the hair mask).
  - Flyaway cleanup.
  - Hair glow effect.
- **Verify:** build.
- **Deps:** T49, T05, T29.
- **Files:** `Lumi/Features/Hair/HairShapeView.swift`, `Lumi/Features/Hair/HairShapeRules.swift`.

### Checkpoint 6
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: full makeup look plus hair dye on 5 varied photos.
- [ ] Human review.

---

## Phase 7: Body

### T51: Lower-body and torso warps (M)
- **What:** height via a band stretch, long legs, straight legs, thighs, calves, waist, belly, hips, bust and back. Driven by pose plus mask, per person.
- **Acceptance criteria:**
  - Each slider is a pose-driven rule.
  - Bust and hips are estimated from shoulder and hip joints plus the mask contour; this lower precision is documented.
- **Verify:** build; rule tests.
- **Deps:** T05, T11, T12.
- **Files:** `Lumi/Features/Body/BodyRules.swift`, `Lumi/Features/Body/BodyView.swift`, `LumiTests/BodyRuleTests.swift`.

### T52: Upper body, presets, auto (M)
- **Acceptance criteria:**
  - Neck, shoulders (square, width, uneven), traps, arms, head-to-shoulder ratio, smaller head.
  - Body-type presets.
  - One-tap auto body (sets sliders from measured proportions).
  - Muscle definition (local contrast in a brushed area).
- **Verify:** build; tests for the auto-proportion logic.
- **Deps:** T51.
- **Files:** `Lumi/Features/Body/UpperBodyRules.swift`, `Lumi/Features/Body/AutoBody.swift`, `LumiTests/AutoBodyTests.swift`.

### T53: Manual body brushes (S)
- **Acceptance criteria:**
  - Slim, Zoom and Distortion brushes (from T05) work on the body, with undo.
- **Verify:** build.
- **Deps:** T05.
- **Files:** `Lumi/Features/Body/ManualBodyView.swift`.

### T54: Background protection (M, device)
- **What:** the warp is limited to the person mask plus a soft edge, and LaMa fills the uncovered background strip. A manual protect brush is available.
- **Acceptance criteria:**
  - Slimming next to a door frame keeps the frame straight.
  - There is no visible seam in the fill.
- **Verify:** build; device run.
- **Deps:** T51, T29, T10.
- **Files:** `Lumi/Core/Render/ProtectedWarp.swift`, `Lumi/Features/Body/BackgroundProtection.swift`.

### Checkpoint 7
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: per-person body edit in a group photo with background protection.
- [ ] Human review.

---

## Phase 8: Recipes, batch, collage, materials

### T55: Recipes (M)
- **Acceptance criteria:**
  - Save a full edit stack or part of it (beauty, body, filter, collage) as a recipe and apply it to another photo.
  - Manage recipes: rename, delete, favorite, recent 50, search.
  - Share and import a recipe as a file.
  - A bundled set of starter recipes.
- **Verify:** build; tests for recipe apply and subset filtering.
- **Deps:** T44, T51, T17.
- **Files:** `Lumi/Core/Document/Recipe.swift`, `Lumi/Features/Recipes/RecipesView.swift`, `Lumi/Features/Recipes/RecipeStore.swift`, `LumiTests/RecipeTests.swift`.

### T56: Batch edit (M)
- **Acceptance criteria:**
  - Pick N photos and apply a recipe or operations to all of them.
  - Per-photo preview and progress.
  - Batch save and export.
  - Batch enhance and cutout hooks.
- **Verify:** build.
- **Deps:** T55.
- **Files:** `Lumi/Features/Batch/BatchView.swift`, `Lumi/Features/Batch/BatchRunner.swift`, `LumiTests/BatchRunnerTests.swift`.

### T57: Collage templates (M)
- **What:** data-driven layout JSON covering grids (including a 9-grid) and shapes (heart, triangle). Slots support pan, zoom and swap; border, corner radius, background and ratio are adjustable. Ships about 100 layouts.
- **Acceptance criteria:**
  - Every bundled layout renders.
  - Swapping photos between slots works.
  - "AI collage" auto-picks a layout from the photo count and aspect ratios.
- **Verify:** build; layout-parse tests.
- **Deps:** T14.
- **Files:** `Lumi/Features/Collage/CollageView.swift`, `Lumi/Features/Collage/LayoutModel.swift`, `Lumi/Resources/Layouts/`, `LumiTests/LayoutTests.swift`.

### T58: Freeform, split, seamless collage (M)
- **Acceptance criteria:**
  - Freeform scrapbook mode.
  - Split-screen layouts.
  - Seamless/borderless mode.
  - Collage recipes (layout plus filter plus stickers).
- **Verify:** build.
- **Deps:** T57, T55.
- **Files:** `Lumi/Features/Collage/FreeformCollage.swift`, `Lumi/Features/Collage/SeamlessCollage.swift`.

### T59: Long stitch and screenshot stitch (M)
- **Acceptance criteria:**
  - Vertical or horizontal stitching.
  - Smart screenshot stitching that detects overlap with translational registration.
  - Saves the long image plus paged slices.
- **Verify:** build; overlap-detection tests.
- **Deps:** T14.
- **Files:** `Lumi/Features/Collage/StitchView.swift`, `Lumi/Features/Collage/OverlapFinder.swift`, `LumiTests/OverlapFinderTests.swift`.

### T60: Materials, templates, wallpapers (M)
- **Acceptance criteria:**
  - A material center that browses bundled stickers, filters, fonts, frames and backgrounds by category, with search, "My materials" and storage management.
  - Curated collections (in place of artist collections).
  - Seasonal packs.
  - A wallpaper maker (crop to the device ratio, preview, save).
- **Verify:** build.
- **Deps:** T18, T28.
- **Files:** `Lumi/Features/Materials/MaterialCenterView.swift`, `Lumi/Features/Materials/MaterialCatalog.swift`, `Lumi/Features/Wallpaper/WallpaperView.swift`.

### Checkpoint 8
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: save a recipe, batch-apply it to 10 photos, build a collage and a screenshot stitch.
- [ ] Human review.

---

## Phase 9: Camera

### T61: Camera core (M, device; split when reached)
- **Acceptance criteria:**
  - AVCaptureSession for photo and video.
  - Lens switch and zoom; tap to focus and expose, with lock.
  - Flash and torch, timer (3 s / 6 s), grid, burst, front mirroring, auto-save, settings.
- **Verify:** build; device run.
- **Deps:** T01.
- **Files:** `Lumi/Features/Camera/CameraView.swift`, `Lumi/Features/Camera/CameraService.swift`, `Lumi/Features/Camera/CameraSettings.swift`.

### T62: Live beauty camera (M, device)
- **Acceptance criteria:**
  - Real-time skin, face-shape, makeup and filter effects on preview frames (Renderer per frame plus smoothed analysis).
  - The captured photo matches the preview.
- **Verify:** build; device run with a frame-time budget.
- **Deps:** T61, T44, T45, T17.
- **Files:** `Lumi/Features/Camera/LivePreviewPipeline.swift`, `Lumi/Features/Camera/CameraBeautyPanel.swift`.

### T63: Camera modes (M, device; split when reached)
- **Acceptance criteria:**
  - Live Photo capture.
  - Natural / "iPhone mode" with lighting adjustment and no beauty.
  - Film camera (film looks, grain, date stamp, film album).
  - Camera watermark and text bubble.
  - Screen fill light.
  - Enhanced flash.
- **Verify:** build; device run.
- **Deps:** T62, T27.
- **Files:** `Lumi/Features/Camera/Modes/NaturalMode.swift`, `Lumi/Features/Camera/Modes/FilmMode.swift`, `Lumi/Features/Camera/Modes/LiveCapture.swift`.

### T64: AR "Cutie" mode and camera music (M, device)
- **Acceptance criteria:**
  - Face-anchored AR stickers and makeup filters (ARKit face tracking where TrueDepth exists, otherwise Vision landmarks).
  - Simple interactive effects.
  - Record video with a background track mixed in.
- **Verify:** build; device run.
- **Deps:** T62.
- **Files:** `Lumi/Features/Camera/Modes/ARMode.swift`, `Lumi/Features/Camera/CameraMusic.swift`, `Lumi/Resources/AREffects/`.

### T65: Camera extras (S, device)
- **Acceptance criteria:**
  - Subject tracking (Vision object tracking with a digital crop that follows).
  - Lens-distortion correction.
  - QR scanning (`DataScannerViewController`).
- **Verify:** build; device run.
- **Deps:** T61.
- **Files:** `Lumi/Features/Camera/SubjectTracking.swift`, `Lumi/Features/Camera/QRScanView.swift`.

### Checkpoint 9
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: every camera mode captures, and the beauty preview holds frame rate on an iPhone 11-class phone.
- [ ] Human review.

---

## Phase 10: Live Photos

### T66: Live Photo editor (M, device)
- **What:** import a Live Photo and edit it through the `PHLivePhotoEditingContext` frame processor, using the same Renderer plus per-frame smoothed analysis. Choose the cover/key frame. Save back as a Live Photo.
- **Acceptance criteria:**
  - Retouch, filter and body edits apply to every frame.
  - The result plays as a Live Photo in Photos.
  - A Live Photo duration limit is set from device measurements.
- **Verify:** build; device run.
- **Deps:** T11, T44, T51.
- **Files:** `Lumi/Features/Live/LiveEditorView.swift`, `Lumi/Features/Live/LiveFrameProcessor.swift`.

### T67: Live overlays and conversion (M)
- **Acceptance criteria:**
  - Animated stickers and text on Live Photos (up to 3 Live texts).
  - Live → GIF or video.
  - Video → Live.
  - Grab a Live Photo from a video.
  - Live slideshow.
- **Verify:** build; GIF-encoding tests.
- **Deps:** T66, T23.
- **Files:** `Lumi/Features/Live/LiveOverlays.swift`, `Lumi/Features/Live/LiveConvert.swift`, `LumiTests/GIFEncoderTests.swift`.

### T68: Live collage and batch (S)
- **Acceptance criteria:**
  - Template and seamless Live collages.
  - Batch Live retouch (apply a recipe to several Live Photos).
- **Verify:** build.
- **Deps:** T67, T57, T56.
- **Files:** `Lumi/Features/Live/LiveCollage.swift`, `Lumi/Features/Live/LiveBatch.swift`.

### Checkpoint 10
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: a retouched Live Photo plays in Photos; Live → GIF works.
- [ ] Human review.

---

## Phase 11: Video

### T69: Timeline core (M)
- **Acceptance criteria:**
  - Import clips and photos; trim, split, reorder, duplicate, delete and replace.
  - Preview with AVPlayer over an AVMutableComposition.
  - Export with resolution and FPS options.
  - Video drafts.
- **Verify:** build; timeline-model tests.
- **Deps:** T09.
- **Files:** `Lumi/Features/Video/Timeline/TimelineView.swift`, `Lumi/Features/Video/Timeline/TimelineModel.swift`, `Lumi/Features/Video/VideoExporter.swift`, `LumiTests/TimelineModelTests.swift`.

### T70: Clip operations and transitions (M)
- **Acceptance criteria:**
  - Speed, reverse and freeze frame.
  - Crop, rotate and mirror; canvas and background.
  - Transitions through a custom `AVVideoCompositing` that uses Core Image.
- **Verify:** build.
- **Deps:** T69.
- **Files:** `Lumi/Features/Video/ClipOps.swift`, `Lumi/Features/Video/Compositor.swift`, `Lumi/Features/Video/Transitions.swift`.

### T71: Per-clip color and effects (M)
- **Acceptance criteria:**
  - Filters, adjustments and effects per clip, via the compositor calling the shared Renderer.
  - Tone unify across clips.
- **Verify:** build.
- **Deps:** T70, T17.
- **Files:** `Lumi/Features/Video/ClipColorView.swift`, `Lumi/Features/Video/Compositor.swift`.

### T72: Text, stickers, keyframes (M)
- **Acceptance criteria:**
  - Timed text and sticker overlays with in/out animations.
  - Keyframes for position, scale, rotation and opacity.
- **Verify:** build; keyframe-interpolation tests.
- **Deps:** T71, T21, T23.
- **Files:** `Lumi/Features/Video/Overlays/VideoOverlayModel.swift`, `Lumi/Features/Video/Overlays/Keyframes.swift`, `LumiTests/KeyframeTests.swift`.

### T73: Overlay video, masks, tracking (M)
- **Acceptance criteria:**
  - Picture-in-picture with blend and opacity.
  - Shape masks.
  - Vision object tracking that attaches stickers, text or mosaic to a moving subject.
  - Person matting on video (per-frame person segmentation, smoothed) for background replace and blur.
- **Verify:** build.
- **Deps:** T72.
- **Files:** `Lumi/Features/Video/Overlays/PiP.swift`, `Lumi/Features/Video/Overlays/Masks.swift`, `Lumi/Features/Video/Overlays/Tracking.swift`.

### T74: Audio (M; split when reached)
- **Acceptance criteria:**
  - Import music from Files (no DRM).
  - Volume and fades.
  - Voice-over recording.
  - Extract the audio track.
  - Sound effects (CC0 or CC-BY, credited).
  - Text-to-speech voices (`AVSpeechSynthesizer` written to a buffer).
  - Beat markers.
  - Remove silent segments.
  - Basic noise reduction and voice enhancement (EQ and dynamics).
- **Verify:** build; silence-detection tests.
- **Deps:** T69.
- **Files:** `Lumi/Features/Video/Audio/AudioTrackModel.swift`, `Lumi/Features/Video/Audio/AudioView.swift`, `Lumi/Features/Video/Audio/SilenceDetector.swift`, `LumiTests/SilenceDetectorTests.swift`.

### T75: Captions and teleprompter (M, device)
- **Acceptance criteria:**
  - Auto captions with `SpeechAnalyzer`, on-device (check the API against the docs).
  - Caption editing and styling.
  - Bilingual captions through the Translation framework.
  - A teleprompter during voice-over.
- **Verify:** build; device run; SRT export tests.
- **Deps:** T72, T74.
- **Files:** `Lumi/Features/Video/Captions/CaptionService.swift`, `Lumi/Features/Video/Captions/CaptionsView.swift`, `Lumi/Features/Video/Captions/Teleprompter.swift`, `LumiTests/CaptionTests.swift`.

### T76: Video retouch (M, device)
- **Acceptance criteria:**
  - Per-frame face, skin, makeup and body retouch with temporally smoothed landmarks.
  - Per person and per segment.
  - Mask-limited background protection.
  - No visible jitter on a 10-second clip.
- **Verify:** build; device run.
- **Deps:** T71, T44, T51, T45.
- **Files:** `Lumi/Features/Video/Retouch/VideoRetouchView.swift`, `Lumi/Features/Video/Retouch/FrameAnalysisTrack.swift`.

### T77: Video quality (M; split when reached)
- **Acceptance criteria:**
  - Stabilization (homographic registration, then a smoothed crop).
  - Denoise, dehaze and night enhance.
  - Color enhance.
  - Through VideoToolbox `VTFrameProcessor` (iOS 26; check each effect's availability in the docs):
    - Frame interpolation and slow motion (frame-rate conversion).
    - Video super-resolution.
    - De-flicker and temporal denoise (temporal noise filter).
- **Verify:** build; tests for path smoothing.
- **Deps:** T71.
- **Files:** `Lumi/Features/Video/Quality/Stabilizer.swift`, `Lumi/Features/Video/Quality/QualityOps.swift`, `LumiTests/StabilizerTests.swift`.

### T78: Video and Live erase (M, device)
- **Acceptance criteria:**
  - LaMa runs per frame on a tracked mask for short clips and Live Photos, with temporal blending to cut flicker.
  - The clip length limit is set from measurements.
- **Verify:** build; device run.
- **Deps:** T29, T73, T66.
- **Files:** `Lumi/Features/Video/Erase/VideoEraser.swift`, `Lumi/Features/Video/Erase/TemporalBlend.swift`.

### T79: Video extras (M)
- **Acceptance criteria:**
  - Pick and crop a cover.
  - GIF export.
  - Video collage (≤ 20 s).
  - Video recipes (save and apply an edit stack).
  - Batch crop.
  - Cache manager.
- **Verify:** build.
- **Deps:** T71, T55, T57.
- **Files:** `Lumi/Features/Video/Extras/CoverPicker.swift`, `Lumi/Features/Video/Extras/VideoCollage.swift`, `Lumi/Features/Video/Extras/CacheManager.swift`.

### Checkpoint 11
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: a 60-second edit with clips, transitions, captions, music and retouch exports at 1080p.
- [ ] Human review.

---

## Phase 12: On-device AI

### T80: Enhancer and upscaler (M, device)
- **What:** a Core ML upscaler (candidate: Real-ESRGAN; **verify the license**), tiled. Modes: HD, Ultra HD and AI UHD. Also face super-resolution on face crops, and batch enhance.
- **Acceptance criteria:**
  - A 4× upscale of a 1 MP image completes within the budget measured on device.
  - The license is recorded in the ledger.
  - "Lossless" resize: upscale, then resample to the target size (used by T14).
- **Verify:** build; device run.
- **Deps:** T03 (tiling), T56.
- **Files:** `Lumi/Core/ML/Upscaler.swift`, `Lumi/Features/Enhance/EnhanceView.swift`, `Lumi/Resources/Credits.json`.

### T81: Old-photo restoration (M, device)
- **Acceptance criteria:**
  - Scratch and dust removal (LaMa with a brush or auto mask).
  - Enhance.
  - Colorize, using an on-device model only if a spike in this task finds one with a redistributable license; otherwise colorize is reported as dropped.
- **Verify:** build; device run.
- **Deps:** T80, T29.
- **Files:** `Lumi/Features/Enhance/RestoreView.swift`, `Lumi/Core/ML/Colorizer.swift`.

### T82: Image Playground creations (M, device, Apple Intelligence)
- **Acceptance criteria:**
  - AI art, avatars, AI stickers and emoji packs via `ImageCreator`, using a photo or sketch as the concept; sketch → image covers doodle-to-art.
  - Text-to-image.
  - A clear fallback when Apple Intelligence is unavailable.
- **Verify:** build; device run.
- **Deps:** T23, T25.
- **Files:** `Lumi/Features/AICreate/AICreateView.swift`, `Lumi/Features/AICreate/ImagePlaygroundService.swift`.

### T83: ~~AI Assistant~~ (dropped 2026-10-11)
Dropped by your decision. The ID is kept so other task numbers stay stable. Nothing depends on it.

### T84: AI text replace and AI copywriting (M)
- **Acceptance criteria:**
  - Replace text in a photo: erase the detected text region with LaMa, then render new text matching the original color and size.
  - Caption and copy suggestions in the text tool via Foundation Models, with a fallback.
- **Verify:** build.
- **Deps:** T29, T21, T11.
- **Files:** `Lumi/Features/Text/ReplaceTextFlow.swift`, `Lumi/Features/Text/CopySuggestions.swift`.

### T85: Effects and "animate photo" (M)
- **Acceptance criteria:**
  - Classic effects library (glitch, light leaks, particles, blur).
  - "AI Effects" relight looks (photo booth, LED strip, red light…) built as face/person-masked colored relighting.
  - Animate a photo: 2.5D parallax or Ken-Burns motion from the person mask (and depth if present), exported as video or Live.
- **Verify:** build.
- **Deps:** T20, T67.
- **Files:** `Lumi/Features/Effects/EffectsView.swift`, `Lumi/Features/Effects/RelightLooks.swift`, `Lumi/Features/Effects/AnimatePhoto.swift`.

### Checkpoint 12
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: on an Apple Intelligence device and a non-AI device, every AI feature works or falls back cleanly.
- [ ] Human review.

---

## Phase 13: Utilities

### T86: ID photo (M)
- **Acceptance criteria:**
  - A spec library as data (1-inch, 2-inch, passport, visa, exams…).
  - A shooting guide.
  - Background color swap via the person mask.
  - Face-aligned crop to the spec.
  - Compliance checks (face size, position, tilt).
  - A print-layout sheet.
- **Verify:** build; spec-crop math tests.
- **Deps:** T32, T14.
- **Files:** `Lumi/Features/IDPhoto/IDPhotoView.swift`, `Lumi/Features/IDPhoto/IDSpecs.swift`, `Lumi/Resources/Specs/id-specs.json`, `LumiTests/IDSpecTests.swift`.

### T87: Scanner (M)
- **Acceptance criteria:**
  - Document camera (VisionKit) and scan filters.
  - OCR text extraction with copy and share.
  - Table recognition (check the iOS 26 Vision document API).
  - Translate.
  - PDF export.
  - Recent scans.
- **Verify:** build.
- **Deps:** T01.
- **Files:** `Lumi/Features/Scanner/ScannerView.swift`, `Lumi/Features/Scanner/ScanStore.swift`, `Lumi/Features/Scanner/OCRService.swift`.

### T88: GIF and emoji maker (S)
- **Acceptance criteria:**
  - Make a GIF from photos or a video (frame rate, size, loop).
  - Make an emoji pack from cutouts.
- **Verify:** build.
- **Deps:** T67, T32.
- **Files:** `Lumi/Features/GIF/GIFMakerView.swift`.

### Checkpoint 13
- [ ] Xcode Cloud green on `main`.
- [ ] Device check: produce a passport photo sheet and a scanned PDF with OCR.
- [ ] Human review.

---

## Phase 14: App shell, polish, release

### T89: Home, Tools, search, tutorials (M)
- **Acceptance criteria:**
  - A Home grid of entry points.
  - A Tools directory.
  - Drag to reorder Home.
  - Global search over tools, recipes and materials.
  - Tutorials (TipKit plus short how-to pages).
- **Verify:** build; search-ranking tests.
- **Deps:** T55, T60, T88 (the tool catalog lists every active feature task).
- **Files:** `Lumi/Features/Home/HomeView.swift`, `Lumi/Features/Home/ToolCatalog.swift`, `Lumi/Features/Home/SearchView.swift`, `LumiTests/ToolSearchTests.swift`.

### T90: Settings and attributions (S)
- **Acceptance criteria:**
  - Clear cache; save format and location.
  - Language.
  - Appearance follows the system (dark mode).
  - Permissions page.
  - Switch app icon.
  - About.
  - **Credits screen** generated from `Lumi/Resources/Credits.json`: each entry shows title, author, license with a link, required attribution text and modifications; full license texts for OFL, Apache-2.0 and MIT.
  - A test confirms the screen lists every credits entry.
- **Verify:** build; credits-screen test.
- **Deps:** T28.
- **Files:** `Lumi/Features/Settings/SettingsView.swift`, `Lumi/Features/Settings/AttributionsView.swift`.

### T91: Widgets, Control, Shortcuts (S)
- **Acceptance criteria:**
  - A Home Screen quick-tools widget.
  - A Control Center camera control.
  - App Shortcuts (open camera, open remover).
- **Verify:** build.
- **Deps:** T61, T89.
- **Files:** `LumiWidgets/LumiWidgets.swift`, `Lumi/App/AppShortcuts.swift`, `project.yml`.

### T92: Long jobs and recent tasks (M)
- **Acceptance criteria:**
  - Long jobs (batch, video export, enhance) keep running in the background (check the iOS 26 continued-processing task API).
  - A Recent tasks list.
  - A completion notification.
- **Verify:** build.
- **Deps:** T56, T69, T80.
- **Files:** `Lumi/Core/Jobs/JobQueue.swift`, `Lumi/Features/Tasks/RecentTasksView.swift`, `LumiTests/JobQueueTests.swift`.

### T93: Localization (M)
- **Acceptance criteria:**
  - Every string is in the String Catalog.
  - **English and Japanese** complete, including tool names, filter and material names, and App Store metadata.
  - A test fails if any catalog key is missing a Japanese translation.
- **Verify:** build.
- **Deps:** T89.
- **Files:** `Lumi/Resources/Localizable.xcstrings`.

### T94: Performance, memory, accessibility (M, device)
- **Acceptance criteria:**
  - No out-of-memory crash on 48 MP photos on a 4 GB device.
  - Thermal behavior is acceptable.
  - VoiceOver labels on all controls.
  - Dynamic Type in non-canvas UI.
  - Layout checked on the smallest and largest supported iPhones.
- **Verify:** build; device run with Instruments.
- **Deps:** T93 (runs after every feature task).
- **Files:** varies; notes in `docs/perf.md`.

### T95: Release prep (M)
- **Acceptance criteria:**
  - Privacy manifest (no data collected).
  - App privacy label: "Data Not Collected".
  - A privacy policy page (free hosting, e.g. GitHub Pages).
  - A public credits page generated from `Credits.json`, matching the in-app screen.
  - AI-features disclosure.
  - App Review notes.
  - Screenshots and icon.
  - Final name chosen (replacing the codename Lumi).
  - An Xcode Cloud archive workflow uploads builds to TestFlight.
- **Verify:** archive builds; App Store Connect validation.
- **Deps:** T94.
- **Files:** `Lumi/PrivacyInfo.xcprivacy`, `website/privacy.html`, `website/credits.html`, `docs/app-review-notes.md`.

### Final checkpoint
- [ ] Every row of `meitu-research/01-feature-inventory.md` is built or explicitly excluded (see plan.md → Coverage).
- [ ] Xcode Cloud green on `main` (the full test suite).
- [ ] Device pass on an iPhone 11-class phone and a 15 Pro.
- [ ] Human approval to submit.

---

## Phase Q: Quality — makeup, face, body (top priority)

Why: the user wants these three to beat every other app. Research summary (2026-10-12): the best systems move landmarks/contours and solve one smooth, constrained deformation (rigid moving least squares, Shih et al.-style mesh energies that keep lines straight), use dense or 3D face models (Meitu 3D reshape), reshape bodies from the real outline or a fitted 3D body (Zhou et al. parametric reshaping, NeuralReshaper, Ren et al. CVPR 2022 / BR-5K), and render makeup on pixel-accurate parsing masks with brightness kept and colour changed (LAB/HCL), gloss as its own layer (LipAT, CA-GAN, patents). Lumi today uses round liquify pushes on Vision's 76 points and blend modes on landmark polygons.

Bugs already fixed on the way (2026-10-12): the warp field was mirrored vertically (every reshape landed at the mirrored height); Vision's body joints are named anatomically (`left_upLeg_joint` = hip, `left_leg_joint` = knee, `left_foot_joint` = ankle, `left_forearm_joint` = elbow) so waist/hips/legs/arms never moved; waist/hips push was 6x too strong.

Rules for this phase: every task is judged on the bench (Q0) on the device, not just by unit tests. Contact sheets are pulled to the Mac and looked at before a task is ticked.

### Q0 Quality bench and personal-use licence rules (S–M)
- A bench of photos in the app's Documents/bench (front face, turned face, glasses, beard, dark and light skin, full body front/side, arms against the body, busy straight-line backgrounds). Diagnostic tests (pattern: `FaceSliderDiagnosticsTests`, `BodySliderDiagnosticsTests`) render every slider at ±0.5/±1 with landmarks, joints and stroke/control points drawn, and write contact sheets; they run only when the bench is present.
- Optional reference: the user's exports from Meitu for the same photos, shown side by side.
- Credits: keep crediting everything, but allow research / non-commercial / OpenRAIL licences with a `personalUseOnly` flag (update `Credits.allowedLicenses` and its tests).
- Accept: one command produces the sheets for every face, body and makeup control.

### Q1 Constrained mesh-warp engine (M)
- New API: an edit is a set of control-point moves (from → to) plus pinned points, not round brushes. Solve rigid moving least squares on a grid (CPU, ~100x140 nodes), then add a small energy pass that keeps straight background lines straight and weights the person/face region (person mask from BiRefNet Lite). Output stays a `DisplacementField` so the existing GPU kernel, protect-background and fill work unchanged.
- Keep the old brush path for Liquify only.
- Accept: unit tests for MLS (points land on targets, rigid regions keep shape, far field ≈ 0), a straight wall line stays straight within 1 px on the bench, solve < 30 ms on A17 for a preview grid.

### Q2 Face reshape on the new engine (M)
- Every face slider (Face, Eyes, Nose, Mouth, Brows, Ratio) becomes target positions for landmarks with the rest pinned (eyes/mouth pinned when "protect features"); jaw/V shape move the contour along its normals; eye size scales the eye outline about its centre; glasses lock pins the frame band.
- Accept: on the bench, jaw/V/chin/width visibly change only the outline; no bulging of eyes/lips; the outline overlay matches the result.

### Q3 Body reshape on the new engine (M)
- Outline from the person mask; split into parts by the skeleton (torso, each arm, each leg); each slider moves that part's contour toward its bone (waist = torso contour between ribs and hips; arms handled separately so a hanging arm is not squeezed into the waist). Background pinned; vacated strip filled (LaMa/SD).
- Uses Vision 3D body pose (`VNDetectHumanBodyPose3DRequest`) to tell front from side views.
- Accept: on the bench, waist/hips/legs/arms slim the part only, walls and door frames stay straight, side views work.

### Q4 Makeup on face parsing (M)
- Masks from the bundled BiSeNet face parsing (lips upper/lower, skin, brows, eyes, hair, glasses classes) run per face window and refined with the landmarks; teeth, glasses and hair excluded automatically.
- Colour: change chroma in LAB, keep the photo's brightness and creases; finishes (matte, satin, gloss, shimmer) as separate highlight layers following the lip's own light; strength adapts to skin tone; foundation/blush/contour/highlight on the skin class with soft falloff.
- Accept: lip colour stays inside the lips at the corners and never covers teeth; colour is visible on dark and light skin; bench sheets per look.

### Q5 Dense face landmarks (M)
- MediaPipe Face Landmarker (478 points incl. irises); convert to Core ML or run TFLite (size and licence no longer matter). Feeds Q2 and Q4 with a tighter jaw, lips and eyelids; falls back to Vision.

### Q6 3D body shape fit (L, split when reached)
- Fit SMPL-X (research licence is fine here) from joints + mask; "weight", "muscle", "height" sliders change the 3D shape and transfer the 2D change into Q1 control points (Zhou et al. 2010 approach).

### Q7 Learned body-reshape flow (M)
- Ren et al. CVPR 2022 model trained on BR-5K (non-commercial, fine here) converted to Core ML; offered as an alternative "AI slim" and compared with Q3 on the bench.

### Q8 Makeup transfer from a reference photo (M)
- EleGANt or BeautyREC (~1 M params) on Core ML: copy a look from any photo, then edit per region with Q4 controls.

### Q9 3D face fit for turned heads (M)
- 3DDFA-V2-class model; Q2 edits are applied in 3D and projected, so a three-quarter face slims correctly.

### Reconsidered because Lumi is not released
- Licences: NC/research models allowed (Q0 rule); SMPL-X, BR-5K weights, EleGANt become options.
- Size: no budget. The Stable Diffusion fill can be bundled instead of an in-app download (user to decide).
- One device: tune for A17 / 8 GB; old-iPhone fallbacks and latency budgets for 4 GB devices are not needed.
- Release work (Phase 14 store/submission, public credits page, privacy manifest polish) can be dropped or deferred indefinitely.

