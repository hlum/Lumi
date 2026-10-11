# Spike T04/T05: preview and warp

**Decided (pending device numbers):** edit on a proxy (longest side ~2048) in a Metal-backed `MTKView`; export re-renders the same `Renderer` graph at full resolution. A custom view is needed because SwiftUI `Image` can't redraw a Core Image graph at 60 fps.

**Warp:** brush strokes are the source of truth (`WarpEdit`); the displacement field is replayed from them, so undo/redo is exact and the edit serializes as JSON. Field = source-offset grid, bilinear sampled, edge-clamped.

**Warp:** done, see the update below.

## Update: warp measured on device (A17, iPhone 15 Pro)
- Warp renders through a Core Image Metal kernel (`MeshWarpRenderer`), compiled from source at first use. The kernel needs `[[ stitchable ]]`; the library-linker route (`-fcikernel`) did not find the function.
- Edge handling: the source is `clampedToExtent`, so a warp that pulls from outside never shows transparent seams (tested).
- A 4000x3000 warp renders on A17 inside the test run. Frame-time numbers for 48 MP are still to be measured with Instruments.
- Go: the displacement-field approach is kept for every reshape tool.
