# Cross compile MAME for ARM systems like Raspberry Pi on an x86_64 host

## About

The [MAME project](https://github.com/mamedev/mame) runs very well on Raspberry Pi 4 and 5 hardware running 64‑bit Raspberry Pi OS (a Debian derivative). Benchmarks:  
- https://stickfreaks.com/misc/raspberry-pi-mame-benchmarks

Compiling MAME directly on a Raspberry Pi can be slow and memory‑intensive. This project uses **crosstool‑NG** to build a complete cross‑compilation environment on a fast x86_64 machine, allowing you to build ARM64 MAME binaries quickly and reliably.

---

# Fixes and Improvements in This Fork (mrgw454)

This fork includes a series of **critical corrections** and **build‑system improvements** required to successfully cross‑compile MAME for ARM64 on Debian 13 for use with the CoCo-Pi Project.
[CoCo-Pi project](https://github.com/mrgw454/CoCo-Pi-Installer/tree/debian13)

HUGE thank you to Dan Mons for his project.  He has saved me countless hours of compiling MAME for the Raspberry Pi.

These fixes were developed through forensic troubleshooting and have been **verified only on Debian 13 (Trixie)**.  
Other distributions may work but are not currently supported.

This repository is the supported place for local Raspberry Pi cross-build changes.
The original upstream project should be treated as read-only for these fork-specific fixes.

## Summary of Fixes

- **Corrected two‑stage build process**  
  Host tools (such as *genie*) are now built with the host compiler, while MAME is built with the ARM64 cross‑toolchain.

- **Fixed broken Makefile invocation**  
  Removed a stray blank line that caused `-j32: command not found`.

- **Corrected success/failure logic**  
  The upstream script inverted the meaning of the exit code, causing failed builds to be reported as successful.

- **Removed incorrect OVERRIDE_LD usage**  
  Prevented the cross‑linker from being forced into the host‑tool build.

- **Eliminated dynamic patching**  
  All fixes are now committed directly into the repo; no runtime modifications are required.

- **Improved environment hygiene**  
  The wrapper script unsets polluted variables and enforces a clean PATH to prevent cross‑compiler contamination.

---

# Unified Wrapper Script

This fork includes a **unified build wrapper**:

```
make-mame_raspberrypi_cross_compile-unified.sh
```

This script is the **single source of truth** for:

- pyenv setup  
- Python version enforcement (3.11.2)  
- environment cleanup  
- toolchain verification  
- sysroot verification  
- artifact cleanup  
- MAME SOURCES selection  
- full compile and validation  

The wrapper script **defines the SOURCES list** for the MAME build.  
`functions/compile` no longer contains any hard‑coded SOURCES.

---

# Qt6 Wrapper Script

Current upstream MAME expects a Qt6-based Linux debugger build path.
To keep the existing Qt5-oriented environment intact while supporting new MAME builds for Raspberry Pi, this fork now includes a parallel Qt6 wrapper:

```bash
make-mame_raspberrypi_cross_compile-unified-qt6.sh
```

This wrapper uses a separate environment name:

```bash
debian_13_trixie_arm64_qt6
```

That environment keeps the Qt6 sysroot, toolchain outputs, and logs isolated from the older default path.

The Qt6 flow is designed around the two practical workflows used on this machine:

- rebuild everything from scratch for the Qt6 environment
- reuse the existing Qt6 tool environment and only refresh/build MAME

Internally, `functions/compile` now detects whether the target sysroot contains Qt5 or Qt6 and rewrites MAME's generated Qt makefiles to use the target sysroot libraries instead of host Qt library paths.

Just as important, this fork now validates the final MAME binary architecture instead of treating a completed compile as success by itself. The Qt6 path is only considered good if the produced `build/src/mame/mame` binary reports `aarch64`.

Current Qt6 ARM work also forces the target-stage MAME build through MAME's `linux_x64` release path. That sounds odd for an ARM target, but in current upstream MAME it is the path that expands to the generated `release64` makefile configuration and avoids the misleading host-style `scripts/...` archive path that can otherwise produce `x86_64` false positives.

The Qt6 path has now been verified end-to-end for current MAME `0.288` on Debian 13 `x86_64`:

- `download` completed
- `prepare` completed
- `compile` completed
- `build/src/mame/mame` is confirmed `aarch64`
- helper tools such as `chdman` and `castool` are also confirmed `aarch64`

Confirmed output:

```bash
build/output/mame_0.288_debian_13_trixie_arm64_qt6.7z
```

Earlier in the debugging process, a Qt6 compile produced a misleading `x86_64` top-level result. The current repo logic now treats that as a hard failure and validates the final `build/src/mame/mame` binary before calling the build successful.

The wrapper script is intended to live both in this repo and as a convenience copy in `$HOME/source-other/`.

---

# Packaging Script

This repo now also includes a repo-local package helper. A convenience copy can also live in `$HOME/scripts/`:

```bash
./create-MAME-package-crosstool-NG.sh /home/ron/source/mame_raspberrypi_cross_compile
```

To strip packaged ARM64 binaries before building the `.deb`:

```bash
./create-MAME-package-crosstool-NG.sh --strip /home/ron/source/mame_raspberrypi_cross_compile
```

If you keep the convenience copy in `$HOME/scripts/`, the same command becomes:

```bash
$HOME/scripts/create-MAME-package-crosstool-NG.sh --strip /home/ron/source/mame_raspberrypi_cross_compile
```

It packages the verified top-level build output from:

```bash
build/src/mame
```

Before creating the `.deb`, it checks that:

- `build/src/mame/mame` exists
- `build/src/mame/mame` reports `aarch64`
- non-ARM ELF files at the top level, such as a host-side `mamed`, are skipped automatically

When `--strip` is used, the helper strips only the copied ARM64 binaries inside the package staging tree. The original files in `build/src/mame` are left unchanged.

This avoids packaging a host `x86_64` false-positive build.

---

# Usage

To perform a full build on a clean system:

```bash
./make-mame_raspberrypi_cross_compile-unified.sh
```

To build with the new Qt6 path in automatic mode:

```bash
./make-mame_raspberrypi_cross_compile-unified-qt6.sh
```

To force a fresh Qt6 environment rebuild from scratch:

```bash
./make-mame_raspberrypi_cross_compile-unified-qt6.sh --fresh
```

To reuse the existing Qt6 tool environment and only rebuild MAME:

```bash
./make-mame_raspberrypi_cross_compile-unified-qt6.sh --reuse
```

To run without confirmation pauses:

```bash
./make-mame_raspberrypi_cross_compile-unified-qt6.sh --reuse --yes
```

The script will:

1. Clone the project if needed for a fresh build
2. Optionally rebuild the Qt6 `download` + `prepare` environment
3. Reuse or rebuild the Qt6 toolchain and sysroot as requested
4. Build host tools  
5. Build MAME for ARM64  
6. Validate the generated ARM64 binaries

Packaging is handled separately with `create-MAME-package-crosstool-NG.sh`, optionally using `--strip` to produce a smaller release `.deb`.
7. Validate the resulting binary  

All steps are automated and reproducible.

---

# Debian 13 Requirement

This fork has been **tested exclusively on Debian 13 (Trixie)**.  
The toolchain paths, sysroot layout, and package versions are aligned with Debian 13’s environment.

Other Debian releases or distributions may require adjustments.

---

# MAME forks supported

This project supports building the following versions of MAME:

- **MAME (mainline)**  
  https://github.com/mamedev/mame

- **GroovyMAME**  
  - Low‑resolution CRT support  
  - SwitchRes modeline generation  
  - Groovy_MiSTer low‑latency streaming  
  https://github.com/antonioginer/GroovyMAME

---

# Software versions supported

This repo aims to build the latest stable release of MAME on the latest stable release of Debian Linux.  
Currently that is **Debian 13 Trixie**.

Older Debian releases may work depending on:

- GCC version  
- glibc version  
- SDL2 version  
- Python version  

See `conf/list_ostools.txt` for details.

---

# Installation

- Requires an APT‑based Linux distro  
- Requires GCC 14 and Python 3.12 or older  
- GCC 15 and Python 3.13 break ct-ng  
- pyenv is recommended for Python version management  
- Clone the project:

```bash
sudo apt install -y git
git clone https://github.com/mrgw454/mame_raspberrypi_cross_compile.git
cd mame_raspberrypi_cross_compile
```

- Install prerequisites:

```bash
./install_prereqs.sh
```

---

# Options

`mame-cross-compile.sh` supports:

- `download` — download libraries  
- `prepare` — build toolchain  
- `compile` — build MAME  

See the original README for full argument details.

---

# Example usage

```bash
./mame-cross-compile.sh -o download -r 13 -a arm64
./mame-cross-compile.sh -o prepare -r 13 -a arm64
./mame-cross-compile.sh -o compile -r 13 -a arm64
```

Qt6 environment example:

```bash
MAME_DSTR_SUFFIX=qt6 ./mame-cross-compile.sh -o download -r 13 -a arm64
MAME_DSTR_SUFFIX=qt6 ./mame-cross-compile.sh -o prepare -r 13 -a arm64
MAME_DSTR_SUFFIX=qt6 ./mame-cross-compile.sh -o compile -r 13 -a arm64
```

The Qt6 wrapper above is the preferred entrypoint because it handles:

- `--fresh` for a clean Qt6 tool environment rebuild
- `--reuse` for new MAME builds against the existing Qt6 environment
- `--auto` to reuse when possible and bootstrap when missing

Output appears in:

```
build/output/
```

---

# Running MAME

Copy the `.7z` archive to your ARM64 system, extract, and run.

You may need:

```bash
sudo apt install -y libfreetype6 libsdl2-ttf-2.0-0 libsdl2-2.0-0 libqt6widgets6 libqt6gui6 libgl1
```

---

# Compile speed

Toolchain build: 30–60 minutes  
MAME build: depends on CPU count and RAM

General rule: **2 GB RAM per compile thread**

---

# Windows + WSL2

This project works under WSL2 with Ubuntu 24.04.  
Adjust `.wslconfig` to increase RAM allocation.

---

# What version of MAME should I run?

Always run the latest version.  
Modern MAME includes:

- performance improvements  
- accuracy fixes  
- dynarec for ARM64  
- bug fixes for classic games  

Older versions are not recommended.

---

# End of README
