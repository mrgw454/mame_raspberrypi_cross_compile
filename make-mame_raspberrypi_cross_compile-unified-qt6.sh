#!/bin/bash
set -euo pipefail

ENV_SUFFIX="qt6"
ARCH="arm64"
MODE="auto"
ASSUME_YES=0
PROJECT_DIR=""
SOURCE_DIR="${HOME}/source"
DEBIAN_RELEASE=""

usage() {
    cat <<'EOF'
Usage: make-mame_raspberrypi_cross_compile-unified-qt6.sh [options]

Build modes:
  --auto     Reuse the existing Qt6 tool environment if present, otherwise
             bootstrap it with download + prepare. This is the default.
  --fresh    Rebuild the Qt6 tool environment from scratch for this target,
             then build MAME.
  --reuse    Reuse the existing Qt6 tool environment and only rebuild MAME.

Options:
  --project-dir PATH  Use a specific repo checkout.
  --source-dir PATH   Base directory to clone into for --fresh when the repo
                      does not already exist. Default: $HOME/source
  --release N         Debian release number. Default: host major release.
  --yes               Run without confirmation prompts.
  -h, --help          Show this help text.
EOF
}

confirm() {
    if [ "${ASSUME_YES}" -eq 1 ]; then
        return
    fi
    printf "\nPress ENTER to continue..."
    read -r _
    printf "\n"
}

log_step() {
    printf "\n=== %s ===\n" "$1"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --auto)
            MODE="auto"
            ;;
        --fresh)
            MODE="fresh"
            ;;
        --reuse)
            MODE="reuse"
            ;;
        --project-dir)
            PROJECT_DIR="$2"
            shift
            ;;
        --source-dir)
            SOURCE_DIR="$2"
            shift
            ;;
        --release)
            DEBIAN_RELEASE="$2"
            shift
            ;;
        --yes)
            ASSUME_YES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "${DEBIAN_RELEASE}" ]; then
    DEBIAN_RELEASE=$(grep -oE '^[0-9]+' /etc/debian_version)
fi

ENV_NAME="debian_${DEBIAN_RELEASE}_trixie_arm64_${ENV_SUFFIX}"

log_step "Qt6 Build Settings"
echo "Mode: ${MODE}"
echo "Debian release: ${DEBIAN_RELEASE}"
echo "Environment name: ${ENV_NAME}"
confirm

log_step "Host Architecture Check"
SYSTEM_ARCH=$(dpkg --print-architecture)
echo "Detected architecture: ${SYSTEM_ARCH}"
if [[ "${SYSTEM_ARCH}" =~ arm64 ]]; then
    echo "ERROR: This project cannot run on ARM64 hosts."
    exit 1
fi
confirm

log_step "pyenv Verification"
export PYENV_ROOT="${HOME}/.pyenv"
export PATH="${PYENV_ROOT}/bin:${PATH}"

if ! command -v pyenv >/dev/null 2>&1; then
    echo "ERROR: pyenv not found. Install pyenv first."
    exit 1
fi

eval "$(pyenv init -)"

if ! pyenv versions --bare | grep -qx "3.11.2"; then
    echo "ERROR: Python 3.11.2 missing from pyenv."
    exit 1
fi

export PYENV_VERSION="3.11.2"
echo "Using Python: $(python3 --version)"
confirm

WRAPPER_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${PROJECT_DIR}" ]; then
    if [ -f "${WRAPPER_DIR}/mame-cross-compile.sh" ] && [ -d "${WRAPPER_DIR}/functions" ]; then
        PROJECT_DIR="${WRAPPER_DIR}"
        echo "Wrapper is running from the repo checkout."
    else
        PROJECT_DIR="${HOME}/source/mame_raspberrypi_cross_compile"
        echo "Wrapper is outside the repo; defaulting to ${PROJECT_DIR}"
    fi
fi

REPO_NAME="$(basename "${PROJECT_DIR}")"
TOOLCHAIN_DIR="${PROJECT_DIR}/build/x-tools/${ENV_NAME}/bin"
SYSROOT="${PROJECT_DIR}/build/x-tools/${ENV_NAME}/aarch64-rpi4-linux-gnu/sysroot"
TARGET_LIB_DIR="${PROJECT_DIR}/build/lib/${ENV_NAME}"

log_step "Project Location"
echo "Project directory: ${PROJECT_DIR}"
echo "Source base for fresh clone: ${SOURCE_DIR}"
confirm

clone_repo_if_needed() {
    if [ -d "${PROJECT_DIR}" ]; then
        return
    fi

    log_step "Cloning Project Repository"
    mkdir -p "${SOURCE_DIR}"
    if [ "${PROJECT_DIR}" != "${SOURCE_DIR}/${REPO_NAME}" ]; then
        echo "ERROR: --project-dir does not exist, and automatic clone only supports ${SOURCE_DIR}/${REPO_NAME}"
        exit 1
    fi

    (
        cd "${SOURCE_DIR}"
        git clone https://github.com/mrgw454/mame_raspberrypi_cross_compile.git "${REPO_NAME}"
    )
}

remove_qt6_environment() {
    log_step "Removing Existing Qt6 Environment"
    rm -rf "${PROJECT_DIR}/build/ctng/${ENV_NAME}"
    rm -rf "${PROJECT_DIR}/build/lib/${ENV_NAME}"
    rm -rf "${PROJECT_DIR}/build/pkg/${ENV_NAME}"
    rm -rf "${PROJECT_DIR}/build/x-tools/${ENV_NAME}"
    rm -f "${PROJECT_DIR}/build/log/download_${ENV_NAME}.log"
    rm -f "${PROJECT_DIR}/build/log/prepare_${ENV_NAME}.log"
    echo "Removed prior Qt6 tool environment for ${ENV_NAME}"
}

clean_mame_outputs() {
    log_step "Cleaning MAME Build Outputs"
    rm -rf "${PROJECT_DIR}/build/src/mame"
    rm -rf "${PROJECT_DIR}/build/output"
    rm -rf "${PROJECT_DIR}/build/tmp"
    echo "Removed previous MAME source/build/output directories"
}

run_project_step() {
    local operation="$1"
    log_step "Running ${operation}"
    (
        cd "${PROJECT_DIR}"
        MAME_DSTR_SUFFIX="${ENV_SUFFIX}" ./mame-cross-compile.sh -o "${operation}" -r "${DEBIAN_RELEASE}" -a "${ARCH}"
    )
}

clone_repo_if_needed

if [ ! -f "${PROJECT_DIR}/mame-cross-compile.sh" ] || [ ! -d "${PROJECT_DIR}/functions" ]; then
    echo "ERROR: Project directory does not look like a valid repo checkout: ${PROJECT_DIR}"
    exit 1
fi

case "${MODE}" in
    fresh)
        remove_qt6_environment
        clean_mame_outputs
        confirm
        run_project_step download
        confirm
        run_project_step prepare
        confirm
        ;;
    reuse)
        if [ ! -d "${TOOLCHAIN_DIR}" ] || [ ! -d "${TARGET_LIB_DIR}" ]; then
            echo "ERROR: --reuse requested, but the Qt6 tool environment is missing."
            echo "Expected:"
            echo "  ${TOOLCHAIN_DIR}"
            echo "  ${TARGET_LIB_DIR}"
            exit 1
        fi
        clean_mame_outputs
        confirm
        ;;
    auto)
        if [ -d "${TOOLCHAIN_DIR}" ] && [ -d "${TARGET_LIB_DIR}" ]; then
            echo "Found an existing Qt6 tool environment. Reusing it."
            clean_mame_outputs
            confirm
        else
            echo "Qt6 tool environment not found. Bootstrapping it with download + prepare."
            clean_mame_outputs
            confirm
            run_project_step download
            confirm
            run_project_step prepare
            confirm
        fi
        ;;
    *)
        echo "ERROR: Unsupported mode: ${MODE}"
        exit 1
        ;;
esac

log_step "Toolchain Verification"
if [ ! -d "${TOOLCHAIN_DIR}" ]; then
    echo "ERROR: Toolchain directory missing: ${TOOLCHAIN_DIR}"
    exit 1
fi
for tool in \
    aarch64-rpi4-linux-gnu-gcc \
    aarch64-rpi4-linux-gnu-g++ \
    aarch64-rpi4-linux-gnu-ar \
    aarch64-rpi4-linux-gnu-ld \
    aarch64-rpi4-linux-gnu-ld.gold \
    aarch64-rpi4-linux-gnu-strip
do
    if [ ! -x "${TOOLCHAIN_DIR}/${tool}" ]; then
        echo "ERROR: Missing toolchain binary: ${TOOLCHAIN_DIR}/${tool}"
        exit 1
    fi
    echo "OK: ${tool}"
done
confirm

log_step "Sysroot Verification"
if [ ! -d "${SYSROOT}" ]; then
    echo "ERROR: sysroot not found at: ${SYSROOT}"
    exit 1
fi
if [ ! -d "${SYSROOT}/usr/include" ] || [ ! -d "${SYSROOT}/usr/lib" ]; then
    echo "ERROR: sysroot is incomplete: ${SYSROOT}"
    exit 1
fi
echo "Using sysroot: ${SYSROOT}"
confirm

log_step "Running Qt6 MAME Compile"
(
    cd "${PROJECT_DIR}"
    export PATH="${TOOLCHAIN_DIR}:${PATH}"
    export MAME_DSTR_SUFFIX="${ENV_SUFFIX}"
    export CROSS_BUILD=1
    export OVERRIDE_CC=aarch64-rpi4-linux-gnu-gcc
    export OVERRIDE_CXX=aarch64-rpi4-linux-gnu-g++
    export OVERRIDE_LD=aarch64-rpi4-linux-gnu-ld
    export OVERRIDE_AR=aarch64-rpi4-linux-gnu-ar
    export OVERRIDE_STRIP=aarch64-rpi4-linux-gnu-strip
    export HOSTCC=gcc
    export HOSTCXX=g++
    export HOSTLD=ld
    ./mame-cross-compile.sh -o compile -r "${DEBIAN_RELEASE}" -a "${ARCH}"
)

log_step "Validating Build Output"
MAME_BIN="${PROJECT_DIR}/build/src/mame/mamed"

if [ ! -f "${MAME_BIN}" ]; then
    echo "ERROR: Expected MAME binary missing: ${MAME_BIN}"
    exit 1
fi

ARCH_INFO=$(file "${MAME_BIN}")
echo "Binary reports: ${ARCH_INFO}"
if ! echo "${ARCH_INFO}" | grep -qi "aarch64"; then
    echo "ERROR: Built binary is not ARM64."
    exit 1
fi

echo "MAME binary: ${MAME_BIN}"
LATEST_ARCHIVE=$(find "${PROJECT_DIR}/build/output" -maxdepth 1 -type f -name "mame_*_${ENV_NAME}.7z" | sort | tail -n 1)
if [ -n "${LATEST_ARCHIVE}" ]; then
    echo "Output archive: ${LATEST_ARCHIVE}"
else
    echo "No Qt6 output archive matching mame_*_${ENV_NAME}.7z was found."
    echo "Available archives:"
    ls -1 "${PROJECT_DIR}/build/output" 2>/dev/null || true
fi

echo
echo "=== Build Complete ==="
