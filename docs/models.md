# Swapping models

Every Core ML model is looked up by **slot** (what job it does), never by file name in feature code.

- `ModelSlot` (inpaint, upscale, colorize, hairSegmentation, personMatting, faceParsing) says which input and output **roles** the code uses.
- `ModelEntry` maps each role to the model's own feature name and records `side`/`scale`, version, licence and source.
- `ModelStore` knows the bundled models (`ModelEntry.bundledDefaults`) and installed ones (Application Support/Models, `installed.json`, `selection.json`).
  It picks the active model per slot; the choice survives restarts; `revision` changes whenever it does.
- Services (`LazyInpainter`, `LazyUpscaler`, `LazyColorizer`) rebuild themselves when `revision` changes, so a swap takes effect on the next use.
- Settings > AI models lists models, switches between them, resets to the built-in one and installs a new `.mlpackage`, `.mlmodel` or `.mlmodelc`
  (compiled on the device, checked for the mapped feature names).

To ship a better built-in model: put the compiled model in `Lumi/Resources/Models`, change its `ModelEntry` in `bundledDefaults` (file, feature names, side), update `scripts/fetch_models.sh` and `Credits.json`.
To add a new job (e.g. a hair segmentation model): add the slot, its roles, and read the model through `ModelStore.shared.load(slot)`.
