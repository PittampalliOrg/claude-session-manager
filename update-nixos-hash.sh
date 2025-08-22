#!/usr/bin/env bash

# Script to update NixOS configuration with new claude-manager hash
set -euo pipefail

VERSION="${1:-}"
AUTO_REBUILD="${2:-true}"
NIXOS_CONFIG="/etc/nixos/packages/claude-manager-fetchurl.nix"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [auto-rebuild]"
    echo "Example: $0 v1.2.0        # Updates and rebuilds"
    echo "Example: $0 v1.2.0 false  # Updates without rebuilding"
    exit 1
fi

echo "📦 Fetching hash for claude-manager ${VERSION}..."

# Download and get the hash
URL="https://github.com/PittampalliOrg/claude-session-manager/releases/download/${VERSION}/claude-manager-linux-x64"
echo "Downloading from: $URL"

# Get the hash using nix-prefetch-url
echo "Getting hash with nix-prefetch-url..."
HASH=$(nix-prefetch-url --type sha256 "$URL" 2>/dev/null | tail -1)

if [ -z "$HASH" ]; then
    echo "❌ Failed to fetch hash. Is the release published?"
    echo "   Try running: ./build-all-platforms.sh ${VERSION} true"
    exit 1
fi

# Convert to SRI format
SRI_HASH=$(nix hash to-sri --type sha256 "$HASH" 2>/dev/null)

echo "✅ Got hash: $SRI_HASH"

# Update the NixOS configuration
echo "📝 Updating NixOS configuration..."

# Create a temporary file for the update
TEMP_FILE=$(mktemp)

# Update version and hash in the fetchBinary section
awk -v version="${VERSION#v}" -v hash="$SRI_HASH" '
    /^  version = / && !done_version {
        print "  version = \"" version "\";";
        done_version = 1;
        next;
    }
    /sha256 = "sha256-/ && in_fetch_binary {
        print "      sha256 = \"" hash "\";";
        next;
    }
    /fetchBinary = / { in_fetch_binary = 1 }
    /^  \};$/ && in_fetch_binary { in_fetch_binary = 0 }
    { print }
' "$NIXOS_CONFIG" > "$TEMP_FILE"

# Apply the changes with sudo
sudo cp "$TEMP_FILE" "$NIXOS_CONFIG"
rm "$TEMP_FILE"

echo "✅ Updated configuration:"
echo "  Version: ${VERSION#v}"
echo "  Hash: $SRI_HASH"

if [ "$AUTO_REBUILD" = "true" ]; then
    echo ""
    echo "🔨 Rebuilding NixOS..."
    if sudo nixos-rebuild switch; then
        echo "✅ NixOS rebuild successful!"
        exit 0
    else
        echo "❌ NixOS rebuild failed"
        exit 1
    fi
else
    echo ""
    echo "📌 Configuration updated. To apply changes, run:"
    echo "   sudo nixos-rebuild switch"
fi