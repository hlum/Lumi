#!/bin/sh
# Downloads ML models that are too big for git (GitHub rejects files over 100 MB). Run once; CI runs it from ci_scripts/ci_post_clone.sh.
set -e
mkdir -p "$(dirname "$0")/../Lumi/Resources/Models"
cd "$(dirname "$0")/../Lumi/Resources/Models"
if [ ! -d LaMa.mlpackage ]; then
  base=https://huggingface.co/mlboydaisuke/LaMa-CoreML/resolve/main/LaMa.mlpackage
  mkdir -p LaMa.mlpackage/Data/com.apple.CoreML/weights
  curl -fsSL "$base/Manifest.json" -o LaMa.mlpackage/Manifest.json
  curl -fsSL "$base/Data/com.apple.CoreML/model.mlmodel" -o LaMa.mlpackage/Data/com.apple.CoreML/model.mlmodel
  curl -fsSL "$base/Data/com.apple.CoreML/weights/weight.bin" -o LaMa.mlpackage/Data/com.apple.CoreML/weights/weight.bin
fi
