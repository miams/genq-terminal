# CI Build History — genq-terminal (Ghostty Fork)

Chronological record of every GitHub Actions build failure for the
`build-ghostty.yml` workflow (triggered from `miams/genq`), the root
cause of each failure, the remedy applied, and the result.

The builds target the `genq` branch of `miams/genq-terminal`, which is
pinned to Ghostty **v1.3.1** with cosmetic/branding patches on top.

---

## Build #1 — 2026-03-31

**Commit:** `fix(ci): install Zig 0.15.2 directly from ziglang.org/download`
**Run ID:** 23823986820
**Result:** FAILURE

### Failure
First attempt at a CI build for genq-terminal. The workflow checked out
`main` of `genq-terminal` instead of the `genq` branch. The `main` branch
is a sync of upstream Ghostty which has moved beyond v1.3.1 and requires
Zig **0.16.0-dev** (nightly). The build failed immediately with:

```
error: minimum zig version not met
  required: 0.16.0-dev.XXXX
  found: 0.15.2
```

### Remedy
Changed the `ref:` in the checkout step from `main` to `genq`.

### Result
Not sufficient — further failures followed.

---

## Builds #2–4 — 2026-04-07

**Commits:** `Use Nix to build Ghostty in CI`, `Build Ghostty from genq-terminal main`
**Run IDs:** 24090163812, 24091513812, 24107437474
**Result:** FAILURE

### Failure
Multiple attempts with different Nix configurations and branch references.
These runs were still inadvertently pulling the wrong branch or using
workflow configurations that didn't properly reach the Swift build step.
The DockTilePlugin Swift compilation failed, but the raw error was
swallowed by the Zig build orchestrator which only reports:

```
+- xcodebuild failure
** BUILD FAILED **
```

No Swift error text was visible in the logs at this stage.

### Remedy
Began systematic investigation. Confirmed `ref: genq` was set. Added
diagnostic steps to expose raw xcodebuild output.

---

## Build #5 — 2026-04-09 (early)

**Commit:** `fix(ci): build genq-terminal from genq branch (v1.3.1)`
**Run ID:** 24211695730
**Result:** FAILURE

### Failure
Confirmed the correct `genq` branch was being checked out, but the
DockTilePlugin Xcode target continued to fail. Investigation of the
Xcode project file (`project.pbxproj`) revealed:

```
8193244C2F24E6C000A9ED8F = {
    CreatedOnToolsVersion = 26.2;
};
```

The DockTilePlugin target was created with **Xcode 26.2**. Its source
files are wired through `PBXFileSystemSynchronizedBuildFileExceptionSet`
— a project format from the Xcode 26 era. CI was using Xcode 16.4
(the default on the `macos-latest` = macOS 15 runner), which does not
correctly interpret this project format. The target compiled with no
source files and failed at link time.

Separately, `DockTilePlugin.swift` on the upstream-synced `genq` branch
contained a `#available(macOS 26.0, *)` block using a macOS 26-only
`NSWorkspace.setIcon(nil, ...)` overload. Xcode 16.4's SDK doesn't have
this API and would reject it.

### Remedy
1. **Cherry-pick to `genq` branch (genq-terminal):** Removed the
   `#available(macOS 26.0, *)` block from `DockTilePlugin.swift`,
   keeping only the compatible `else` branch. Commit: `a418551de`.

2. **Switch Xcode on CI:** Added a "Select Xcode" step that picks the
   newest Xcode on the runner:
   ```bash
   xcode=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)
   sudo xcode-select --switch "$xcode/Contents/Developer"
   ```

---

## Build #6 — 2026-04-09

**Commit:** `fix(ci): select Xcode 26.3 to match local build environment`
**Run ID:** 24213510509
**Result:** FAILURE

### Failure
Same DockTilePlugin failure. Investigation confirmed commit `a418551de`
was correctly checked out (DockTilePlugin.swift no longer contained the
macOS 26 block), but the build still failed. The Xcode selection step
was not yet in place.

### Remedy
Added "Select Xcode" step (see Build #5 remedy above) and pushed
`fix(ci): select Xcode 26.3 to match local build environment`.

---

## Builds #7–8 — 2026-04-09

**Commits:** `diag: expose xcodebuild Swift errors`, `fix(ci): restore clean build workflow`
**Run IDs:** 24214755916, 24215630500, 24216575773
**Result:** FAILURE

### Failure
After adding the Xcode selection step, CI confirmed Xcode 26.3 was being
selected. DockTilePlugin compilation still failed. Diagnostic runs
added `continue-on-error: true` and ran xcodebuild directly to capture
the raw Swift error. The raw errors were not DockTilePlugin Swift errors
— the Swift code itself was fine. These runs were intermediate
diagnostic iterations.

### Remedy
Reverted to a clean workflow after diagnostics confirmed the Swift code
was not the problem. Continued investigation.

---

## Build #9 — 2026-04-09

**Commit:** `ci: select latest Xcode to fix DockTilePlugin build on macOS`
**Run ID:** 24217380966
**Runner:** `macos-latest` = macOS 15.7.4
**Result:** FAILURE

### Failure
Xcode 26.3 was successfully selected (confirmed in logs:
`Selecting Xcode: /Applications/Xcode_26.3.0.app`, `Xcode 26.3 / Build version 17C529`).

The DockTilePlugin compiled successfully. A **new and different failure**
appeared at step 283/286:

```
CompileAssetCatalogVariant thinned
  .../macos/build/ReleaseLocal/Ghostty.app/Contents/Resources
  .../images/Ghostty.icon
  .../macos/Assets.xcassets
** BUILD FAILED ** (exit code 65)
```

**Root cause:** `images/Ghostty.icon` is an **Apple IconComposer package**
(`folder.iconcomposer.icon` — a directory with `icon.json` defining a
layered, gradient-based icon with blend modes and effects). This format
was introduced in macOS 26. The `actool` (Asset Catalog Compiler) in
Xcode 26.3 can parse the format, but it requires **macOS 26 system
frameworks** to render the layer composition. The CI runner was macOS 15,
which does not have those frameworks. Exit code 65 = compilation error.

Local builds succeeded because the local machine runs macOS 26.

### Remedy
Changed the CI runner from `macos-latest` (macOS 15) to `macos-26`.

---

## Build #10 — 2026-04-09

**Commit:** `ci: use macos-26 runner to fix IconComposer icon compilation`
**Run ID:** 24217978047
**Runner:** `macos-26-arm64` = macOS 26.3 (25D125)
**Result:** FAILURE

### Failure
The `macos-26` runner resolved the `actool` / `Ghostty.icon` failure.
However, a **new failure** appeared immediately at the start of the
Zig build step:

```
error: undefined symbol: __availability_version_check
    note: referenced by libcompiler_rt.a:___isPlatformVersionAtLeast
error: undefined symbol: _abort
error: undefined symbol: _arc4random_buf
error: undefined symbol: _bzero
error: undefined symbol: _clock_gettime
error: undefined symbol: _dispatch_queue_create
error: undefined symbol: _free
error: undefined symbol: _malloc
... (22 symbols total)
```

**Root cause:** The workflow used `nix develop -c zig build`. Inside
`nix develop`, the environment is isolated — Nix sets `SDKROOT` to
point to its own macOS SDK (built for macOS 15, from the `nixpkgs`
channel snapshot). Zig 0.15.2's embedded LLVM linker uses `SDKROOT`
to locate system library TBD stubs (`.tbd` files for `libSystem.B.dylib`,
`libdispatch.dylib`, etc.). The Nix-provided macOS 15 SDK's TBD stubs
were either absent or structured differently from what macOS 26's linker
environment expects, so all basic C library symbols were unresolved.

The `nix develop` isolation was the culprit — **not Zig 0.15.2 itself**.
The local build works on macOS 26 because Zig is installed via `zigup`
(directly from ziglang.org) and runs without Nix, giving it access to
the real macOS 26 SDK stubs.

The Nix devShell existed only to provide Zig (and dev tools like
swiftlint, vttest). SwiftLint is already a no-op on GitHub Actions
(the build phase script exits immediately when `$GITHUB_ACTIONS` is
set). No other Nix packages are required — Zig's build system fetches
and compiles its own C dependencies from source.

### Remedy
Removed Nix from the macOS CI build entirely. Replaced `nix develop -c`
with a direct Zig installation from ziglang.org (same source as `zigup`):

```yaml
- name: Install Zig 0.15.2
  run: |
    ZIG_VERSION="0.15.2"
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-macos-${ZIG_VERSION}.tar.xz"
    curl -fsSL "$ZIG_URL" | tar -xJ -C /tmp
    sudo mv "/tmp/zig-aarch64-macos-${ZIG_VERSION}" /usr/local/zig
    sudo ln -sf /usr/local/zig/zig /usr/local/bin/zig
    zig version

- name: Build
  working-directory: genq-terminal
  run: zig build -Doptimize=ReleaseFast
```

**Commit:** `ci(macos): install Zig directly, skip Nix on macos-26`
**Run ID:** 24218415133
**Result:** FAILURE — see Build #11.

---

## Build #11 — 2026-04-09

**Commit:** `ci(macos): install Zig directly, skip Nix on macos-26`
**Run ID:** 24218415133
**Runner:** `macos-26-arm64` = macOS 26.3
**Result:** FAILURE

### Failure
The Install Zig step failed immediately:

```
curl: (22) The requested URL returned error: 404
mv: rename /tmp/zig-macos-aarch64-0.15.2 to /usr/local/zig: No such file or directory
```

**Root cause:** Wrong filename in the download URL. The workflow used
`zig-macos-aarch64-0.15.2.tar.xz` (platform-then-architecture), but
ziglang.org names arm64 macOS tarballs `zig-aarch64-macos-0.15.2.tar.xz`
(architecture-then-platform). Confirmed via `https://ziglang.org/download/index.json`.

The correct URL is:
```
https://ziglang.org/download/0.15.2/zig-aarch64-macos-0.15.2.tar.xz
```

### Remedy
Corrected the filename in the workflow URL and `mv` target:
- `zig-macos-aarch64-${ZIG_VERSION}` → `zig-aarch64-macos-${ZIG_VERSION}`

**Commit:** `fix(ci): correct Zig download URL — aarch64-macos not macos-aarch64`

---

## Build #12 — 2026-04-09 ✓ FIRST SUCCESS

**Commit:** `fix(ci): correct Zig download URL — aarch64-macos not macos-aarch64`
**Run ID:** 24218831413
**Runner:** `macos-26-arm64` = macOS 26.3 (25D125), Xcode 26.2 (default)
**Duration:** 10m 53s
**Result:** SUCCESS — both macOS and Linux jobs passed.

### What worked
- macOS: Zig 0.15.2 installed directly from ziglang.org, `zig build -Doptimize=ReleaseFast` ran against the system macOS 26 SDK. App signed, packaged as DMG, uploaded as artifact.
- Linux: Nix + `nix develop -c zig build -Doptimize=ReleaseFast -Dapp-runtime=gtk` (Nix works fine on Linux where SDK isolation is not an issue). Packaged as `.tar.gz`, uploaded as artifact.

### Remaining warning (non-blocking)
```
Node.js 20 actions are deprecated. The following actions are running on
Node.js 20: actions/checkout@v4, actions/upload-artifact@v4.
Actions will be forced to run with Node.js 24 by default starting
June 2nd, 2026.
```

Addressed in the follow-up commit by adding `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`
to the workflow-level `env:` block.

---

## Working build configuration (as of 2026-04-09)

### `miams/genq` — `.github/workflows/build-ghostty.yml`

```yaml
name: Build Ghostty

on:
  workflow_dispatch:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:

  build-macos:
    name: Build macOS (Ghostty)
    runs-on: macos-26          # macOS 26 required for actool IconComposer support

    steps:
      - name: Checkout genq
        uses: actions/checkout@v4

      - name: Checkout genq-terminal (private, via deploy key)
        uses: actions/checkout@v4
        with:
          repository: miams/genq-terminal
          ref: genq             # MUST be genq — main requires Zig nightly
          ssh-key: ${{ secrets.GENQ_TERMINAL_DEPLOY_KEY }}
          path: genq-terminal

      - name: Install Zig 0.15.2
        run: |
          # Direct install (NOT via Nix) — Nix isolates SDKROOT to macOS 15,
          # causing undefined symbol linker errors on the macOS 26 runner.
          ZIG_VERSION="0.15.2"
          ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-macos-${ZIG_VERSION}.tar.xz"
          curl -fsSL "$ZIG_URL" | tar -xJ -C /tmp
          sudo mv "/tmp/zig-aarch64-macos-${ZIG_VERSION}" /usr/local/zig
          sudo ln -sf /usr/local/zig/zig /usr/local/bin/zig
          zig version

      - name: Build
        working-directory: genq-terminal
        run: zig build -Doptimize=ReleaseFast

      - name: Sign
        working-directory: genq-terminal
        run: |
          xattr -cr zig-out/Ghostty.app
          codesign --force --deep --sign - "zig-out/Ghostty.app"

      - name: Package DMG
        working-directory: genq-terminal
        run: |
          mkdir -p /tmp/genq-dmg
          cp -r "zig-out/Ghostty.app" "/tmp/genq-dmg/GenQuery Terminal.app"
          ln -s /Applications /tmp/genq-dmg/Applications
          hdiutil create \
            -volname "GenQuery Terminal" \
            -srcfolder /tmp/genq-dmg \
            -ov -format UDZO \
            -o "$GITHUB_WORKSPACE/GenQuery-Terminal-macOS.dmg"

      - name: Upload DMG
        uses: actions/upload-artifact@v4
        with:
          name: GenQuery-Terminal-macOS
          path: GenQuery-Terminal-macOS.dmg
          retention-days: 14

  build-linux:
    name: Build Linux (Ghostty)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout genq
        uses: actions/checkout@v4

      - name: Checkout genq-terminal (private, via deploy key)
        uses: actions/checkout@v4
        with:
          repository: miams/genq-terminal
          ref: genq
          ssh-key: ${{ secrets.GENQ_TERMINAL_DEPLOY_KEY }}
          path: genq-terminal

      - name: Install Nix
        uses: cachix/install-nix-action@v31
        with:
          nix_path: nixpkgs=channel:nixos-unstable

      - name: Build
        working-directory: genq-terminal
        run: nix develop -c zig build -Doptimize=ReleaseFast -Dapp-runtime=gtk

      - name: Package
        working-directory: genq-terminal
        run: |
          tar -czf "$GITHUB_WORKSPACE/GenQuery-Terminal-Linux.tar.gz" \
            -C zig-out/bin ghostty

      - name: Upload Linux artifact
        uses: actions/upload-artifact@v4
        with:
          name: GenQuery-Terminal-Linux
          path: GenQuery-Terminal-Linux.tar.gz
          retention-days: 14
```

---

## Invariants — must all be true for a successful build

| Requirement | Why |
|---|---|
| Runner: **`macos-26`** | `actool` requires macOS 26 system frameworks to compile `images/Ghostty.icon` (Apple IconComposer format introduced in macOS 26) |
| Zig installed **directly from ziglang.org**, not via Nix | Nix isolates `SDKROOT` to its own macOS 15 SDK; Zig's embedded LLVM linker then can't find macOS 26 system library TBD stubs, causing 22 undefined symbol errors |
| Zig tarball filename: **`zig-aarch64-macos-VERSION`** | ziglang.org uses architecture-first naming (`aarch64-macos`), not platform-first (`macos-aarch64`) |
| Zig version: **0.15.2** | Pinned as `minimum_zig_version` in `build.zig.zon`; upstream main now requires Zig nightly |
| `genq-terminal` ref: **`genq` branch** | `main` tracks upstream Ghostty and requires Zig nightly; `genq` is pinned to v1.3.1 |
| Xcode: **26.x** | DockTilePlugin target has `CreatedOnToolsVersion = 26.2`; Xcode 16.x cannot parse the `PBXFileSystemSynchronizedBuildFileExceptionSet` project format |
| Actions Node.js: **24** | `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` prevents deprecation warnings and prepares for the 2026-06-02 forced cutover |

## genq-terminal `genq` branch patches (on top of v1.3.1)

| Commit | File | Change | Reason |
|---|---|---|---|
| `a418551de` | `macos/Sources/Features/Custom App Icon/DockTilePlugin.swift` | Removed `#available(macOS 26.0, *)` block | macOS 26-only `NSWorkspace.setIcon(nil, ...)` overload causes a compile error when building on any Xcode SDK that predates macOS 26; the `else` branch is functionally equivalent |
| `f11a05111` | `docs/ci-build-history.md` | Created this document | — |
