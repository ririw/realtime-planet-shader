#!/usr/bin/env bash
# Downloads planet textures from Solar System Scope into public/
# Run from the repo root: bash scripts/download-textures.sh

set -e

BASE_URL="https://www.solarsystemscope.com/textures/download"
PUBLIC_DIR="$(dirname "$0")/../public"

download() {
  local filename="$1"
  local dest="$PUBLIC_DIR/$filename"
  if [ -f "$dest" ]; then
    echo "Already exists: $filename"
  else
    echo "Downloading $filename..."
    curl -fsSL "$BASE_URL/$filename" -o "$dest"
    echo "Saved: $filename"
  fi
}

download "2k_neptune.jpg"
download "2k_saturn.jpg"

echo "Done."
