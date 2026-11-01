#!/usr/bin/env bash
# Exports a COCO-pretrained YOLO model to ONNX so Elixir (Ortex) can run it.
#
# This is the "Python side" of the architecture: Python owns the model
# (download / train / export), Elixir only loads the finished .onnx file.
#
# Usage:  scripts/export_yolo.sh            # yolo11n (nano, fastest)
#         scripts/export_yolo.sh yolo11s    # small, slower but more accurate
set -euo pipefail

MODEL="${1:-yolo11n}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"

cd "$WORK"
# uvx runs ultralytics in a throwaway environment, so nothing is installed globally.
# imgsz=640 fixes the input to 1x3x640x640, which lib/indoors_experiments/vision/preprocess.ex assumes.
uvx --from ultralytics yolo export model="$MODEL.pt" format=onnx imgsz=640

mkdir -p "$ROOT/priv/models"
mv "$MODEL.onnx" "$ROOT/priv/models/$MODEL.onnx"
rm -rf "$WORK"
echo "Saved priv/models/$MODEL.onnx"
