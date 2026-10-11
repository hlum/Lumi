# Spike T04/T05: preview and warp

**Decided (pending device numbers):** edit on a proxy (longest side ~2048) in a Metal-backed `MTKView`; export re-renders the same `Renderer` graph at full resolution. A custom view is needed because SwiftUI `Image` can't redraw a Core Image graph at 60 fps.

**Warp:** brush strokes are the source of truth (`WarpEdit`); the displacement field is replayed from them, so undo/redo is exact and the edit serializes as JSON. Field = source-offset grid, bilinear sampled, edge-clamped.

**Warp:** done, see the update below.

## Update: warp measured on device (A17, iPhone 15 Pro)
- Warp renders through a Core Image Metal kernel (`MeshWarpRenderer`), compiled from source at first use. The kernel needs `[[ stitchable ]]`; the library-linker route (`-fcikernel`) did not find the function.
- Edge handling: the source is `clampedToExtent`, so a warp that pulls from outside never shows transparent seams (tested).
- A 4000x3000 warp renders on A17 inside the test run. Frame-time numbers for 48 MP are still to be measured with Instruments.
- Go: the displacement-field approach is kept for every reshape tool.

## T04 measurements (iPhone 15 Pro class, A17; device test `PreviewBenchmarkTests`)
Synthetic 48 MP picture (8000x6000 with random detail), filter + adjust + vignette applied.

| What | Result |
|---|---|
| Preview frame at the 2048 px proxy (render to a 1170x1560 Metal texture) | **about 3 ms** per frame, after warm-up |
| Full-resolution export of the same picture (JPEG, quality 0.8) | **about 0.12 s** |
| Resident memory during both | **about 560-640 MB** |

**Decision (go):**
- Edit on a 2048 px proxy and re-render the whole operation list on every slider tick; at 3 ms per frame there is room for several more expensive tools before the 16 ms budget is at risk.
- Export re-renders the same operations at full resolution (`Renderer.render` is a pure function of image and document), so preview and export agree.
- A custom Metal-backed view (`MetalPreviewView`) is justified: SwiftUI `Image` can't redraw a Core Image graph on every drag tick without converting to a bitmap first.
- Numbers are for a synthetic picture on the fastest current chip. Heavier chains (face retouch, warp, upscale) are measured separately; see `docs/spikes/warp.md` and `lama.md`. A 4 GB older device is still unmeasured.
