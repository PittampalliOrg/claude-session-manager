#!/usr/bin/env bash

# Build script for claude-manager - all platforms
set -euo pipefail

# Configuration
VERSION="${1:-}"
CREATE_RELEASE="${2:-false}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [create-release]"
    echo "Example: $0 v1.0.1"
    echo "Example: $0 v1.0.1 true  # Also creates GitHub release"
    exit 1
fi

echo "🚀 Building claude-manager $VERSION for all platforms..."
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

# Create GitHub release if requested
if [ "$CREATE_RELEASE" = "true" ]; then
    echo ""
    echo "📤 Creating GitHub release $VERSION..."
    
    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) is not installed. Please install it first."
        echo "   Visit: https://cli.github.com/"
        exit 1
    fi
    
    # Check if release already exists
    if gh release view "$VERSION" --repo PittampalliOrg/claude-session-manager &> /dev/null; then
        echo "⚠️  Release $VERSION already exists. Uploading assets..."
        # Upload assets to existing release
        gh release upload "$VERSION" \
            binaries/claude-manager-linux-x64 \
            binaries/claude-manager-linux-arm64 \
            binaries/claude-manager-macos-x64 \
            binaries/claude-manager-macos-arm64 \
            binaries/claude-manager-windows-x64.exe \
            --repo PittampalliOrg/claude-session-manager \
            --clobber
    else
        # Create new release with binaries
        gh release create "$VERSION" \
            binaries/claude-manager-linux-x64 \
            binaries/claude-manager-linux-arm64 \
            binaries/claude-manager-macos-x64 \
            binaries/claude-manager-macos-arm64 \
            binaries/claude-manager-windows-x64.exe \
            --repo PittampalliOrg/claude-session-manager \
            --title "Claude Session Manager $VERSION" \
            --notes "## Claude Session Manager $VERSION

### Features
- Smart tmux session management with FZF integration
- Session history tracking and restoration
- Multi-platform support (Linux, macOS, Windows)
- Seamless integration with Claude Code

### Installation

Download the appropriate binary for your platform:

#### Linux x64
\`\`\`bash
wget https://github.com/PittampalliOrg/claude-session-manager/releases/download/$VERSION/claude-manager-linux-x64
chmod +x claude-manager-linux-x64
sudo mv claude-manager-linux-x64 /usr/local/bin/claude-manager
\`\`\`

#### Linux ARM64
\`\`\`bash
wget https://github.com/PittampalliOrg/claude-session-manager/releases/download/$VERSION/claude-manager-linux-arm64
chmod +x claude-manager-linux-arm64
sudo mv claude-manager-linux-arm64 /usr/local/bin/claude-manager
\`\`\`

#### macOS Intel
\`\`\`bash
wget https://github.com/PittampalliOrg/claude-session-manager/releases/download/$VERSION/claude-manager-macos-x64
chmod +x claude-manager-macos-x64
sudo mv claude-manager-macos-x64 /usr/local/bin/claude-manager
\`\`\`

#### macOS Apple Silicon
\`\`\`bash
wget https://github.com/PittampalliOrg/claude-session-manager/releases/download/$VERSION/claude-manager-macos-arm64
chmod +x claude-manager-macos-arm64
sudo mv claude-manager-macos-arm64 /usr/local/bin/claude-manager
\`\`\`

#### Windows
Download \`claude-manager-windows-x64.exe\` and add to your PATH.

### Checksums
Verify your download:
\`\`\`
$(cd binaries && sha256sum claude-manager-* 2>/dev/null || shasum -a 256 claude-manager-*)
\`\`\`"
    fi
    
    echo "✅ GitHub release $VERSION created/updated successfully!"
    echo "   View at: https://github.com/PittampalliOrg/claude-session-manager/releases/tag/$VERSION"
fi