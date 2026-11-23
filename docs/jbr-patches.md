# Patches in `jbr/termux-package/jbr-25/`

Applied by Termux's build in file-name order (`0001` … `1004`), then `tmpdir-path-length.diff` in the recipe's `termux_step_pre_configure`.

- `00NN`: Termux's patches for its `openjdk-25` package (OpenJDK 25.0.5), copied unchanged from termux-packages commit `a755405a3af63ed4a05d425230b307d5c9a3ca96`, `packages/openjdk-25/`. All of them apply to JBR `jbr-release-25.0.4.1b635.79` in order with no rejected hunks.
- `10NN`: ours, made for JBR on Android.

Placeholders such as `@TERMUX_PREFIX@` are filled in by Termux's build while patching (`scripts/build/termux_step_patch_package.sh`). `@TERMUX_PREFIX@` becomes `/data/data/com.termux/files/usr`. Patch files must keep the placeholders, never the real path.

## Changing or adding a patch

The `.patch` files are the source of truth; the JBR tree is a throwaway workspace.

1. `jbr/scripts/dev-tree.sh`: clones the JBR tag into `work/jbr` and applies every patch as stored (placeholders kept), one commit each.
2. Edit in `work/jbr`. New patch: commit on top. Existing patch: `git commit --fixup <its commit>`, then `git rebase -i --autosquash`.
3. Export over the file: `git -C work/jbr format-patch -1 --stdout <commit> > jbr/termux-package/jbr-25/10NN-<name>.patch`
4. Build: `jbr/scripts/build.sh jbr-25 -f`, then commit the `.patch` change and update this file.

## Ours

| Patch | Changes | Why | Upstream |
|---|---|---|---|
| `1001-move-old_if_redefining-out-of-dictionary-header.patch` | `src/hotspot/share/classfile/dictionary.{hpp,cpp}`: the body of JBR's DCEVM helper `Dictionary::old_if_redefining()` moves from the header to the `.cpp` | The header only forward-declares `InstanceKlass`, so the inline body compiles only with precompiled headers. Termux builds with `--disable-precompiled-headers`: `dictionary.hpp:86: member access into incomplete type 'InstanceKlass'` | JBR bug on any platform built without precompiled headers; candidate for JetBrains |
| `1002-wayland-use-memfd_create-on-android.patch` | `src/java.desktop/unix/native/common/wayland/memory_utils.c`: on `__ANDROID__`, `CreateSharedMemoryFile` uses `syscall(__NR_memfd_create, baseName, MFD_CLOEXEC)` | Bionic has no `shm_open`/`shm_unlink` (`call to undeclared function 'shm_open'`). `memfd_create` gives the same anonymous shared memory; called through `syscall()` because bionic declares it only from API 30 and Termux builds for API 24 | Android-only |
| `1003-link-font-manager-and-wayland-splash-screen-libraries.patch` | `make/modules/java.desktop/lib/ClientLibraries.gmk`: `libfontmanager` and `libfontmanager_xawt` link `-lawt_xawt` when X11 is built (plus a build-order dependency); `libwlsplashscreen` links `$(ICONV_LIBS)` | These libraries leave symbols undefined (`AccelGlyphCache_RemoveAllCellInfos`, `AWTFreeFont`, … , `libiconv_open`) for glibc to find in libraries loaded earlier. Android's loader doesn't: `dlopen failed: cannot locate symbol "AccelGlyphCache_RemoveAllCellInfos"`. Found with `scripts/find-unresolved-symbols.sh` | Android-only |
| `1004-list-known-children-of-unlistable-folders.patch` | `src/java.base/unix/classes/sun/nio/fs/UnixFileSystemProvider.java`: when `newDirectoryStream` can't list a folder that exists (`EACCES`, or `ENOENT` where `stat` reports a directory), return the existing children on the path to known folders: `@TERMUX_PREFIX@`, `user.home`, `$EXTERNAL_STORAGE` and its real path, mount points under `/storage/` (SD cards, USB drives), plus any added in system property `jdk.nio.fs.unlistableDirectoryHints` (`:`-separated) | Android lets an app pass through `/`, `/data`, `/data/data` and `/storage` but not list them (`EACCES`), and the shared-storage mount `/storage/emulated` reports `ENOENT` although it exists. IntelliJ's `NioFiles.list` turns these errors into an empty list, and VFS refresh then marks the whole project as deleted (editors close, project tree empties). With the patch: `/` → `[data, sdcard, storage]`, `/data/data` → `[com.termux]`, `/storage` → `[emulated]`, `/storage/emulated` → `[0]`. Folders not on a hinted path still fail as before | Android/Termux-only |

## Altered Termux patches

None. Every `00NN` patch and `tmpdir-path-length.diff` is byte-for-byte Termux's file at the pinned commit.

Rule: if a Termux patch is ever edited, list it here with what changed and why. `jbr/scripts/build.sh` compares each one with Termux's `packages/openjdk-25/` at the pinned commit and stops when a patch is altered, added or left out without being named in this file. Every `10NN` patch must be named here too.

## Left out

| Patch | Why |
|---|---|
| `0014-Libfontmanager-link-against-libawt-to-fix-link-error.patch` | Adds `-lawt_xawt` to `libfontmanager` unconditionally. Breaks headless-only builds (`unable to find library -lawt_xawt`), and in JBR the X11 font code it targets lives in `libfontmanager_xawt`. `1003` covers the same need for both libraries, only when X11 is built |

## Termux's

| Patch | Subject |
|---|---|
| `0001` | libinet: include netinet/in.h for android builds |
| `0002` | os_linux: add android checks and fixes |
| `0003` | Define sys gettid on arm and aarch64 |
| `0004` | Disable posix print uptime (overridden by linux!) |
| `0005` | android: prevent build of libsa |
| `0006` | aarch64_get_thread_helper() -> Thread::current() |
| `0007` | Remove aarch64_get_thread_helper() |
| `0008` | Use Android's strerror_r() |
| `0009` | Add CXXFLAGS_JDKLIB to CXXFLAGS |
| `0010` | Use ASCII codeset on android |
| `0011` | Fix libjvm.so path when run from Android app |
| `0012` | arm: cast address to char when clearing cache |
| `0013` | Don't run fpu_control related functions on Android |
| `0015` | Try to get libjvm.so path from /proc/self/maps on android |
| `0016` | Warn instead of exiting if getcpu(2) is unsupported |
| `0017` | Remove pre-UAL aliases |
| `0018` | arm: fix assembly in os_linux_arm.cpp |
| `0019` | Add workaround for tagged pointers on Android 12 |
| `0020` | x86: always compile with PIC |
| `0021` | Fix StackOverflowError on ARM |
| `0022` | android: dlvsym is available if ANDROID_API >= 24 |
| `0023` | Update hardcoded paths to work in termux |
| `0024` | elfFile.hpp: no need to define ELF{32,64}_ST_TYPE on android |
| `0025` | os: linux: add getloadavg implementation for android |
| `0026` | libjava: change return type of strerror_r |
| `0027` | make: cflags: handle arm like other arches |
| `0028` | Fix bugs in File.getCanonicalPath() |
| `0029` | (no subject line) version script: remove local symbols |
| `0030` | make: autoconf: define ARM for arm build with clang |
| `0031` | hotspot: os_linux: do not use dlinfo and RTLD_DI_LINKMAP on android |
| `0032` | (no subject line) OUTTREE: bionic type redefinition fix |
| `0033` | Fix: hardcoded paths in jdk.attach |
| `0034` | (no subject line) Do not disable new dtags |
| `0035` | (no subject line) Disable statx syscall |
| `0036` | (no subject line) Link with iconv: `ICONV_LIBS=-liconv` |
| `0037` | (no subject line) android: skip /proc ipv6 check |
| `tmpdir-path-length.diff` | Sets the temporary-folder path length for `@TERMUX_PREFIX@/tmp` (applied in `termux_step_pre_configure`) |
