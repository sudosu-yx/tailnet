#!/bin/bash

# gh release view -R sablierapp/sablier --json tagName --jq '.tagName | ltrimstr("v")'

set -e  # Exit immediately if a command exits with a non-zero status

# Default values
TAILSCALE_VERSION=""
SABLIER_VERSION=""
VERSION=""
IMAGE="sudosu-yx/tailnet"
PFX="localhost/"


# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --tailscale) TAILSCALE_VERSION="$2"; shift ;;
        --sablier) SABLIER_VERSION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if tailscale version is provided
if [ -z "$TAILSCALE_VERSION" ]; then
    echo "Error: Tailscale version is required"
    echo "Usage: ./build.sh --tailscale <version> [--sablier <version>]"
    echo "Example: ./build.sh --tailscale 1.86.2 --sablier 1.10.1"
    exit 1
fi

VERSION=$TAILSCALE_VERSION

# Validate version format (basic semver check)
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Warning: Version '$VERSION' doesn't follow semver format (x.y.z)"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi


if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman not installed"
  exit 1
fi

echo "--------------------------------------------"
echo "Tailnet Podman Build"
echo "--------------------------------------------"
echo "Tailscale Version : $TAILSCALE_VERSION"
echo "Sablier Version   : ${SABLIER_VERSION:-<none>}"
echo "Tag Version       : $VERSION"
echo "Using Podman      : $(podman --version)"
echo "--------------------------------------------"
echo

#
# Build amd64 + arm64 images
#
echo "Building amd64 image..."
podman build \
  --arch amd64 \
  --build-arg TAILSCALE_VERSION="$TAILSCALE_VERSION" \
  --build-arg SABLIER_VERSION="$SABLIER_VERSION" \
  -t "${PFX}${IMAGE}:amd64" \
  -f docker/Dockerfile .

echo "Building arm64 image..."
podman build \
  --arch arm64 \
  --build-arg TAILSCALE_VERSION="$TAILSCALE_VERSION" \
  --build-arg SABLIER_VERSION="$SABLIER_VERSION" \
  -t "${PFX}${IMAGE}:arm64" \
  -f docker/Dockerfile .

#
# Tag version variants
#
echo "Tagging images..."
podman tag "${PFX}${IMAGE}:amd64" "${PFX}${IMAGE}:${VERSION}-amd64"
podman tag "${PFX}${IMAGE}:arm64" "${PFX}${IMAGE}:${VERSION}-arm64"

# Latest = amd64 by convention (local only)
podman tag "${PFX}${IMAGE}:amd64" "${PFX}${IMAGE}:latest"
podman tag "${PFX}${IMAGE}:amd64" "${PFX}${IMAGE}:${VERSION}"

#
# (Optional) Create a local multi-arch manifest
#
echo "Creating local manifest..."
MANIFEST="${PFX}${IMAGE}:${VERSION}"
podman manifest create "$MANIFEST" || true
podman manifest add "$MANIFEST" "${PFX}${IMAGE}:${VERSION}-amd64"
podman manifest add "$MANIFEST" "${PFX}${IMAGE}:${VERSION}-arm64"

echo
echo "✔ Build complete"
echo "Local images:"
podman images | grep "sudosu-yx/tailnet"
echo
echo "Multi-arch manifest created:"
podman manifest inspect "${PFX}${IMAGE}:${VERSION}" | jq .