#!/bin/bash
set -euo pipefail

scriptname=$(basename "$0")
project_root=$(pwd)
repo_arg=""
strip_binaries=0

usage() {
    cat <<EOF
Usage:
  ./${scriptname} [--strip] <repo checkout>

Example:
  ./${scriptname} /path/to/mame_raspberrypi_cross_compile
  ./${scriptname} --strip /path/to/mame_raspberrypi_cross_compile

Options:
  --strip     Strip packaged ARM64 binaries before building the .deb.
              This only affects the package staging copy, not the original
              build outputs in the repo checkout.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strip)
            strip_binaries=1
            ;;
        -h|--help|--h)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -n "${repo_arg}" ]; then
                echo "ERROR: Multiple repo checkouts provided."
                usage
                exit 1
            fi
            repo_arg="$1"
            ;;
    esac
    shift
done

if [ -z "${repo_arg}" ]; then
    echo "No repo checkout provided."
    usage
    exit 1
fi

repo_dir=$(realpath "${repo_arg}")
mamefolder="${repo_dir}/build/src/mame"
strip_tool=""

find_strip_tool() {
    find "${repo_dir}/build/x-tools" -type f -path '*/bin/*-strip' | sort | head -n 1
}

if [ ! -d "${mamefolder}" ]; then
    echo "ERROR: MAME build folder does not exist: ${mamefolder}"
    exit 1
fi

mame_bin="${mamefolder}/mame"
if [ ! -f "${mame_bin}" ]; then
    echo "ERROR: Expected MAME runtime binary missing: ${mame_bin}"
    exit 1
fi

arch_info=$(file "${mame_bin}")
echo "MAME binary: ${arch_info}"
if ! echo "${arch_info}" | grep -qi "aarch64"; then
    echo "ERROR: Refusing to package a non-aarch64 MAME binary."
    exit 1
fi

cd "${repo_dir}/build/src/mame"

mamevergit=$(git tag | grep '^mame' | tail -n1)
if [ -z "${mamevergit}" ]; then
    echo "ERROR: Could not determine MAME version tag."
    exit 1
fi

mamever=${mamevergit:(-3)}
pkg_name="mamecocopi"
pkg_version="0.${mamever}-1"
deb_filename="mameCoCoPi-0.${mamever}-crosstool-NG-1.deb"
pkg_folder="mameCoCoPi-0.${mamever}-crosstool-NG-1"
systemtype="arm64"

echo "Packaging version 0.${mamever} for ${systemtype}"
if [ "${strip_binaries}" -eq 1 ]; then
    strip_tool=$(find_strip_tool)
    if [ -z "${strip_tool}" ]; then
        echo "ERROR: --strip was requested, but no cross strip tool was found under ${repo_dir}/build/x-tools"
        exit 1
    fi
    echo "Package staging binaries will be stripped with: ${strip_tool}"
else
    echo "Package staging binaries will not be stripped."
fi

rm -f "${pkg_folder}.deb"
rm -rf "${pkg_folder}"

mkdir -p "${pkg_folder}/DEBIAN"
mkdir -p "${pkg_folder}/opt/mame-0.${mamever}"

cat > "${pkg_folder}/DEBIAN/control" <<EOF
Package: ${pkg_name}
Version: ${pkg_version}
Section: base
Priority: optional
Architecture: ${systemtype}
Depends:
Maintainer: Ron Klein <ron@kdomain.org>
Description: MAME 0.${mamever} for the CoCo-Pi Project
 Coco-Pi Project:
 http://coco-pi.com
 MAME Project:
 https://www.mamedev.org/
EOF

for folder in artwork bgfx ctrlr docs hash hlsl ini language plugins roms samples; do
    if [ -d "${mamefolder}/${folder}" ]; then
        cp -r "${mamefolder}/${folder}" "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}"
    fi
done

while IFS= read -r top_file; do
    base=$(basename "${top_file}")
    info=$(file -b "${top_file}")

    case "${info}" in
        *ELF*)
            if echo "${info}" | grep -qi "aarch64"; then
                cp "${top_file}" "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}/"
            else
                echo "Skipping non-aarch64 ELF: ${base}"
            fi
            ;;
        *)
            cp "${top_file}" "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}/"
            ;;
    esac
done < <(find "${mamefolder}" -maxdepth 1 -type f)

rm -f "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}/useroptions.mak"
rm -f "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}/dist.mak"
rm -f "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}/makefile"

if [ "${strip_binaries}" -eq 1 ]; then
    while IFS= read -r staged_file; do
        file_info=$(file -b "${staged_file}")
        if echo "${file_info}" | grep -q "ELF" && echo "${file_info}" | grep -qi "aarch64"; then
            echo "Stripping $(basename "${staged_file}")"
            "${strip_tool}" "${staged_file}"
        fi
    done < <(find "${mamefolder}/${pkg_folder}/opt/mame-0.${mamever}" -maxdepth 1 -type f)
fi

dpkg-deb --build "${mamefolder}/${pkg_folder}"

if [ -f "${mamefolder}/${deb_filename}" ]; then
    echo "MAME package ${deb_filename} built successfully."
else
    echo "ERROR: MAME package build failed."
    exit 1
fi

echo "Done."
