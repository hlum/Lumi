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

if [ ! -d RealESRGAN_x4.mlpackage ]; then
  base=https://huggingface.co/mlboydaisuke/Real-ESRGAN-x4-CoreML/resolve/main/RealESRGAN_x4.mlpackage
  mkdir -p RealESRGAN_x4.mlpackage/Data/com.apple.CoreML
  curl -fsSL "$base/Manifest.json" -o RealESRGAN_x4.mlpackage/Manifest.json
  curl -fsSL "$base/Data/com.apple.CoreML/model.mlmodel" -o RealESRGAN_x4.mlpackage/Data/com.apple.CoreML/model.mlmodel
fi

if [ ! -d SIGGraph17Colorizer.mlpackage ]; then
  curl -fsSL "https://huggingface.co/c2p-cmd/bw_colorizer_coreml/resolve/main/SIGGraph17Colorizer.mlpackage.zip" -o sig17.zip
  unzip -q -o sig17.zip
  rm -f sig17.zip
  rm -rf __MACOSX
fi

if [ ! -d FaceParsing.mlpackage ]; then
  base=https://huggingface.co/mlboydaisuke/Face-Parsing-CoreML/resolve/main/FaceParsing.mlpackage
  mkdir -p FaceParsing.mlpackage/Data/com.apple.CoreML
  curl -fsSL "$base/Manifest.json" -o FaceParsing.mlpackage/Manifest.json
  curl -fsSL "$base/Data/com.apple.CoreML/model.mlmodel" -o FaceParsing.mlpackage/Data/com.apple.CoreML/model.mlmodel
fi

if [ ! -d BiRefNetLite.mlpackage ]; then
  base=https://huggingface.co/metaclass/birefnet-lite-coreml/resolve/main/fp16compute-fp32io/r1/BiRefNetLite-1024-FP16Compute-FP32IO.mlpackage
  mkdir -p BiRefNetLite.mlpackage/Data/com.apple.CoreML/weights
  curl -fsSL "$base/Manifest.json" -o BiRefNetLite.mlpackage/Manifest.json
  curl -fsSL "$base/Data/com.apple.CoreML/model.mlmodel" -o BiRefNetLite.mlpackage/Data/com.apple.CoreML/model.mlmodel
  curl -fsSL "$base/Data/com.apple.CoreML/weights/weight.bin" -o BiRefNetLite.mlpackage/Data/com.apple.CoreML/weights/weight.bin
fi
