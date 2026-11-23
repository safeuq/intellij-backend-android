# `fsnotifier` for Android

IntelliJ's Linux file watcher (`intellij-community`, `native/fsNotifier/linux`), built for Android with the NDK. It uses `inotify` to tell IntelliJ about changes as they happen. Without it, IntelliJ finds changes by rescanning on a timer and when its window gets focus.

The `bin/fsnotifier` that ships with IntelliJ is statically linked and starts on the phone, but stops at once:

```
can't open /proc/sys/fs/inotify/max_user_watches: Permission denied
GIVEUP
```

Android doesn't let apps read that file, and `fsnotifier` treats a missing watch count as fatal.

## Build

A Termux package, built in Docker like `jbr-25` (moved from the plain-NDK `backend/fsnotifier/build.sh` on 2026-11-23):

```sh
jbr/scripts/build.sh intellij-fsnotifier   # output/intellij-fsnotifier_2025.04.24_aarch64.deb
```

The recipe (`jbr/termux-package/intellij-fsnotifier/`) downloads the four source files at `intellij-community` commit `1725b9d80229df4741d8089ba0011a8911e472d2` (the last change to `native/fsNotifier/linux`), each checked against its SHA-256. Termux applies the patches below, and the recipe compiles with Termux's API 24 toolchain and the flags from JetBrains' `make.sh`. `jbr/scripts/build.sh` stops if a `.patch` file in the recipe isn't named in this file.

The package installs `$PREFIX/opt/intellij-android/bin/fsnotifier`, at its path in IntelliJ's folder. The install script copies it over IntelliJ's own `bin/fsnotifier` ([`terminal-natives.md`](terminal-natives.md) has the same scheme for the terminal's libraries).

## Use

Until the install script replaces `bin/fsnotifier`, `intellij-backend setup` still uses a copy at `~/intellij/fsnotifier`: copy it there and point IntelliJ at it in the `idea.properties` file of IntelliJ's config folder. Both the remote-dev backend and the desktop IntelliJ read that file:

```sh
cp $PREFIX/opt/intellij-android/bin/fsnotifier ~/intellij/fsnotifier
# on the phone; intellij-backend setup adds the same line to the right config folder:
echo "idea.filewatcher.executable.path=$HOME/intellij/fsnotifier" >> ~/.config/JetBrains/IntelliJIdea2026.3/idea.properties
```

IntelliJ's log then shows `Starting file watcher: /data/data/com.termux/files/home/intellij/fsnotifier` and `Native file watcher is operational.`, with no `File watcher gave up to operate` after it. (`operational` alone proves nothing: IntelliJ logs it as soon as the process starts, and the bundled build logs it too before giving up.)

Shared storage (`/storage/emulated/…`) is a FUSE mount, which `fsnotifier` reports to IntelliJ as unwatchable on any Linux. Projects there keep the periodic rescans; projects in Termux's home get the watcher.

## Patches

| Patch | Changes | Why |
|---|---|---|
| `1001-android-default-watch-count.patch` | `inotify.c`: on `__ANDROID__`, when `/proc/sys/fs/inotify/max_user_watches` can't be opened, use `1048576` instead of giving up | The count only sizes `fsnotifier`'s own watch table (indexed by watch descriptor modulo its size). `1048576` is the largest default the kernel picks, so two live descriptors rarely share a slot. The kernel still enforces the real limit, and running out is reported to IntelliJ as before (`inotify.watch.limit`) |
