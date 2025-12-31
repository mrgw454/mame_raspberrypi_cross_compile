#!/bin/bash
set -euo pipefail

#############################################
# Helper: Pause for confirmation
#############################################
confirm() {
    echo
    read -rp "Press ENTER to continue..."
    echo
}

#############################################
# Detect Debian release (for -r flag)
#############################################
DEBIAN_RELEASE=$(grep -oE '^[0-9]+' /etc/debian_version)
echo "Detected Debian release: $DEBIAN_RELEASE"
confirm

#############################################
# 0. Host architecture check
#############################################
echo "=== Host Architecture Check ==="
systemtype=$(dpkg --print-architecture)
echo "Detected architecture: $systemtype"

if [[ $systemtype =~ arm64 ]]; then
    echo "ERROR: This project cannot run on ARM64 hosts."
    exit 1
fi
confirm

#############################################
# 1. Verify pyenv + Python 3.11.2
#############################################
echo "=== pyenv Verification ==="
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

if ! command -v pyenv >/dev/null 2>&1; then
    echo "ERROR: pyenv not found. Install pyenv first."
    exit 1
fi

eval "$(pyenv init -)"

echo "Available pyenv versions:"
pyenv versions
echo

if ! pyenv versions --bare | grep -qx "3.11.2"; then
    echo "ERROR: Python 3.11.2 missing from pyenv."
    exit 1
fi

export PYENV_VERSION="3.11.2"
echo "Using Python: $(python3 --version)"
confirm

#############################################
# 2. Determine project directory
#############################################
WRAPPER_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$WRAPPER_DIR/mame-cross-compile.sh" ] && [ -d "$WRAPPER_DIR/functions" ]; then
    PROJECT_DIR="$WRAPPER_DIR"
    echo "Wrapper is inside the project directory."
else
    PROJECT_DIR="$HOME/source/mame_raspberrypi_cross_compile"
    echo "Wrapper is outside the project directory."
fi
confirm

#############################################
# 3. Determine if full build is needed
#############################################
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project folder NOT found — FULL BUILD required (clone + download + prepare)."
    FULL_BUILD=1
else
    echo "Project folder exists."
    FULL_BUILD=0
fi
confirm

#############################################
# 4. If project exists but toolchain missing → FULL BUILD (no clone)
#############################################
TOOLCHAIN_GLOB="$PROJECT_DIR/build/x-tools/debian_${DEBIAN_RELEASE}_*/bin"

if [ "$FULL_BUILD" -eq 0 ]; then
    if ! ls $TOOLCHAIN_GLOB >/dev/null 2>&1; then
        echo "Toolchain missing — FULL BUILD required (no clone)."
        FULL_BUILD=2
        confirm
    fi
fi

#############################################
# 5. Clone repo if FULL_BUILD=1
#############################################
if [ "$FULL_BUILD" -eq 1 ]; then
    echo "=== Cloning Project Repository ==="
    mkdir -p "$HOME/source"
    cd "$HOME/source"

    if [ -d mame_raspberrypi_cross_compile ]; then
        echo "ERROR: Unexpected existing folder. Aborting to avoid contamination."
        exit 1
    fi

    git clone https://github.com/mrgw454/mame_raspberrypi_cross_compile
    PROJECT_DIR="$HOME/source/mame_raspberrypi_cross_compile"
    cd "$PROJECT_DIR"

    echo "=== Running FULL BUILD Steps ==="
    ./mame-cross-compile.sh -o download -r "$DEBIAN_RELEASE" -a arm64
    confirm
    ./mame-cross-compile.sh -o prepare -r "$DEBIAN_RELEASE" -a arm64
    confirm
fi

#############################################
# 6. FULL_BUILD=2 → run download + prepare (no clone)
#############################################
if [ "$FULL_BUILD" -eq 2 ]; then
    echo "=== Running FULL BUILD Steps (no clone) ==="
    cd "$PROJECT_DIR"
    ./mame-cross-compile.sh -o download -r "$DEBIAN_RELEASE" -a arm64
    confirm
    ./mame-cross-compile.sh -o prepare -r "$DEBIAN_RELEASE" -a arm64
    confirm
fi

#############################################
# 7. Move into project folder
#############################################
cd "$PROJECT_DIR"

#############################################
# 8. Environment hygiene (for compile phase)
#############################################
echo "=== Environment Hygiene Check ==="
VARS=(
    CC CXX LD AR AS STRIP RANLIB OBJCOPY OBJDUMP NM
    CROSS_COMPILE OVERRIDE_CC OVERRIDE_CXX OVERRIDE_LD OVERRIDE_AR
)

for v in "${VARS[@]}"; do
    if [[ -n "${!v-}" ]]; then
        echo "Unset polluted variable: $v"
        unset "$v"
    fi
done

echo "Environment is clean."
confirm

#############################################
# 9. Verify toolchain
#############################################
echo "=== Toolchain Verification ==="
TOOLCHAIN_DIR="build/x-tools/debian_${DEBIAN_RELEASE}_trixie_arm64/bin"

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "ERROR: Toolchain directory missing: $TOOLCHAIN_DIR"
    exit 1
fi

echo "Toolchain directory: $TOOLCHAIN_DIR"
echo

REQUIRED_TOOLS=(
    aarch64-rpi4-linux-gnu-gcc
    aarch64-rpi4-linux-gnu-g++
    aarch64-rpi4-linux-gnu-ar
    aarch64-rpi4-linux-gnu-ld
    aarch64-rpi4-linux-gnu-ld.gold
    aarch64-rpi4-linux-gnu-strip
)

for TOOL in "${REQUIRED_TOOLS[@]}"; do
    if [ ! -x "$TOOLCHAIN_DIR/$TOOL" ]; then
        echo "ERROR: Missing toolchain binary: $TOOL"
        exit 1
    fi
    echo "OK: $TOOL"
done
confirm

#############################################
# 10. Verify sysroot
#############################################
echo "=== Sysroot Verification ==="

SYSROOT="build/x-tools/debian_${DEBIAN_RELEASE}_trixie_arm64/aarch64-rpi4-linux-gnu/sysroot"

if [ ! -d "$SYSROOT" ]; then
    echo "ERROR: sysroot not found at: $SYSROOT"
    exit 1
fi

if [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: sysroot missing usr/include."
    exit 1
fi

if [ ! -d "$SYSROOT/usr/lib" ]; then
    echo "ERROR: sysroot missing usr/lib."
    exit 1
fi

echo "Using sysroot: $SYSROOT"
echo "Sysroot verified."
confirm

#############################################
# 11. Clean previous MAME build artifacts
#############################################
echo "=== Cleaning MAME Build Artifacts ==="
rm -rf build/src/mame
rm -rf build/output
rm -rf build/tmp
echo "MAME artifacts cleaned."
confirm

#############################################
# 12. Define SOURCES
#############################################
echo "=== Defining MAME SOURCES ==="

export SOURCES="trs/coco12.cpp,trs/coco3.cpp,trs/dragon.cpp,trs/mc10.cpp,atari/atari400.cpp,ti/ti99_4x.cpp,nintendo/dkong.cpp,commodore/c64.cpp,commodore/c128.cpp,msx/msx.cpp,sinclair/spectrum.cpp,trs/trs80.cpp,trs/trs80dt1.cpp,trs/trs80m2.cpp,trs/trs80m3.cpp,coleco/adam.cpp,coleco/coleco.cpp,apple/apple1.cpp,apple/apple2.cpp,apple/apple2e.cpp,apple/apple2gs.cpp,apple/apple3.cpp,trs/agvision.cpp,misc/nabupc.cpp,sharp/x68k.cpp,mattel/aquarius.cpp,mattel/aquarius_v.cpp,heathzenith/h19.cpp,tektronix/tek405x.cpp"

echo "SOURCES set to:"
echo "$SOURCES"
confirm

#############################################
# 13. Build MAME (ARM64 forced)
#############################################
echo "=== Running Project Compile Step ==="
echo "Command: ./mame-cross-compile.sh -o compile -r $DEBIAN_RELEASE -a arm64"
confirm

# Prepend toolchain to PATH
export PATH="$PROJECT_DIR/build/x-tools/debian_${DEBIAN_RELEASE}_trixie_arm64/bin:$PATH"

# Force cross-compile
export CROSS_BUILD=1
export OVERRIDE_CC=aarch64-rpi4-linux-gnu-gcc
export OVERRIDE_CXX=aarch64-rpi4-linux-gnu-g++
export OVERRIDE_LD=aarch64-rpi4-linux-gnu-ld
export OVERRIDE_AR=aarch64-rpi4-linux-gnu-ar
export OVERRIDE_STRIP=aarch64-rpi4-linux-gnu-strip

# Host tools
export HOSTCC=gcc
export HOSTCXX=g++
export HOSTLD=ld

./mame-cross-compile.sh -o compile -r "$DEBIAN_RELEASE" -a arm64
COMPILE_STATUS=$?

if [ $COMPILE_STATUS -ne 0 ]; then
    echo "ERROR: Project compile step failed."
    exit 1
fi

#############################################
# 14. Validate output
#############################################
echo "=== Validating Build Output ==="

if [ ! -f build/src/mame/mame ]; then
    echo "ERROR: MAME binary missing."
    exit 1
fi

echo "MAME binary found:"
ls -l build/src/mame/mame
echo

echo "Output archives:"
ls -l build/output || true
echo

#############################################
# 15. Verify MAME binary architecture
#############################################
echo "=== Verifying MAME Binary Architecture ==="

MAME_BIN="$PROJECT_DIR/build/src/mame/mame"

ARCH_INFO=$(file "$MAME_BIN")
echo "Binary reports: $ARCH_INFO"

if echo "$ARCH_INFO" | grep -qi "aarch64"; then
    echo "SUCCESS: MAME binary is ARM64 (aarch64)."
else
    echo "ERROR: MAME binary is NOT ARM64!"
    echo "This indicates the build system fell back to native x86_64."
    echo "Aborting to prevent packaging or distributing an incorrect binary."
    exit 1
fi

echo "Architecture verification complete."
echo
echo "=== Build Complete ==="
