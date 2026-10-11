# Spike T04/T05: preview and warp

**Decided (pending device numbers):** edit on a proxy (longest side ~2048) in a Metal-backed `MTKView`; export re-renders the same `Renderer` graph at full resolution. A custom view is needed because SwiftUI `Image` can't redraw a Core Image graph at 60 fps.

**Warp:** brush strokes are the source of truth (`WarpEdit`); the displacement field is replayed from them, so undo/redo is exact and the edit serializes as JSON. Field = source-offset grid, bilinear sampled, edge-clamped.

**Still to measure on device:** frame time and memory with a 48 MP photo; GPU application of the field to a full-res image (seam/aliasing check). Not yet built: the Metal/Core Image kernel that applies the field.
