# Build outputs

For local Windows/Debian builds, use the shared entrypoints described in
[README.build.md](../README.build.md). They default to the workspace-level
`../artifacts/`, with `rustdesk/{cache,build,publish}/`,
`rustdesk-api/{cache,build,publish}/` and `rustdesk-api-web/{cache,build,publish}/`.
`--artifacts-root` or `RUSTDESK_ARTIFACTS_DIR` selects the shared root; on this
machine use `C:/Git/RustDesk/artifacts` (`T:` is an alias). The client and server
are built from disposable source copies under this root, so their internal
relative `artifacts/` paths also remain physically inside it. Shared SDKs stay
in `artifacts/tools/`.

The paths below describe lower-level direct builds and upstream packaging/CI.
Those keep their existing repository-relative paths; invoking them directly
can recreate repository-local `artifacts` directories.

Each repository keeps Rust build products in its own `artifacts/target/`, configured in `.cargo/config.toml`. This also applies when Cargo runs inside a child directory. No user or system Cargo setting is changed. `CARGO_TARGET_DIR` and Cargo's `--target-dir` still override this default.

| Output | Location relative to this repository |
| --- | --- |
| Cargo binaries, libraries, objects and test executables | `artifacts/target/` |
| Packages and portable installers produced by `build.py` | `artifacts/publish/` |
| Debian package staging | `flutter/artifacts/tmpdeb/` for Flutter/package mode; `artifacts/tmpdeb/` for legacy Cargo bundle mode |
| Downloaded native packaging resources | `artifacts/resources/` |
| Pinned libdrmtap checkout and Meson output | `artifacts/third_party/libdrmtap/` |
| Arch package build work | `artifacts/makepkg/` |
| MSI package/native custom action binaries and intermediates | `artifacts/msi/bin/`, `artifacts/msi/obj/` |
| Android/iOS symbol files from the build scripts | `artifacts/split-debug-info/` |
| CI Windows release staging | `artifacts/staging/` |

For example, run `cargo build --release` from this repository, then use `artifacts/target/release/rustdesk` (`.exe` on Windows). Run `python build.py --flutter` with the platform prerequisites installed to produce the normal platform build/package. CI cache, linking, signing and upload paths use the same Cargo directory.

The `rustdesk-server` and `hbb_common` sibling repositories use their own `artifacts/target/` directories. Server UI assets are written to `rustdesk-server/artifacts/ui/dist/`; installer staging, signed binaries and Debian packaging use that repository's `artifacts/staging/`, `artifacts/publish/` and `artifacts/debian-build/`.

The ignore rule `artifacts/` ignores directories with that name at every depth, including Flutter package staging. Synchronization tools should exclude directories named `artifacts` throughout the workspace as well; Git ignore rules do not configure external synchronization software. Shared portable SDKs and local test harnesses can live in the workspace-level `artifacts/tools/`.

## Tool-managed paths

Some build inputs and working directories retain the paths required by their tools or existing compile-time includes:

- Flutter uses `flutter/build/` and `flutter/.dart_tool/`. Its native build directory comes from the user's Flutter configuration, which this project does not change. There is no project-local `flutter build --build-dir` flag. See the [Flutter build directory implementation](https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/build_info.dart) and [Flutter config command](https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/commands/config.dart).
- Flutter platform support files include `ephemeral/`, `.plugin_symlinks/`, generated CMake/Xcode configuration, CocoaPods `Pods/` and Android `.gradle/`/`jniLibs/`. Native Rust libraries are copied there as packaging inputs. These paths and generated Dart/Rust bridge files are already ignored where appropriate.
- The portable packer includes `libs/portable/data.bin` and `app_metadata.toml` directly at compile time. The Windows resource input `Runner.res` also stays beside that project. The compiled packer itself is in `artifacts/target/`.
- MSI preprocessing creates WiX resources in `res/msi/`, and NuGet restores its legacy package inputs under `res/msi/packages/`. The compiled MSI and C++ outputs are redirected separately.
- AppImage/Flatpak packaging keeps its existing recipe-relative staging and downloaded modules. RPM's build tree, Cargo registries and SDK/package caches use the tool's existing cache configuration outside these repositories.

These disposable generated files may be removed when no build is running; the corresponding tools regenerate them. Keep tracked sources, submodules, package lockfiles and manually supplied signing material.

## Regression surface

The output-path commit changes build and packaging behavior only. The three .cargo/config.toml files select the new Cargo target directory. Client build.py, entrypoint.sh, flutter/build_android.sh, flutter/build_fdroid.sh, and flutter/build_ios.sh produce or consume the relocated outputs. Flutter's Windows/Linux CMakeLists.txt and iOS/macOS Xcode projects consume the relocated native libraries. res/msi/CustomActions/CustomActions.vcxproj and Directory.Build.props select MSI bin/obj directories; the two non-Flutter RPM specs and the Enigo debugger launch configuration consume the new Cargo path. Client workflows ci.yml, flutter-build.yml, playground.yml and server workflow build.yaml update caches, packaging, signing and uploads together. Server ui/html/vite.config.js, ui/tauri.conf.json and ui/setup.nsi keep UI assets and installer staging consistent. README examples, translated docs/README-*.md, server debian/README.source and MSI instructions show the same paths. The three .gitignore files ignore artifacts at every depth. Application session/authentication behavior is unchanged by this commit.

The separate private-access server commit changes only module/CLI wiring in src/lib.rs, src/main.rs and src/hbbr.rs, the enabled-only listener/admission guards in src/rendezvous_server.rs, and the enabled-only pairing adapter/shared bandwidth limiter in src/relay_server.rs. These hooks are required to enforce protected registration and relay admission while preserving the existing relay limits and the access-key-disabled paths. Client session/key/IPC/UI hooks are listed in [Private access](private-access.md).
