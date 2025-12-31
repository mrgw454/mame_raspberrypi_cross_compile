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

# Usage

To perform a full build on a clean system:

```bash
./make-mame_raspberrypi_cross_compile-unified.sh
```

The script will:

1. Clone the project (if missing)  
2. Download and build the toolchain  
3. Prepare the sysroot  
4. Build host tools  
5. Build MAME for ARM64  
6. Package the output  
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

Output appears in:

```
build/output/
```

---

# Running MAME

Copy the `.7z` archive to your ARM64 system, extract, and run.

You may need:

```bash
sudo apt install -y libfreetype6 libsdl2-ttf-2.0-0 libsdl2-2.0-0 libqt5widgets5 libqt5gui5 libgl1
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
