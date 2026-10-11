# Spike T03: LaMa on device

**Go** on iPhone 15 Pro-class hardware (A17). Not yet measured on a ~4 GB iPhone 11-class device.

- **Model:** `mlboydaisuke/LaMa-CoreML` (Core ML conversion of advimman/lama). License: Apache-2.0 for both the conversion and the upstream weights (model card and `coremlcompiler metadata` both say Apache 2.0). Entry added to `Lumi/Resources/Credits.json`.
- **I/O:** `image` 800x800 RGB + `mask` 800x800 gray (1 = remove) -> `output` 800x800 RGB. Fixed size, `computeUnits = .all` as converted.
- **Size:** 187 MB download, ~209 MB on disk. GitHub rejects files over 100 MB, so the package is not in git: `scripts/fetch_models.sh` downloads it, `ci_scripts/ci_post_clone.sh` runs that on Xcode Cloud, and the folder is gitignored.
- **Measured on A17 (device test, 1200x900 photo, 160 px object):** first call 3.6 s including model load, warm call 1.2 s, resident memory about 1.0 GB in the whole test process.
- **Strategy for 12-48 MP photos:** never run the whole image. `InpaintPlan.cropRect` takes the mask's bounding box plus context (mask size x3, at least 256 px), slides the square back inside the image, scales it to 800x800, runs LaMa, scales the result back and blends it over the original through a slightly grown, feathered mask. Everything outside the mask stays bit-identical. A mask larger than 800 px loses some resolution inside the window; tiling for very large masks is a later improvement.
- **Open:** run the same test on a 4 GB device, and watch peak memory with Instruments before release.
