#!/usr/bin/env bash
set -euo pipefail
# Same model as the captured configuration; keep the large model outside Git.
model_dir="$HOME/.local/share/voxtype/models"
model="$model_dir/ggml-base.en.bin"
mkdir -p "$model_dir"
expected=a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002
if [[ ! -f $model ]] || [[ $(sha256sum "$model" | cut -d' ' -f1) != "$expected" ]]; then
  partial=$(mktemp "$model_dir/.base.en.XXXXXX")
  trap 'rm -f -- "$partial"' EXIT
  curl --fail --location --show-error --retry 3 \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin -o "$partial"
  printf '%s  %s\n' "$expected" "$partial" | sha256sum --check --status
  mv -- "$partial" "$model"
fi
