#!/usr/bin/env bash
#
# Build script for the cuda-runtime desktop image.
#
# Usage:
#   ./build.sh                       # build with defaults
#   ./build.sh -t my-tag             # override tag
#   ./build.sh -r registry.example.com/ns -p   # build + push to a registry
#   ./build.sh --load-tar img.tar    # load an image from a tar (e.g. matlab-vnc.tar)
#   ./build.sh --save-tar img.tar    # export the built image to a tar
#
# See `./build.sh -h` for all options.
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (override via flags or environment variables)
# ---------------------------------------------------------------------------
IMAGE_NAME="${IMAGE_NAME:-cuda-runtime-desktop}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"                 # e.g. registry.example.com/namespace
PLATFORM="linux/amd64"                    # Dockerfile is amd64-only (TigerVNC/oneport/fcitx .deb)
NO_CACHE="false"
PUSH="false"
LOAD_TAR=""
SAVE_TAR=""
BUILD_ARGS=()

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- extra-docker-build-args]

Build the ${IMAGE_NAME} desktop image.

Options:
  -n, --name NAME        Image name            (default: ${IMAGE_NAME}, env IMAGE_NAME)
  -t, --tag TAG          Image tag             (default: ${IMAGE_TAG}, env IMAGE_TAG)
  -r, --registry URL     Registry/namespace prefix, e.g. registry.example.com/ns
                         (env REGISTRY). Implies push target "<registry>/<name>:<tag>"
  -p, --push             Push after a successful build (requires --registry)
      --no-cache         Pass --no-cache to docker build
      --platform PLAT    Target platform       (default: ${PLATFORM})
      --load-tar FILE    Skip build; load an image from a saved tar file
      --save-tar FILE    After build, export image to a tar file
  -h, --help             Show this help

Examples:
  $(basename "$0")
  $(basename "$0") -t 1.0 -r registry.example.com/library -p
  $(basename "$0") --no-cache -- --build-arg VNC_PW=secret
  $(basename "$0") --load-tar matlab-vnc.tar
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)     IMAGE_NAME="$2"; shift 2 ;;
        -t|--tag)      IMAGE_TAG="$2"; shift 2 ;;
        -r|--registry) REGISTRY="$2"; shift 2 ;;
        -p|--push)     PUSH="true"; shift ;;
        --no-cache)    NO_CACHE="true"; shift ;;
        --platform)    PLATFORM="$2"; shift 2 ;;
        --load-tar)    LOAD_TAR="$2"; shift 2 ;;
        --save-tar)    SAVE_TAR="$2"; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        --)            shift; BUILD_ARGS+=("$@"); break ;;
        -*)            echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *)             echo "Unexpected argument: $1" >&2; usage; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight: docker must be available
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "✗ docker not found in PATH. Please install Docker first." >&2
    exit 1
fi

# Resolve the script directory so it can be run from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "Dockerfile" ]]; then
    echo "✗ Dockerfile not found in $SCRIPT_DIR" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Mode: load a tar image and exit
# ---------------------------------------------------------------------------
if [[ -n "$LOAD_TAR" ]]; then
    if [[ ! -f "$LOAD_TAR" ]]; then
        echo "✗ tar file not found: $LOAD_TAR" >&2
        exit 1
    fi
    echo "→ Loading image from $LOAD_TAR ..."
    docker load -i "$LOAD_TAR"
    echo "✓ Done."
    exit 0
fi

# ---------------------------------------------------------------------------
# Compose the full image reference
# ---------------------------------------------------------------------------
if [[ -n "$REGISTRY" ]]; then
    # Strip any trailing slash from the registry/namespace prefix.
    REGISTRY="${REGISTRY%/}"
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
fi

# ---------------------------------------------------------------------------
# Push sanity check
# ---------------------------------------------------------------------------
if [[ "$PUSH" == "true" && -z "$REGISTRY" ]]; then
    echo "✗ --push requires --registry (a registry/namespace prefix)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
# BuildKit gives better layer caching and progress output. The Dockerfile pins
# the platform to linux/amd64; on Apple Silicon / arm64 hosts the build runs
# under QEMU emulation automatically.
export DOCKER_BUILDKIT=1

BUILD_CMD=(docker buildx build
    --platform "$PLATFORM"
    -t "$FULL_IMAGE"
    --load)

if [[ "$NO_CACHE" == "true" ]]; then
    BUILD_CMD+=(--no-cache)
fi

# Append any user-supplied extra args collected after "--".
# NOTE: under `set -u`, expanding an empty array as "${ARR[@]}" throws
# "unbound variable" on bash 3.2 (macOS default). Guard with the count.
if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
    BUILD_CMD+=("${BUILD_ARGS[@]}")
fi
BUILD_CMD+=(".")

echo "→ Building image: ${FULL_IMAGE}"
echo "  platform: ${PLATFORM}"
echo "  context:  ${SCRIPT_DIR}"
if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
    echo "  extra:    ${BUILD_ARGS[*]}"
fi
echo

"${BUILD_CMD[@]}"

echo "✓ Built ${FULL_IMAGE}"

# ---------------------------------------------------------------------------
# Optionally export to tar
# ---------------------------------------------------------------------------
if [[ -n "$SAVE_TAR" ]]; then
    echo "→ Saving image to $SAVE_TAR ..."
    # Use the platform tag so the exported tar matches the built artifact.
    docker save -o "$SAVE_TAR" "$FULL_IMAGE"
    echo "✓ Saved $(du -h "$SAVE_TAR" | cut -f1) → $SAVE_TAR"
fi

# ---------------------------------------------------------------------------
# Optionally push
# ---------------------------------------------------------------------------
if [[ "$PUSH" == "true" ]]; then
    echo "→ Pushing ${FULL_IMAGE} ..."
    docker push "$FULL_IMAGE"
    echo "✓ Pushed ${FULL_IMAGE}"
fi
