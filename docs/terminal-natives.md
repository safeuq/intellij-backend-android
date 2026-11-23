# Native libraries for IntelliJ's terminal

IntelliJ's terminal starts its shell through pty4j, and pty4j calls its native code through JNA. IntelliJ ships glibc builds of both native libraries, so on the phone the terminal never starts. `idea.log` shows:

```
Failed to start [/bin/sh]
  <- PtyHelpers: Cannot load native pty executor library
  <- UnsatisfiedLinkError: Unable to locate JNA native support library
```

Three Android files fix it. Each is built by a Termux package recipe in `jbr/termux-package/` (built like `jbr-25`, see below). The packages install them under `$PREFIX/opt/intellij-android/`, at the same relative path they have in IntelliJ's folder:

| File in IntelliJ's folder | Package | Where it comes from |
|---|---|---|
| `plugins/jna-plugin/lib/jna/aarch64/libjnidispatch.so` | `jna-native` | JNA 5.19.1's own Android build, `dist/android-aarch64.jar` (SHA-256 `be093cb7796df563235ac17d77e6dd4e6d24b5e17b614be3675780a11d6aa8a1`). It reports native interface 7.0.4, the same as the JNA in IntelliJ 2026.3 |
| `plugins/pty4j-plugin/lib/pty4j/linux/aarch64/libpty.so` | `pty4j-native` | pty4j's `native/exec_pty.c`, `exec_pty.h`, `openpty.c` and `pfind.c` at commit `7dd1378d167cb451fe6c50f4b73e129ec2925897` (0.14.0), each checked against its SHA-256 |
| `linux-aarch64/libutil.so` inside `plugins/pty4j-plugin/lib/modules/intellij.libraries.pty4j.jar` | `pty4j-native` (installed as `jar-resources/intellij.libraries.pty4j/linux-aarch64/libutil.so`) | An empty library that depends on libc (see below) |

`intellij-fsnotifier` (the file watcher, [`fsnotifier.md`](fsnotifier.md)) installs the same way, as `bin/fsnotifier`.

The install script copies these files over IntelliJ's own, at IntelliJ's default paths. It keeps no `*.glibc` copies and adds no `-D` or VM options that point somewhere else (user's decision, 2026-11-23). Nobody updates the IntelliJ folder by hand.

## Build

```sh
jbr/scripts/build.sh jna-native            # output/jna-native_5.19.1_aarch64.deb
jbr/scripts/build.sh pty4j-native          # output/pty4j-native_0.14.0_aarch64.deb
jbr/scripts/build.sh intellij-fsnotifier   # output/intellij-fsnotifier_2025.04.24_aarch64.deb
```

Each takes about a minute once the Docker container is up ([`building-jbr.md`](building-jbr.md)).

## libpty.so

It is compiled with pty4j's own flags (`-shared -fPIC -O2 -D_REENTRANT -D_GNU_SOURCE`) and Termux's API 24 toolchain. `-Wl,--no-undefined` makes a missing source file fail the build. Without `pfind.c` the library builds, but it doesn't load.

IntelliJ's pty4j jar calls five functions (from `javap` of `NativePtyExecutor$Pty4J`): `exec_pty`, `wait_for_child_process_exit`, `get_window_size`, `set_window_size` and `is_valid_fd`. The pinned commit exports all five.

## libutil.so

pty4j's Linux `OSFacadeImpl` calls `Native.loadLibrary("util")` only for `login_tty`. Android keeps `login_tty` in libc and has no `libutil.so`. In Termux, `$PREFIX/lib/libutil.so` is an 11-byte linker script from `ndk-sysroot`, not a library.

An empty library built with `-shared -fPIC -Wl,--no-as-needed -lc -Wl,-soname,libutil.so` works, because JNA finds `login_tty` through the library's libc dependency.

IntelliJ's launcher sets `jna.nosys` and `jna.noclasspath` and no `jna.library.path`, so a plain `dlopen("libutil.so")` fails. JNA then looks for the resource `linux-aarch64/libutil.so` on the class loader of pty4j's interface. That is the pty4j plugin's class loader, so the file goes inside `intellij.libraries.pty4j.jar`:

```sh
$PREFIX/lib/jvm/jbr-25/bin/jar uf <idea>/plugins/pty4j-plugin/lib/modules/intellij.libraries.pty4j.jar \
  -C $PREFIX/opt/intellij-android/jar-resources/intellij.libraries.pty4j linux-aarch64/libutil.so
```

## Proof on the phone (2026-11-23, S24+)

The UI session ran a small pty4j check on jbr-25 with IntelliJ 263.7307.200's own pty4j and JNA jars and these three libraries. It started `zsh` on `/dev/pts/0`. A resize reached it (`stty size` printed `40 120`), and it exited with 0. In that check, `libutil.so` was found as `linux-aarch64/libutil.so` inside a jar on the classpath, and the libraries were found through `-D` options that applied only to the check.
