#!/usr/bin/env bash
set -euo pipefail

asset_dir="${1:?pass the Whisper asset directory}"
mkdir -p "$asset_dir"
model="$asset_dir/ggml-tiny-q5_1.bin"
want='2827a03e495b1ed3048ef28a6a4620537db4ee51'
if ! printf '%s  %s\n' "$want" "$model" | sha1sum --status -c -; then
  temp=$(mktemp "$asset_dir/.model.XXXXXX")
  trap 'rm -f "$temp"' EXIT
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin -o "$temp"
  printf '%s  %s\n' "$want" "$temp" | sha1sum --check -
  mv "$temp" "$model"
fi
