# intellij-android

Running IntelliJ IDEA's backend natively on Android, with no Linux VM or proot, as the base for a native Android frontend.

## Status

| Part | State |
|---|---|
| `jbr/`: JetBrains Runtime 25 built for Android (bionic), as a Termux package | Works. IntelliJ IDEA 2026.3's remote-dev server runs on it in Termux; JetBrains Client and Gateway on another machine edit, highlight and complete against it |
| `backend/`: running IntelliJ on the phone | `intellij-backend` (setup, start/stop/status, a notification with a Stop button) and IntelliJ's file watcher built for Android |
| Native frontend | Moved to [safeuq/ideate-editor](https://github.com/safeuq/ideate-editor) (the Ideate Android app and a desktop build of the same code), with its docs: the split-mode protocol, the client and the IntelliJ look |

Why a custom JBR: IntelliJ's remote-dev server needs JetBrains Runtime (`com.jetbrains.JBR.isGraphicsUtilsSupported()` must be `true`), and the JBR that ships with IntelliJ is built for glibc, which Android doesn't have.

## Docs

All documentation is in [`docs/`](docs/):

| Doc | What |
|---|---|
| [`running-the-backend.md`](docs/running-the-backend.md) | set up the phone (`intellij-backend setup`), start/stop the backend, connect from JetBrains Gateway over SSH, known limitations |
| [`building-jbr.md`](docs/building-jbr.md) | build the `jbr-25` Termux package |
| [`jbr-patches.md`](docs/jbr-patches.md) | every patch in the JBR recipe: what it does and why |
| [`jbr-for-android.md`](docs/jbr-for-android.md) | plan and dated log of the whole build: every failure and fix |
| [`fsnotifier.md`](docs/fsnotifier.md) | IntelliJ's file watcher built for Android |
| [`terminal-natives.md`](docs/terminal-natives.md) | the Android builds of JNA's and pty4j's native libraries that IntelliJ's terminal needs, and where they go in IntelliJ's folder |
| [`remote-dev-server.md`](docs/remote-dev-server.md) | how IntelliJ's remote-dev server behaves: launcher, commands, status files, sessions, Gateway's steps, native parts that need glibc |
| [`desktop-ui-on-the-phone.md`](docs/desktop-ui-on-the-phone.md) | IntelliJ's full window on the phone over VNC with XFCE: what works, VNC commands and behaviour |
| [`connections.md`](docs/connections.md) | the Ideate app's connect screen (link, this-phone discovery, history) and the `intellij-backend` contract it relies on |
| [`ssh-agent-bridge.md`](docs/ssh-agent-bridge.md) | `ideate-agent-bridge` and `intellij-backend ssh-agent`: how the Ideate app uses Termux's ssh-agent keys over localhost TCP with a token |
| [`pending.md`](docs/pending.md) | the one list of open work for the backend and the Ideate client: owner, status, where the details are |

## Layout

```
docs/                          all documentation (above)
jbr/
  termux-package/             Termux recipes, each built by scripts/build.sh <name>
    jbr-25/                    the JBR: build.sh, Termux's patches (00NN), ours (10NN)
    intellij-fsnotifier/       IntelliJ's file watcher, our patch
    pty4j-native/              libpty.so and libutil.so for IntelliJ's terminal
    jna-native/                JNA's Android libjnidispatch.so
  scripts/build.sh             builds a recipe's .deb in Termux's Docker build image
  scripts/dev-tree.sh          recreates a patched JBR git tree for writing new patches
  scripts/find-unresolved-symbols.sh
  docker/tar-rosetta-wrapper.sh
backend/checks/                small Java checks used on the phone
backend/termux/intellij-backend  setup/start/stop/status/link for the backend in Termux (called by the app)
```

No upstream source is committed. `jbr/scripts/build.sh` fetches termux-packages at a pinned commit into `work/`, and each recipe downloads its source (the JBR tarball, single files from `intellij-community` and pty4j at pinned commits, JNA's Android jar), checked against its SHA-256.
