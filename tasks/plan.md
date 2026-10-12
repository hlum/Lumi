# Implementation plan: Lumi (codename)

## Overview
Lumi is a **free iOS app** that recreates the editing and creation features of Meitu Xiuxiu (美图秀秀). The feature source is `../../meitu-research/01-feature-inventory.md`.

**Scope:**
- Photo editing, portrait and body retouch, makeup and hair, the object remover, cutout, collage, camera, Live Photos, a video editor, on-device AI and utilities.
- No login, accounts, subscriptions, pricing, ads or backend.
- Everything runs on the phone. The only spend is the existing Apple Developer membership.
- One App Store release when everything is done.

The task list is in `tasks/todo.md`: 95 task IDs (94 active, T83 dropped) in 15 build phases, preceded by a design phase. Every phase ends in a review checkpoint. **Nothing is built until the designs are approved (Checkpoint D).**

## Decisions this plan builds on (from the research README)
| Decision | Effect on the plan |
|---|---|
| Free, no login or subscriptions | No account, IAP or ad code. Account-dependent Meitu features are excluded (§M) |
| Remover = on-device **LaMa** (Core ML) | LaMa is also reused for AI Expand, background protection, braces and hair fill, text replace, and video erase |
| No prompt erase | No natural-language erase anywhere in the app |
| On-device AI where possible | Apple Image Playground, Foundation Models, Vision, Speech, Translation and small Core ML models. AI group photo, AI photoshoot and photoreal AI edit are dropped |
| Minimum **iOS 26** | Swift-native Vision API, SpeechAnalyzer, Foundation Models, Liquid Glass. AI features light up only on Apple Intelligence devices, with a fallback elsewhere |
| One release at the end | Phases are internal milestones, each ending in a human-review checkpoint |
| Native UI first | Stock SwiftUI and system components. Custom UI only where the system can't do the job, and each case says why (e.g. the Metal canvas) |
| **Design before build** (2026-10-11) | Phase D precedes T01; Checkpoint D (designs approved) blocks all build work |
| **Xcode Cloud runs the tests, set up first** (2026-10-11) | T02 sets up CI right after the scaffold, before any feature work |
| **Test-driven development** (2026-10-11) | Each task writes failing tests first, then implements. A task is done when Xcode Cloud is green. Tests aren't run locally |
| **English and Japanese** (2026-10-11) | T93 localizes both fully. T28 bundles Japanese-capable OFL fonts. A test catches missing Japanese strings |
| **Server-AI drops approved** (2026-10-11) | The former Open Question 1 list is now excluded (see Excluded) |
| **CC-BY and other free assets allowed, with complete credits** (2026-10-11) | Policy in *Content and credits*. `Credits.json` plus tests exist from T01; the in-app credits screen comes in T90 and a public credits page in T95 |
| **iPhone only** (2026-10-11) | `TARGETED_DEVICE_FAMILY = 1`; no iPad layout work |
| **AI Assistant dropped** (2026-10-11) | T83 is marked dropped (ID kept). Foundation Models is still used for copy suggestions in T84 |

## Architecture decisions
1. **Project:** XcodeGen `project.yml` (same as ClimaApp); the Lumi app plus LumiTests (Swift Testing); Swift 5 language mode, matching your other apps.
   - The generated `.xcodeproj` and its shared scheme are committed, so Xcode Cloud builds without installing XcodeGen.
2. **CI and TDD.**
   - The Xcode Cloud workflow "CI" runs Build and Test on every pull request and every push to `main`, on one iPhone simulator destination.
   - Tests are Swift Testing unit tests. Hardware-dependent code (camera, Core ML, Apple Intelligence) sits behind protocols with fakes, so it's testable on CI.
   - Fixtures are bundled into the test target, because Xcode Cloud runs tests without the repository present.
3. **Non-destructive editing.**
   - A photo edit is an `EditDocument`: a reference to the original plus an ordered list of Codable `EditOperation`s (parameters, masks, displacement fields, layers). Pixels are never baked until export.
   - This gives undo/redo, re-editable drafts, recipes (a recipe is a saved operation list) and batch editing almost for free.
4. **Rendering is a pure function.**
   - `Renderer.render(document, analysis, frame: CIImage) -> CIImage` on Core Image over Metal.
   - The same function serves the photo preview (at proxy resolution in an `MTKView`), full-res export, the camera preview, the Live Photo frame processor (`PHLivePhotoEditingContext`) and the video compositor (`AVVideoCompositing`).
   - Live, video and camera therefore reuse every photo tool instead of reimplementing it.
5. **Analysis is a shared, cached service.**
   - Vision provides face landmarks, body pose, person instance masks, subject masks and text regions; the hair model comes from spike T06.
   - Results are computed once per image. Per-frame calls go through a temporal-smoothing hook (a One-Euro filter) for video, Live and camera.
6. **Warp engine.**
   - One Metal mesh-warp with a displacement field drives every reshape tool: face, features and body.
   - Each slider is a small landmark- or pose-driven displacement rule; the manual brushes are pinch, bloat and push.
   - Background protection limits the warp to the person mask, and LaMa fills the strip it uncovers.
7. **Shared brush and mask infrastructure (T10).** Built once and used by partial adjust, filter eraser, mosaic, remover, skin brushes, liquify and background protection.
8. **ML models.**
   - Models are bundled in the app at first. LaMa is about 190 MB, which is allowed.
   - If total model weight grows, moving them to Apple-hosted downloadable asset packs before release gets its own task. That mechanism isn't assumed here.
   - Every model license is verified inside a task and recorded in `Lumi/Resources/Credits.json`.
9. **Content and credits.** See the section below.
10. **Persistence:** SwiftData `Project` records for drafts, plus files on disk for originals and masks. No network.

## Content and credits
The goal is that **nothing ships without its required credit**.

**Allowed:**
- Self-made.
- CC0 / public domain.
- **CC-BY** (any version).
- OFL (fonts).
- MIT, BSD or Apache-2.0 (code and models).
- Other free licenses that explicitly allow commercial use and redistribution inside an app. The license text is saved with the entry.

**Allowed only unmodified:** CC-BY-SA, CC-BY-ND.

**Not allowed:** NC (non-commercial), "personal use only", unknown or unclear licenses, licensed IP or trademarks (no Disney, Sanrio and so on).

**Single source of truth:** `Lumi/Resources/Credits.json`, bundled in the app. Each entry records:
- Files covered, title, author, source URL.
- License name and license URL.
- The exact attribution text the license requires.
- Modified (yes/no, and what changed).
- Date added.
- NOTICE text for Apache-2.0 items.

Self-made assets also get an entry, marked self-made, so coverage can be checked mechanically.

**Enforced by tests from the first commit (T01):**
- **Coverage:** every file under `Lumi/Resources/` is covered by an entry.
- **Completeness:** every entry has all fields, and its license is on the allow-list.
- **Screen (T90):** the in-app Credits screen lists every entry.

Any task that adds an asset, font, model, sound or third-party code adds its entry in the same task. Otherwise Xcode Cloud goes red.

**Shown in two places:**
- In-app Settings → Credits (T90), with full license texts for OFL, Apache-2.0 and MIT.
- A public credits page on the website (T95).

## Folder layout
```
Lumi/
├── project.yml
├── Lumi.xcodeproj         generated by XcodeGen, committed for Xcode Cloud
├── Lumi.xctestplan
├── ci_scripts/              only if Xcode Cloud needs a step (BunnyBank pattern)
├── Lumi/
│   ├── App/                 LumiApp, RootTabView, AppShortcuts
│   ├── Core/
│   │   ├── Document/        EditDocument, EditOperation, Layer, Project, Recipe, UndoStack, ExportSettings, PersonTarget
│   │   ├── Render/          Renderer, MetalPreviewView, MeshWarp, ProtectedWarp, Kernels.metal, LUT, *Ops
│   │   ├── Analysis/        Analyzer, AnalysisCache, Smoothing, SkinMask, FaceRegions, IrisMask, SpotDetector, NailRegions
│   │   ├── Mask/            MaskCanvas, BrushEngine, MaskStore
│   │   ├── ML/              Inpainter (LaMa), HairSegmenter, Upscaler, Colorizer
│   │   └── Jobs/            JobQueue
│   ├── Features/<Feature>/  View + @Observable model per feature (Editor, Crop, Adjust, Filters, Text, Stickers, Remover, Cutout, Expand, Retouch/…, Makeup, Hair, Body, Recipes, Batch, Collage, Camera, Live, Video/…, Enhance, AICreate, Assistant, Effects, IDPhoto, Scanner, GIF, Home, Settings, Projects, Materials, Wallpaper, Watermark, Mosaic, Doodle, Frames, Canvas, Resize, Relight, Tasks)
│   ├── Shared/              ColorPickerPanel and other reusable components
│   └── Resources/           Credits.json (credits source of truth), Filters/, Stickers/, Fonts/, Frames/, Layouts/, Makeup/, Backgrounds/, TextStyles/, AREffects/, Sounds/, Specs/, Models/, Localizable.xcstrings
├── LumiWidgets/
├── LumiTests/               Swift Testing; Fixtures/ bundled for Xcode Cloud
├── docs/                    spikes/*.md, ci.md, perf.md, app-review-notes.md
├── website/                 privacy.html, credits.html
└── tasks/                   plan.md, todo.md
```

## Dependency graph (main spine)
```
Checkpoint D (designs approved)
T01 scaffold ─ T02 Xcode Cloud CI
 ├─ T03 LaMa spike ───────────────┐
 ├─ T04 preview spike ─ T05 warp  │
 └─ T06 hair spike                │
T07 edit pipeline (Renderer) ─ T08 undo ─ T09 drafts
 ├─ T10 brush/mask ──────────┬──────────────────────────┐
 └─ T11 analysis ─ T12 picker│                          │
     │                       │                          │
     ├─ color/filters T13–T20 (T17 needs T10)           │
     ├─ overlays T21–T28                                │
     ├─ remover/cutout/expand T29–T34 (needs T03, T10) ◄┘
     ├─ face retouch T35–T44 (needs T05 warp, T11)
     ├─ makeup/hair T45–T50 (hair needs T06)
     ├─ body T51–T54 (background protection needs T29)
     ├─ recipes/batch/collage/materials T55–T60
     ├─ camera T61–T65 (beauty camera reuses Renderer)
     ├─ Live T66–T68 (frame processor reuses Renderer)
     ├─ video T69–T79 (compositor reuses Renderer)
     ├─ on-device AI T80–T85
     └─ utilities T86–T88
 shell/polish/release T89–T95
```

## Task list (index; details in todo.md)
| Phase | Tasks | Milestone at its checkpoint |
|---|---|---|
| **Q Quality (top priority)** | Q0–Q9 | Makeup, face and body beat other apps on the bench; Lumi is personal-use only (not released) |
| D Design | (defined in the design session) | Designs approved; nothing is built before this |
| 0 Scaffold, CI and spikes | T01–T06 | CI green; go/no-go on LaMa, preview, warp and hair model |
| 1 Editing foundation | T07–T12 | Import → edit → save → reopen → undo |
| 2 Basic edit and color | T13–T20 | Crop, adjust and filters smooth on 48 MP |
| 3 Overlays | T21–T28 | Text, stickers, frames, mosaic, watermark |
| 4 Remover, cutout, expand | T29–T34 | LaMa features on old and new iPhones |
| 5 Face retouch | T35–T44 | Per-face group retouch |
| 6 Makeup and hair | T45–T50 | Full looks plus hair dye |
| 7 Body | T51–T54 | Per-person body edit with background protection |
| 8 Recipes, batch, collage, materials | T55–T60 | Recipe → batch, collage, stitch |
| 9 Camera | T61–T65 | All camera modes; beauty preview holds frame rate |
| 10 Live Photos | T66–T68 | Retouched Live Photo plays in Photos |
| 11 Video | T69–T79 | 60-second edit exports at 1080p |
| 12 On-device AI | T80–T85 | AI features work or fall back cleanly |
| 13 Utilities | T86–T88 | ID photo sheet, scanned PDF |
| 14 Shell, polish, release | T89–T95 | Submission-ready |

Verification (details at the top of todo.md):
- **Test-first:** write failing tests for the acceptance criteria, then implement.
- **Build locally:** compile only; tests aren't run locally.
- **Done:** a task is done when its Xcode Cloud run is green.
- **Device checks:** only where a task says so.

## Risks and mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| LaMa too slow or memory-heavy on 4 GB iPhones | High | Spike T03 first: crop/tile around the mask, process at 512 px and blend back; set a latency budget; go/no-go at Checkpoint 0 |
| No usable, redistributable hair-segmentation model | High (6 hair features) | Spike T06; fallback heuristic mask plus brush; re-scope hair at Checkpoint 0 |
| Real-time preview on 48 MP | High | Spike T04: proxy-resolution preview, full-res only at export |
| Warp quality (seams, background bending) | High | Spike T05; background protection with LaMa fill (T54) |
| Video retouch jitter | Med | Smoothing hook in T11; device checks in T76 |
| Video/Live erase flicker | Med | Short clips only; temporal blending; limit set from measurements (T78) |
| Bust and hip precision (no Vision joints there) | Med | Estimate from joints plus mask contour; documented limitation (T51) |
| Apple Intelligence missing on many devices | Med | Every AI feature has a non-AI fallback (T82, T84) |
| Content volume: filters, stickers, makeup textures, layouts | Med (time) | Explicit content tasks (T18, T28, T47, T57) and the license ledger |
| Model licenses (upscaler, colorize, hair) | Med | Verified inside each task before shipping; a feature is dropped if its license fails |
| A credit is missing or wrong (legal risk) | High | Credits coverage and completeness tests on every CI run from T01; the allow-list blocks NC and unclear licenses; credits screen test (T90); public credits page (T95) |
| App size from bundled models | Low/Med | Measure at T94; downloadable asset packs if needed |
| Xcode Cloud free compute allowance runs out | Med | One simulator destination, unit tests only, no UI tests; T02 records the current allowance; move heavy jobs to device checks |
| Scope: 95 tasks before any release | High (time) | Checkpoints every phase; human review can re-prioritize. Some M tasks (T42, T61, T63, T74, T77) are marked "split when reached" |

## Open questions
None right now. The design phase may raise new ones.

Colorize remains conditional on finding a licensable on-device model (T81). Video frame interpolation, super-res and de-flicker are included, through VideoToolbox `VTFrameProcessor` on iOS 26 (T77).

## Excluded (already decided)
- §M account- and backend-dependent features: community feed, posts, likes, comments, follows, profiles; private and group chat; MT Album, shared albums, cloud drive, cloud editing history; remote "scan to co-create" group photo; paid ID-photo orders, wallet, beauty-goods page.
- Prompt erase.
- AI group photo, AI photoshoot (including AI video from photoshoots), photoreal AI edit (pose/outfit/weather).
- AI Assistant (dropped 2026-10-11).
- **Approved 2026-10-11** (these need server-side generative AI):
  - Hairstyle/bangs swap; makeup removal; flowing-hair animation.
  - Open-mouth and wink expressions; video expression transfer.
  - AI-generated video transitions; audio separation.
  - Image-to-video, video extender, AI animation, AI dance, AI music, product-to-video.
  - AI product image, AI model try-on, AI poster/logo/note cover, design agent.
  - Outfit/hair swap in ID photos.

## Appendix: coverage of the feature inventory
Generated mechanically from every row of `meitu-research/01-feature-inventory.md`: 187 rows, 0 unmapped. Tally: 168 → tasks, 5 → excluded (decided earlier, including the AI Assistant), and 14 rows with an approved drop. Some of those 14 rows are only partly dropped.

A reverse check confirms that every specific claim in this table appears in the cited task's text in todo.md.

| § | Inventory item | Lumi task / exclusion |
|---|---|---|
| A | Home 首页 (*Home*) | T89 |
| A | Tools 工具箱 (*Tools*) | T89 |
| A | Reorder features 功能排序 | T89 |
| A | Global search | T89 |
| A | Tutorial library 教程库 | T89 |
| A | Space 空间 (*Project*) | T09 |
| A | Drafts 草稿箱 (*Drafts*) | T09 (photo), T69 (video), T66 (Live) |
| A | Recent tasks 最近任务 | T92 |
| A | Portrait manager 人像管理 | T12 |
| A | Shortcuts / widgets | T91 |
| A | Dark mode | T90 (system appearance) |
| A | Undo / redo / compare | T08 |
| B1 | Crop 裁剪 (*Crop*) | T13 |
| B1 | Rotate / flip | T13 |
| B1 | Straighten 画面矫正 (*Adjust*) | T13 |
| B1 | Resize 像素修改 (*Pixels*) | T14 (lossless AI resize via T80) |
| B1 | Canvas 画布 | T14 |
| B2 | Filters 滤镜 (*Filters*) | T17, T18 |
| B2 | Auto color fix 自动校色 (*Color Fix*) | T17 |
| B2 | Extract filter 提取滤镜 / AI filter (*AI Filters*) | T19 |
| B2 | Adjust 调色 (*Adjust*) | T15, T16 |
| B2 | Partial adjust 局部调色 (*Partial*) | T19 |
| B2 | Palette / color picker 调色盘 / 取色 | T16 |
| B2 | AI Flash (*AI Flash*) / AI补光 | T20 |
| B2 | Light and shadow 光影 (*Glow*) | T19 |
| B2 | AI color 色彩增强 (*AI Color*) / 色彩还原 | T19 |
| B2 | Tone unify 色调统一 | T19 (photo), T71 (video) |
| B3 | Auto erase 自动消除 | T30 (People/Text/Auto chips); Wrinkles and Marks via T31 brushes |
| B3 | Brush / box erase | T29 |
| B3 | ~~Prompt erase 一句话消除 (*Prompt*)~~ | EXCLUDED: prompt erase (decided) |
| B3 | Specialty removers | T31 |
| B3 | Watermark / subtitle removal | T29 brush + T30 Text chip (photo); T78 (video/Live) |
| B3 | Video / Live erase | T78 |
| B3 | Clone 复制修补 (*Repair*) | T31 |
| B4 | AI cutout 智能抠图 (*AI Cutout*) | T32; video matting T73 |
| B4 | Transparent background | T32 |
| B4 | Change background 换背景 | T32 |
| B4 | Batch cutout 批量抠图 | T33 |
| B4 | Save cutout as sticker 存为贴纸 | T32, T24 |
| B4 | Background blur 背景虚化 (*Blur*) | T32 |
| B4 | Background protection 背景保护 (*BG Lock* / *Background Protection*) | T54 (photo), T76 (video) |
| B5 | Stickers 贴纸 (*Stickers*) | T23, T28 |
| B5 | Custom stickers 自定义贴纸 | T24; AI stickers T82 |
| B5 | Live stickers / Live text | T67 |
| B5 | Text 文字 (*Text*) | T21, T22 |
| B5 | AI text replace 无痕改字 / AI改字 | T84 |
| B5 | Frames 边框 (*Frames*) | T25 |
| B5 | Doodle 涂鸦笔 (*Brushes*) | T25; AI doodle→art T82 |
| B5 | Marker 标记 (*Mark*) | T25 |
| B5 | Mosaic 马赛克 (*Mosaic*) | T26; video tracking T73 |
| B5 | Watermark 水印 | T27 |
| B5 | Face cover 一键挡脸 / 智能挡脸 (*AI Mask*) | T26 |
| B6 | Effects 特效 / 魔法照片 (*Animate*) | T85 |
| B6 | AI Effects (*AI Effects*) | T85 (approximated: masked relight looks) |
| B6 | AI Expand AI扩图 (*AI Expand*) | T34 |
| B6 | AI Edit AI改图 | EXCLUDED: server-side generative AI (decided in the cloud-AI answer) (photoreal pose/outfit/weather edits) |
| B6 | Enhancer 画质修复 / 变清晰 (*AI Enhancer*) | T80 |
| B6 | Old photo restoration (*Photo Restoration*) / colorize (*Colorize*) | T81 (colorize conditional on a licensable model) |
| B6 | Dehaze 去雾, night view (*Night View*), denoise | T19 (dehaze, night view), T31 (denoise), T77 (video) |
| B6 | Batch edit 批量修图 (*Batch*) | T56 |
| C1 | Presets | T44 |
| C1 | Personalized AI beauty | T44 (remembers the user's parameters; no cloud model) |
| C1 | Men's mode | T44 |
| C1 | Multi-face | T12, T44 |
| C1 | Save as recipe | T55 |
| C2 | Face shape | T39 |
| C2 | Ratio | T40 |
| C2 | 3D | T40 |
| C2 | Eyes | T41 |
| C2 | Nose | T41 |
| C2 | Mouth | T41 |
| C2 | Brows | T41 (shape warp); T46 (brow shape swap/color) |
| C2 | Manual slim 手动瘦脸 (*Manual slimming*) | T43 |
| C2 | Face volume 丰盈提拉 (*Face Volume*) | T43 |
| C2 | Protection | T40 |
| C4 | Smooth 磨皮 (*Smooth*) | T35 |
| C4 | Whiten / tone (*Tone*) | T36 |
| C4 | Acne / spots | T37 |
| C4 | Redness 祛红血丝 | T37 |
| C4 | Makeup fix 底妆修复 (*Fix*) | T37 |
| C4 | Concealer pen 遮瑕笔 (*Concealer*) | T37 |
| C4 | Matte 去油光 (*Matte*) | T36 |
| C4 | Skin texture 皮肤细节 / 肤质 | T35 |
| C4 | Highlight 高光 | T36 |
| C4 | Wrinkles 祛皱 (*Firm*) | T38 |
| C4 | Body skin | T37 (body blemish/hair), T36 (body tone), T35 (body smoothing) |
| C4 | Teeth | T42 |
| C4 | Glasses | T31 (glare brush, glasses removal by remover brush); no auto glasses detection |
| C4 | Face light 面部补光 (*Fill light*) / shadow | T20 |
| C4 | Clothing wrinkles | T31 |
| C6 | Hair dye 染发 (*Hair Dye*) | T49 |
| C6 | Root retouch 发根补染 (*Root Retouch*) | T49 |
| C6 | Fill / volume | T50 |
| C6 | Hairline 发际线 (*Hairline*) | T50 |
| C6 | Fluffy / de-oil 头发蓬松 | T50 (fluff), T49 (de-oil) |
| C6 | Flyaways 去碎发 | T50 |
| C6 | Smooth / shine 发质柔顺 · 发质光泽 | T49 |
| C6 | Glow / flowing-hair effects | T50 (glow); flowing-hair animation: EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| C6 | Bangs 刘海 (*Bangs*), hairstyle 换发型 (*Style*) | EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| C7 | Auto body 一键美体 (*Auto*) | T52 |
| C7 | Legs / height | T51 |
| C7 | Torso | T51 |
| C7 | Upper body | T52 |
| C7 | Body types | T52 |
| C7 | Manual tools | T53 |
| C7 | Per-person | T51, T12 |
| C7 | Body recipes | T55 |
| C7 | Compute | n/a (note row); on-device per T51–T54 |
| C8 | Expression reshape 表情重塑 (*Expression*) / AI Expression | T41 (smile corners, pout via warp); open mouth/wink: EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| C8 | Expression transfer (video) | EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| C8 | Sticker/GIF pack 表情包 | T88, T82 |
| C8 | Face super-res 面部超清 | T80 |
| D | Modes | T63 (natural/iPhone mode, film, Live), T64 (Cutie AR) |
| D | Live beauty | T62 |
| D | Capture | T61, T63 |
| D | Light | T61 (flash/torch), T63 (screen fill light, enhanced flash) |
| D | Lens | T61 (zoom), T65 (tracking, distortion) |
| D | Music | T64 |
| D | Overlays | T63 |
| D | Settings | T61 |
| D | After capture | T61 → Editor (T07) |
| D | QR scanner | T65 |
| E | Editor | T66 |
| E | Retouch on Live | T66 |
| E | Live stickers, text, doodle ("Live涂鸦mini人") | T67 |
| E | Live collage | T68 |
| E | Batch Live retouch | T68 |
| E | Live erase / watermark removal | T78 |
| E | Convert | T67 |
| E | Limit | T66 (limit set from measurements) |
| F | Template collage (*Template*) | T57 |
| F | Freeform / scrapbook 拼贴 | T58 |
| F | Seamless (*Seamless Collage*) | T58 |
| F | Split-screen 分屏 (*Split*) | T58 |
| F | Long stitch (*PicStrip*) / screenshot stitch (*Screenshot Collage*) | T59 |
| F | Video collage 视频拼接 | T79 |
| F | Live collage | T68 |
| F | Group / flow / scene layouts, collage cutout, AI collage | T57/T58 layouts + T32 cutout; AI collage = auto-layout pick in T57 |
| F | Collage recipes | T58 |
| F | ID-photo print layout 排版照 | T86 |
| G2 | Timeline | T69, T70 |
| G2 | Overlay 画中画 (*Overlay*) | T73 |
| G2 | Keyframes | T72 |
| G2 | Masks 蒙版 (*Mask*) | T73 |
| G2 | Transitions | T70; AI-generated transitions: EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| G2 | Color | T71 |
| G2 | Effects | T71, T85 |
| G2 | Text and subtitles | T72, T75 |
| G2 | Audio | T74; audio separation: EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| G2 | Tracking | T73 |
| G2 | Quality | T77 (stabilize, denoise, dehaze, night, color; frame interpolation, super-res, de-flicker via VTFrameProcessor) |
| G2 | AI video | T85 (AI Motion ≈ animate/parallax); image-to-video, video extender, AI animation, AI dance, AI music, product-to-video: EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| G2 | Cover | T79 |
| G2 | Video recipes / same-style | T79 (local recipes; no online feed) |
| G2 | Export | T69, T79 |
| G2 | Batch | T79 |
| G2 | Drafts / cache manager | T69, T79 |
| H | **AI Agent** 美图秀秀AI助手 (*AI Agent*) | EXCLUDED: AI Assistant dropped (2026-10-11) |
| H | **AI Group Photo** AI合照 | EXCLUDED: server-side generative AI (decided in the cloud-AI answer) |
| H | **AI Photoshoot** AI写真 | EXCLUDED: server-side generative AI (decided in the cloud-AI answer) |
| H | AI Art AI绘画 (*AI Art*) | T82 |
| H | AI Portraits (*AI Portraits*) | T82 |
| H | AI Effects | T85 |
| H | Text-to-image 文生图 | T82 |
| H | AI Product Image (*AI Product Image*) | EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| H | AI Model (*AI Model*) / try-on | EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| H | AI Poster / AI Logo / AI text poster | EXCLUDED: server-side generative AI (drop approved 2026-10-11) (manual posters possible via collage/canvas/text) |
| H | AI note cover AI图文笔记 | EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| H | AI copywriting | T84 |
| H | Design agent (RoboNeo, embedded) | EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| I | Recipes 配方 (*Templates*) | T55 |
| I | Trend recipes | T55 (bundled starter recipes; no online trend feed) |
| I | Template center | T60 (bundled; no daily server updates) |
| I | Material center 素材中心 (*Elements*) | T60 |
| I | Artist collections | T60 (curated collections) |
| I | Wallpapers (*Wallpaper*) | T60 |
| I | Seasonal packs | T60 (bundled) |
| J | ID photo 证件照 (*ID Photo*) | T86 (outfit/hair swap: EXCLUDED: server-side generative AI (drop approved 2026-10-11)) |
| J | Scanner 扫描 | T87 |
| J | GIF / emoji maker | T88 |
| J | Compress / format | T14 |
| J | Upscale / magnify | T80 |
| C3 | Eyes detail (prose list) | T42 (brighten, whites, catchlight, gaze, contacts, pupil, eye smile); T38 (bags, dark circles, tear troughs, eye wrinkles) |
| C5 | Makeup (prose list) | T45 (lips, blush, contour, foundation), T46 (eyes, brows), T47 (looks, recreate-from-reference via color sampling), T48 (nails); makeup removal: EXCLUDED: server-side generative AI (drop approved 2026-10-11) |
| G1 | Video retouch (prose) | T76 |
| K | Save and share (prose) | T07 (Photos + ShareLink), T14 (format/quality), T67 (Live/GIF), T69 (video) |
| L | Settings (prose) | T90; cloud-processing consent not needed (no cloud) |
