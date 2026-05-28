#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p build/ModuleCache
swiftc -module-cache-path build/ModuleCache \
  desktop/DesktopPet.swift \
  -o build/DesktopPet \
  -framework Cocoa \
  -framework WebKit

exec ./build/DesktopPet
