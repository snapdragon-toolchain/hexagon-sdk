#!/bin/bash
set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <hexagon_sdk_zip_url> [flavor]"
    echo "  flavor: 'linux' (default) or 'windows'"
    exit 1
fi

URL="$1"
FLAVOR="${2:-linux}"
ZIP_FILE=$(basename "$URL")

if [ "$FLAVOR" != "linux" ] && [ "$FLAVOR" != "windows" ]; then
    echo "Error: flavor must be 'linux' or 'windows'"
    exit 1
fi

echo "Downloading $URL..."
wget -q -O "$ZIP_FILE" "$URL"

echo "Extracting $ZIP_FILE..."
unzip -q "$ZIP_FILE"

# Find version directory
VERSION_DIR=$(ls Hexagon_SDK | head -n 1)
SDK_PATH="Hexagon_SDK/$VERSION_DIR"

echo "Stripping unnecessary files from $SDK_PATH..."

# 1. Preserve important binaries before sweeping removals
mkdir -p "$SDK_PATH/ipc/fastrpc/qaic/bin"
if [ "$FLAVOR" = "linux" ]; then
    cp "$SDK_PATH/ipc/fastrpc/qaic/Ubuntu/qaic" "$SDK_PATH/ipc/fastrpc/qaic/bin/qaic" || true
else
    cp "$SDK_PATH/ipc/fastrpc/qaic/WinNT/qaic.exe" "$SDK_PATH/ipc/fastrpc/qaic/bin/qaic.exe" || true
fi

# 2. Remove Top-Level Documents and Examples
rm -f "$SDK_PATH"/*.pdf
rm -rf "$SDK_PATH/docs"
rm -rf "$SDK_PATH/examples"

# 3. Find and remove deeper 'examples', 'docs', 'tests', 'Documents', 'Examples' generic directories
find "$SDK_PATH" -type d \( \
    -name "examples" -o \
    -name "Examples" -o \
    -name "docs" -o \
    -name "Documents" -o \
    -name "tests" -o \
    -name "googletest" -o \
    -name "test_main" \
\) -prune -exec rm -rf {} + || true

# 4. Specific tools cleanup: Uninstall directories, etc
find "$SDK_PATH/tools" -type d -name "Uninstall" -prune -exec rm -rf {} + || true

# 5. Remove unnecessary top level utils/tools directories that were removed
rm -rf "$SDK_PATH/tools/wrapperTools"
rm -rf "$SDK_PATH/tools/hexagon_ide"
rm -rf "$SDK_PATH/tools/HALIDE_Tools"
rm -rf "$SDK_PATH/tools/elfsigner"
rm -rf "$SDK_PATH/tools/Tools"
rm -rf "$SDK_PATH/tools/debug/mini-dm_deprecate"
rm -rf "$SDK_PATH/utils/visualize_hvx_instructions"

# 6. FastRPC QAIC deprecated/ubuntu/win folders
rm -rf "$SDK_PATH/ipc/fastrpc/qaic/Ubuntu"*
rm -rf "$SDK_PATH/ipc/fastrpc/qaic/WinNT"*
rm -rf "$SDK_PATH/ipc/fastrpc/qaic/Makefile"

# 7. Specific prebuilt tool targets we want to remove to save size.
# In the original manual strip, most hexagon_toolv* directories were removed.
# Let's remove them generically.
find "$SDK_PATH" -type d -name "hexagon_toolv*" -prune -exec rm -rf {} + || true

# 8. Strip all ELF binaries to save space (Linux only)
if [ "$FLAVOR" = "linux" ]; then
    echo "Stripping binaries..."
    find "$SDK_PATH" -type f -exec file {} + | grep -i "elf 64-bit lsb" | grep -i "x86-64" | cut -d: -f1 | tr "\n" "\0" | xargs -0 -r strip -s || true
fi

# Pack into tar.xz
if [ "$FLAVOR" = "linux" ]; then
    OUT_FILE="hexagon-sdk-v${VERSION_DIR}-amd64-lnx.tar.xz"
else
    # Output format used by windows artifact
    OUT_FILE="hexagon-sdk-v${VERSION_DIR}-arm64-wos.tar.xz"
fi

echo "Creating archive $OUT_FILE..."
cd Hexagon_SDK
tar -cf - "$VERSION_DIR" | xz -T0 > "../$OUT_FILE"
cd ..

echo "Done. Created $OUT_FILE."
