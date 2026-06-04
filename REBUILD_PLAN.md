# Qt6 ARM64 Rebuild Plan

## Goal

Replace the fragile Qt6 ARM64 compile path with a simpler end-to-end pipeline that is reproducible from a clean start every time.

That replacement must automate all of the following:

- create the package/sysroot environment
- create the cross-toolchain
- build MAME for ARM64
- package the result as a `.deb`

No manual fixes are acceptable between stages.

## Why This Is Being Reworked

The current Qt6 path has shown that ARM64 MAME builds are possible, but the clean rebuild path exposed too many hidden assumptions:

- generated-makefile rewrites are brittle
- some include/library paths only worked because of prior build state
- Qt6, SDL2, ALSA, X11, and bgfx dependencies are not yet expressed in a single simple automated model

The project needs to move closer to:

- one clear environment model
- one clear toolchain model
- one clear compile model
- one clear package model

## Keep vs Replace

Keep:

- repo-managed `conf/useroptions.mak`
- ARM64 binary verification before packaging
- optional `--strip` packaging support
- stage-based structure: `download`, `prepare`, `compile`, `package`

Replace or simplify:

- brittle generated-makefile surgery where possible
- assumptions that depend on reused build artifacts
- any machine-specific examples or personal paths in docs
- any workflow that cannot succeed after deleting `build/src/mame`, `build/output`, and `build/tmp`

## Intended v2 Workflow

### 1. download

Create the target sysroot from Debian 13 ARM64 and Raspberry Pi packages.

Current source-of-truth package list for the Qt6 ARM64 environment:

```bash
conf/packages_debian_13_trixie_arm64_qt6
```

Must include all required build dependencies for the Qt6 SDL path, including:

- SDL2
- SDL2_ttf
- bzip2
- Qt6
- fontconfig
- PulseAudio
- ALSA
- X11 headers/libs
- OpenGL/EGL-related headers/libs needed by bgfx

Current observation from the clean-build investigation:

- the Qt6 package list already includes `libasound2-dev`
- the Qt6 package list now includes `libbz2-1.0` and `libbz2-dev`
- the Qt6 package list already includes `libx11-dev`
- therefore the recent `alsa/asoundlib.h` and `X11/Xlib.h` failures point to compile-path propagation problems, not just missing ARM64 sysroot packages

### 2. prepare

Create the cross-toolchain in a deterministic way.

The toolchain setup must:

- install `crosstool-ng` if needed
- build the selected ARM64 toolchain
- place outputs in the repo-managed build tree

Host-side tools also need to be treated as explicit prerequisites rather than hidden assumptions.

Current examples from the repo:

- `pyenv` with Python `3.11.2`
- `git`
- `curl`
- `wget`
- `dpkg`
- `apt-get`
- host Qt6 `moc`/`qmake6` tooling used by the debugger build path

Those should be documented and, where practical, checked automatically before the pipeline starts.

### 3. compile

Build MAME from a clean checkout.

The compile step must:

- install repo-managed `useroptions.mak`
- use explicit cross-toolchain variables
- use explicit sysroot include and library paths
- produce a real `aarch64` `build/src/mame/mame`
- avoid depending on stale generated files or prior partial builds

### 4. package

Build the final `.deb`.

The package step must:

- verify the produced binaries are `aarch64`
- optionally strip package-staging binaries
- leave original build outputs untouched
- produce a release package suitable for the CoCo-Pi installer repo

## Current Known Clean-Build Failure Areas

These were observed during the recent clean Qt6 rebuild work:

- SDL `_real_SDL_config.h` compatibility/header-path issues
- bgfx OpenGL header discovery
- ALSA header discovery in `portaudio`
- X11 header discovery in `bgfx`
- generated makefile rewrite fragility for toolchain/sysroot injection

These issues should be solved by a simpler consistent environment model, not by accumulating one-off exceptions forever.

## Immediate Next Steps

1. Treat `conf/packages_debian_13_trixie_arm64_qt6` as the environment baseline for v2.
2. Audit whether any additional EGL/OpenGL/X11-related development packages are genuinely missing from that list.
3. Evaluate whether the first reproducible Pi-targeted build should force `USE_QTDEBUG=0`.
4. Simplify the compile stage so the sysroot include/library paths are applied consistently without depending on fragile generated-makefile rewrites.
5. Resume clean-build testing only after the environment baseline and compile-path model are explicit.

## Candidate Simplification: Disable Qt Debugger For Target Builds

Upstream MAME's Linux build logic defaults `USE_QTDEBUG=1` unless it is explicitly disabled.

That matters because the current fragile path is heavily tied to debugger-specific generated makefiles such as:

- `qtdbg_sdl.make`
- `mame.make` Qt debugger link handling
- host `moc` discovery
- `qmake6`-derived include/library substitutions

For a Raspberry Pi runtime build, the portable Qt debugger may not be required.

If `USE_QTDEBUG=0` is acceptable for the Pi-targeted release build, it may allow a much simpler v2 compile path:

- fewer generated makefiles to patch
- less dependence on host Qt tooling during the target build
- a cleaner separation between "builds for Pi" and "debugger-enabled developer builds"

This should be treated as a deliberate design choice, not a hidden workaround.

Current branch decision:

- the first v2 target is a reproducible Raspberry Pi runtime build with `USE_QTDEBUG=0`
- debugger-enabled Qt6 cross-builds are a later follow-up, not the first success criterion

## Latest Compile-Path Findings

A cheap generate-only check against the current MAME tree confirmed a few important things for the `USE_QTDEBUG=0` direction:

- `USE_QTDEBUG=0` is being propagated into generated files
- `mame.make` becomes noticeably simpler on the runtime path and no longer obviously links the Qt debugger libraries
- `qtdbg_sdl.make` is still generated even when `USE_QTDEBUG=0`
- generated files may still contain host-biased `qmake6` header references and checkout-path `FORCE_INCLUDE` lines

That means the first runtime-focused rebuild should not assume that "Qt debugger disabled" removes every Qt-related generated file.

Instead, the v2 compile work should aim for this rule:

- only patch or account for the generated files that are actually required by the runtime build path
- avoid dragging debugger-specific rewrite logic into the first reproducible Pi build unless the runtime build proves it is still needed

Additional note:

- no committed repo scripts currently hardcode `/home/ron/...`
- the personal path showed up in generated MAME makefiles from the local checkout location, which is a build artifact concern rather than a committed-script concern

Latest compile-script progress:

- the generated-makefile handling has been split into:
  - an always-on cross-toolchain/sysroot rewrite for runtime builds
  - a separate Qt-debugger-specific rewrite used only when `USE_QTDEBUG=1`
- when `USE_QTDEBUG=0`, the compile script now prunes `qtdbg_sdl` from the generated top-level build graph
- when `USE_QTDEBUG=0`, the compile script also removes `libqtdbg_sdl.a` from `mame.make`

That keeps the first Pi runtime target closer to the real requirement:

- build the Pi runtime
- do not build or link the optional Qt debugger pieces unless a later debugger-focused path explicitly asks for them

## Current Proven Runtime Milestones

The simplified `USE_QTDEBUG=0` runtime path has now been proven much further than the earlier clean-build attempts.

Successful generated/runtime-stage results:

- generated `gmake-linux` files can be regenerated cleanly with `USE_QTDEBUG=0`
- generated top-level runtime graph can be pruned away from `qtdbg_sdl`
- cross-toolchain assignments are landing in generated makefiles
- sysroot include/library paths are landing in generated runtime makefiles

Successful release libraries from the current runtime path:

- `libportaudio.a`
- `libbgfx.a`
- `libosd_sdl.a`
- `libfrontend.a`
- `libmame_mame.a`

That means the recent blockers are no longer the earlier SDL / ALSA / X11 / GL header-path failures.

## Proven Scripted Build State

The branch has now moved beyond manual resume-only validation.

Proven scripted results:

- `./make-mame_raspberrypi_cross_compile-unified-qt6.sh --reuse --yes`
  - removes prior `build/src/mame`, `build/output`, and `build/tmp`
  - clones a fresh MAME checkout
  - completes the ARM64 Qt6 runtime compile
  - verifies `build/src/mame/mame` as `aarch64`
  - creates `build/output/mame_0.288_debian_13_trixie_arm64_qt6.7z`
- `./create-MAME-package-crosstool-NG.sh /path/to/mame_raspberrypi_cross_compile`
  - packages the current ARM64 build successfully
  - creates `build/src/mame/mameCoCoPi-0.288-crosstool-NG-1.deb`

Additional proven binaries from the current scripted compile path:

- `build/src/mame/chdman`
- `build/src/mame/castool`

Those now validate as `aarch64` as well.

## Latest Success State

The most recent direct runtime probe progressed all the way to the final link and then failed only because the Qt6 ARM64 sysroot baseline was missing bzip2.

That gap has now been fixed in automation:

- `conf/packages_debian_13_trixie_arm64_qt6` now includes:
  - `libbz2-1.0`
  - `libbz2-dev`
- those two ARM64 packages were downloaded into the existing local sysroot and extracted under:
  - `build/lib/debian_13_trixie_arm64_qt6`

After adding `libbz2`, the exact resume command completed successfully:

```bash
make -C build/src/mame/build/projects/sdl/mame/gmake-linux config=release64 mame -j1
```

The resulting runtime binary is now present and verified:

```bash
build/src/mame/mame
```

- `file` reports it as an `ELF 64-bit LSB executable, ARM aarch64`
- current local size is about `118 MB`

Packaging also completed successfully with the existing stripped-package helper:

```bash
./create-MAME-package-crosstool-NG.sh --strip /path/to/mame_raspberrypi_cross_compile
```

Current successful artifact:

```bash
build/src/mame/mameCoCoPi-0.288-crosstool-NG-1.deb
```

- current local package size is about `33 MB`

Important nuance:

- this success was proven by resuming the already-generated runtime build graph after updating the package baseline
- that earlier gap has now been closed for the `--reuse` wrapper compile path
- that later gap has now also been closed by a successful full `--fresh` wrapper-level run

## Full Fresh Validation

The full from-scratch wrapper path has now been proven with:

```bash
./make-mame_raspberrypi_cross_compile-unified-qt6.sh --fresh --yes
```

That successful run verified:

- sysroot package download from scratch
- cross-toolchain creation from scratch
- clean MAME source checkout
- clean ARM64 Qt6 runtime compile
- output archive creation
- final ARM64 validation of:
  - `build/src/mame/mame`
  - `build/src/mame/chdman`
  - `build/src/mame/castool`

The resulting `mame` binary has also been tested successfully on the Raspberry Pi 500 target.

At this point, the branch is proven for:

- full environment rebuild
- full toolchain rebuild
- clean scripted compile
- separate package creation
- real target runtime validation

## Current Next Step

The remaining project-management step is no longer technical validation. It is branch promotion:

- keep `main` as the single primary branch
- optionally fold packaging into the wrapper if you want one-command `download` + `prepare` + `compile` + `package`

## Working Rule

If a required fix cannot be automated in the repo scripts, it is not an acceptable fix.

## Branch Strategy

The simplified Qt6 rebuild work is being isolated on a dedicated branch first.

Once the replacement path is working cleanly end-to-end, that branch can replace the current main working path.
