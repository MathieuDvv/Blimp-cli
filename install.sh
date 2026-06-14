#!/usr/bin/env bash
#
# Blimp installer
#
#   curl -fsSL https://raw.githubusercontent.com/MathieuDvv/Blimp-cli/main/install.sh | bash
#
# Downloads the prebuilt binary matching your OS/arch from the latest GitHub
# release and installs it. Falls back to building from source (needs Swift) if
# no prebuilt binary is available for your platform.
#
# Environment overrides:
#   BLIMP_VERSION   release tag to install (default: latest)
#   BLIMP_INSTALL   install directory     (default: first writable of
#                   /usr/local/bin, ~/.local/bin)
#
set -euo pipefail

REPO="MathieuDvv/Blimp-cli"
BINARY="blimp"

info()  { printf '\033[34m::\033[0m %s\n' "$*"; }
ok()    { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# --- detect platform -------------------------------------------------------

os=$(uname -s)
arch=$(uname -m)

case "$os" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)      die "Unsupported OS: $os (Windows users: grab blimp.exe from the Releases page)" ;;
esac

case "$arch" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) die "Unsupported architecture: $arch" ;;
esac

# macOS ships universal binaries, so the asset is arch-agnostic there.
if [ "$PLATFORM" = "macos" ]; then
  ASSET="blimp-macos-universal.tar.gz"
else
  ASSET="blimp-linux-${ARCH}.tar.gz"
fi

# --- pick install dir ------------------------------------------------------

choose_install_dir() {
  if [ -n "${BLIMP_INSTALL:-}" ]; then echo "$BLIMP_INSTALL"; return; fi
  for d in /usr/local/bin "$HOME/.local/bin"; do
    if [ -d "$d" ] && [ -w "$d" ]; then echo "$d"; return; fi
  done
  # default: create ~/.local/bin
  echo "$HOME/.local/bin"
}

INSTALL_DIR=$(choose_install_dir)
mkdir -p "$INSTALL_DIR"

# --- resolve version -------------------------------------------------------

VERSION="${BLIMP_VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- try prebuilt binary ---------------------------------------------------

install_prebuilt() {
  local url="$BASE/$ASSET"
  info "Downloading $ASSET ..."
  if ! curl -fsSL "$url" -o "$TMP/$ASSET" 2>/dev/null; then
    return 1
  fi
  # optional checksum verification
  if curl -fsSL "$BASE/checksums.txt" -o "$TMP/checksums.txt" 2>/dev/null; then
    info "Verifying checksum ..."
    ( cd "$TMP" && grep " $ASSET\$" checksums.txt | shasum_check ) || warn "Checksum check skipped/failed"
  fi
  tar -xzf "$TMP/$ASSET" -C "$TMP"
  install -m 0755 "$TMP/$BINARY" "$INSTALL_DIR/$BINARY"
  return 0
}

shasum_check() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -c -
  elif command -v shasum  >/dev/null 2>&1; then shasum -a 256 -c -
  else cat >/dev/null; fi
}

# --- fallback: build from source ------------------------------------------

build_from_source() {
  command -v swift >/dev/null 2>&1 || die "No prebuilt binary for $PLATFORM/$ARCH and Swift is not installed. Install Swift from https://swift.org/install and re-run."
  command -v git   >/dev/null 2>&1 || die "git is required to build from source."
  info "Building from source with Swift ..."
  local ref="$VERSION"; [ "$ref" = "latest" ] && ref="main"
  git clone --depth 1 --branch "$ref" "https://github.com/$REPO.git" "$TMP/src" 2>/dev/null \
    || git clone --depth 1 "https://github.com/$REPO.git" "$TMP/src"
  ( cd "$TMP/src" && swift build -c release )
  install -m 0755 "$TMP/src/.build/release/$BINARY" "$INSTALL_DIR/$BINARY"
}

# --- run -------------------------------------------------------------------

info "Installing blimp ($PLATFORM/$ARCH) to $INSTALL_DIR"
if install_prebuilt; then
  ok "Installed prebuilt binary"
else
  warn "No prebuilt binary found for this platform — falling back to source build"
  build_from_source
  ok "Built and installed from source"
fi

# --- PATH hint -------------------------------------------------------------

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) warn "$INSTALL_DIR is not on your PATH. Add this to your shell profile:"
     printf '\n    export PATH="%s:$PATH"\n\n' "$INSTALL_DIR" ;;
esac

ok "Done! Run: $BINARY"
