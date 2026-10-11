# Spike T06: hair segmentation

**No-go on a bundled hair model. Go on the plan's fallback.**

- **Candidates checked:** `mlboydaisuke/Face-Parsing-CoreML` (BiSeNet, 19 classes incl. hair, 47 MB, code MIT) and several TFLite/ONNX hair-segmentation models on Hugging Face.
- **Licence problem:** the face-parsing weights are trained on CelebAMask-HQ, whose dataset terms restrict use to non-commercial research. The MIT licence covers the code, not what the weights learned from, so redistributing them in an app is not clearly allowed. The plan says licences are verified, not assumed, so it is not bundled. The TFLite/ONNX candidates have no clear provenance or licence statement for their training data either.
- **Fallback (implemented):** `HairMask.estimate` = Vision person mask ∩ a head region around the detected face − face skin − the face box's lower part. The user refines it with the existing brush (`MaskCanvas`). Quality is lower on hair against busy backgrounds and on hats; the brush is the escape hatch.
- **Re-scope:** hair colour (T49) works on this mask. Hair shape (T50, volume/length warps) is limited to the head region the same way. If a clearly licensed model appears (own training data, or a permissive dataset), swapping it in only touches `HairMask`.
