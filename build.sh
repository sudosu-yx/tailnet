#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
#  Tailnet Pro Build Script (Podman + Multi-Arch)
# ------------------------------------------------------------
#  Features:
#   - Multi-arch (amd64 + arm64)
#   - Rootless Podman workflow
#   - Arguments: --tailscale <v> --sablier <v>
#   - Auto semver validation
#   - Parallel pushes
#   - Manifest publish (latest + version tag)
# ------------------------------------------------------------

# Defaults
TAILSCALE_VERSION=""
SABLIER_VERSION=""
VERSION="0.0.1"

# ------------------------------------------------------------
# Parse CLI arguments
# ------------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --tailscale) TAILSCALE_VERSION="$2"; shift ;;
        --sablier)   SABLIER_VERSION="$2"; shift ;;
        *)
            echo "❌ Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

# ------------------------------------------------------------
# Validate input
# ------------------------------------------------------------
if [[ -z "$TAILSCALE_VERSION" ]]; then
    echo "❌ Error: --tailscale <version> is required"
    echo "Usage: ./build.sh --tailscale 1.86.2 --sablier 1.10.1"
    exit 1
fi

VERSION="$TAILSCALE_VERSION"

# Semver check
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "⚠️ Warning: '$VERSION' does not match semver (x.y.z)"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# ------------------------------------------------------------
# Requirements check
# ------------------------------------------------------------
for bin in podman podman-compose; do
    if ! command -v "$bin" &>/dev/null; then
        echo "❌ Missing dependency: $bin"
        exit 1
    fi
done

echo "------------------------------------------------------------"
echo " 🧪 Building Tailnet"
echo " ------------------------------------------------------------"
echo "  → Tailscale: $TAILSCALE_VERSION"
echo "  → Sablier:   $SABLIER_VERSION"
echo "  → Version:   $VERSION"
echo "  → Arch:      amd64 + arm64"
echo "------------------------------------------------------------"

# ------------------------------------------------------------
# Build multi-arch images
# ------------------------------------------------------------
echo "🔨 Building multi-arch images via Podman..."

podman build \
  -t localhost/tailnet:amd64 \
  --build-arg SABLIER_VERSION="$SABLIER_VERSION" \
  --build-arg TARGETPLATFORM=linux/amd64 \
  --arch amd64 .

podman build \
  -t localhost/tailnet:arm64 \
  --build-arg SABLIER_VERSION="$SABLIER_VERSION" \
  --build-arg TARGETPLATFORM=linux/arm64 \
  --arch arm64 .

# ------------------------------------------------------------
# Tag for registry
# ------------------------------------------------------------
REG_FULL="docker.io/sudosu-yx/tailnet"

echo "🏷 Tagging images..."

podman tag localhost/tailnet:amd64 "$REG_FULL:amd64"
podman tag localhost/tailnet:arm64 "$REG_FULL:arm64"

# Versioned tags
podman tag localhost/tailnet:amd64 "$REG_FULL:$VERSION-amd64"
podman tag localhost/tailnet:arm64 "$REG_FULL:$VERSION-arm64"

# ------------------------------------------------------------
# Push arch images in parallel
# ------------------------------------------------------------
echo "📤 Pushing images (parallel)..."

(
    podman push "$REG_FULL:amd64" &&
    podman push "$REG_FULL:$VERSION-amd64"
) &

(
    podman push "$REG_FULL:arm64" &&
    podman push "$REG_FULL:$VERSION-arm64"
) &

wait

# ------------------------------------------------------------
# Create and push MANIFESTS
# ------------------------------------------------------------
echo "📦 Creating multi-arch manifest..."

MAN_LATEST="$REG_FULL:latest"
MAN_VERSION="$REG_FULL:$VERSION"

# Remove existing manifests (if any)
podman manifest rm "$MAN_LATEST" 2>/dev/null || true
podman manifest rm "$MAN_VERSION" 2>/dev/null || true

# Create manifests
podman manifest create "$MAN_LATEST"
podman manifest create "$MAN_VERSION"

# Add images to manifests
podman manifest add "$MAN_LATEST"   "$REG_FULL:amd64"
podman manifest add "$MAN_LATEST"   "$REG_FULL:arm64"
podman manifest add "$MAN_VERSION"  "$REG_FULL:$VERSION-amd64"
podman manifest add "$MAN_VERSION"  "$REG_FULL:$VERSION-arm64"

echo "🚀 Pushing manifests..."
podman manifest push "$MAN_LATEST"
podman manifest push "$MAN_VERSION"

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
echo ""
echo "🎉 SUCCESS — Multi-arch build & push complete!"
echo "------------------------------------------------------------"
echo " Published:"
echo "   → $REG_FULL:latest"
echo "   → $REG_FULL:$VERSION"
echo "   → $REG_FULL:amd64"
echo "   → $REG_FULL:arm64"
echo "   → $REG_FULL:$VERSION-amd64"
echo "   → $REG_FULL:$VERSION-arm64"
echo "------------------------------------------------------------"
