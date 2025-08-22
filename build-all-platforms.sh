#!/usr/bin/env bash

# Build script for claude-manager - all platforms
set -euo pipefail

echo "🚀 Building claude-manager for all platforms..."
echo ""

# Create binaries directory
mkdir -p binaries

# Linux x64
echo "📦 Building for Linux x64..."
deno compile \
  --allow-all \
  --no-check \
  --target x86_64-unknown-linux-gnu \
  --output binaries/claude-manager-linux-x64 \
  claude-session-manager.ts

# Linux ARM64 (if needed)
echo "📦 Building for Linux ARM64..."
deno compile \
  --allow-all \
  --no-check \
  --target aarch64-unknown-linux-gnu \
  --output binaries/claude-manager-linux-arm64 \
  claude-session-manager.ts

# macOS x64 (Intel)
echo "📦 Building for macOS x64 (Intel)..."
deno compile \
  --allow-all \
  --no-check \
  --target x86_64-apple-darwin \
  --output binaries/claude-manager-macos-x64 \
  claude-session-manager.ts

# macOS ARM64 (Apple Silicon)
echo "📦 Building for macOS ARM64 (Apple Silicon)..."
deno compile \
  --allow-all \
  --no-check \
  --target aarch64-apple-darwin \
  --output binaries/claude-manager-macos-arm64 \
  claude-session-manager.ts

# Windows x64
echo "📦 Building for Windows x64..."
deno compile \
  --allow-all \
  --no-check \
  --target x86_64-pc-windows-msvc \
  --output binaries/claude-manager-windows-x64.exe \
  claude-session-manager.ts

echo ""
echo "✅ All platforms built successfully!"
echo ""
echo "Binaries created in ./binaries/:"
ls -lah binaries/ | tail -n +2

echo ""
echo "📋 Platform mapping:"
echo "  Linux x64:         binaries/claude-manager-linux-x64"
echo "  Linux ARM64:       binaries/claude-manager-linux-arm64"
echo "  macOS x64:         binaries/claude-manager-macos-x64"
echo "  macOS ARM64:       binaries/claude-manager-macos-arm64"
echo "  Windows x64:       binaries/claude-manager-windows-x64.exe"