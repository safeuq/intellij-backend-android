# Connecting: link prompt, discovery and history

Decided with the user on 2026-11-16. The app's connect screen has three parts:

1. **Link prompt**: paste a join link.
2. **Discovered**: a backend on this phone, found through Termux. No LAN discovery (decided 2026-11-16): other machines are added once by link or SSH, then stay in history.
3. **History**: machines connected before. Tapping one reconnects.

Build order: saved pasted links first, then Termux on this phone, then SSH.

Ownership: the screens and the connection logic belong to the UI session ([Ideate](https://github.com/safeuq/ideate-editor)). The phone side (the `intellij-backend` command, Termux setup) belongs to the runtime session (`backend/`). The contract between them is below.

## Why history can't just store the link

| Part of the link | Example | Lifetime |
|---|---|---|
| `jt` (join token) | `584c7a19-0df1-4798-be5c-7af786a00846` | **Used once** (seen 2026-11-16): when a client connects with it, the backend issues a new one. The same client id can use it again only to resume its own session; anyone else gets `Declining invalid token` (see [`split-protocol.md`](https://github.com/safeuq/ideate-editor/blob/main/docs/split-protocol.md)). `intellij-backend link` asks the backend for the current one (IntelliJ's status file keeps the first) |
| client id | `<SHA3-256 of the client's CA certificate>-<epoch ms>` | Chosen by the client. Kept, it can use the same `jt` again |
| `fp` | 64 hex digits | Server certificate fingerprint; checked by the client |
| host, port | `tcp://127.0.0.1:5990` | `0.0.0.0` or `127.0.0.1` as printed by the backend; the client puts in the address it actually reached |

The backend also keeps a dropped session open for the client to resume, with no time limit (`rdct.connection.rd.reconnection.timeout.seconds = -1`). It drops the session only when more than 100 MB of unsent updates pile up (`rdct.wire.storage.wire.buffer.size.bytes`).

**One client at a time.** A backend takes one controlling client. When another connects with a valid token, the backend ends the first one's session (`Active controller connection has been detected. Terminate existing connection.`). Seen 2026-11-16: the phone app was connected, Gateway on the Mac connected to the same backend, the app showed "backend terminated the connection", and its retry with its stored token was refused (`Declining invalid token`).

So:
- **Every history entry stores the client identity it connected with** (CA key and certificate, client id), so the app can resume its session with the same `jt` after it restarts.
- The stored link works only while that session exists: not after the backend restarts, and not after another client took over. Then a fresh link is needed: from Termux, over SSH, or pasted again. Connecting with it takes the backend over from the other client.

## History entry

| Field | Example | For |
|---|---|---|
| kind | `link`, `termux` or `ssh` | how to get a fresh link |
| name | `Pixel 8 · smoke` | display |
| address, port | `192.168.0.105`, `5990` | where to connect |
| project | `/data/data/com.termux/files/home/intellij/smoke` | display; `start` for `termux` and `ssh` |
| `fp` | `9205207E…6B6A` | to notice a different server |
| last link | `tcp://…#jt=…` | try first |
| client identity | key, certificate, client id | reuse the `jt` |
| SSH (kind `ssh` only) | user `u0_a404`, port `8022`, key alias | run commands, tunnel the port |
| last connected | `2026-11-16 10:42` | sort order |

What tapping an entry does:

| Kind | Steps |
|---|---|
| `link` | Connect with the last link and the stored client identity. Refused (another client took over) or the server's `fp` changed (backend restarted) → ask for a new link and keep the entry |
| `termux` | Like Gateway, first run `intellij-backend status --json` through Termux. Not running → `intellij-backend start <project>`. Running without this project in `projects` → `intellij-backend start <project>` opens it in the running backend as a second project (same join link; the app then shows that project, ideate-editor b85440b). Project open → resume with the newest stored client identity for this backend (same `fp` and port, from any of its projects' entries), so the app's own earlier connection isn't taken for another device. That refused, or none stored → `controllerConnected: true` means another client (e.g. Gateway on a laptop) has it, so ask before taking it over; then connect with its `joinLink` (address `127.0.0.1`) and a new client identity. Paths: `start` resolves symlinks, so a project tapped as `~/storage/shared/Files/Projects/Xflow/commons` is listed as `/storage/emulated/0/Files/Projects/Xflow/commons`; after `start` exits 0 the app treats the project as open (the listed one with the same folder name, else `project`) and doesn't run `start` again (ideate-editor 5cd2d36; before, it looped). The whole open is one popup, from the first `status --json` until the session opens or fails; Cancel shows while `start` runs, and on a backend that already serves another project it only stops waiting |
| `ssh` | Over SSH, run `intellij-backend link` (exit `3` → offer `start`). Connect through an SSH local port forward to `127.0.0.1:<port>` on the host. This also avoids opening the backend's port on the LAN |

## Discovery

Only on this phone:

| Check | How |
|---|---|
| Backend running in Termux | `intellij-backend status --json` through Termux (needs the Termux setup below). It reads IntelliJ's own status files in `~/.cache/JetBrains/RemoteDev/active/`, the same ones JetBrains Gateway checks over SSH |
| Termux not set up or not installed | TCP connect to `127.0.0.1:5990`–`5999`: a backend is there, but its link has to be pasted |

There is no LAN discovery: no DNS-SD announcement and no browsing (dropped 2026-11-16). A machine on the LAN is added once, by pasting its link or as an SSH host, and is reached through history after that.

## Runtime contract

The command is `intellij-backend`, at `$PREFIX/bin/intellij-backend` (`/data/data/com.termux/files/usr/bin/intellij-backend`). The UI side calls it through Termux and over SSH, so its output and exit codes are fixed:

| Command | Prints (stdout) | Exit codes |
|---|---|---|
| `start <project> [--lan] [--port N]` | the join link, one line, once the backend is ready (waits up to 180 s). Already open in the running backend: prints its link. A backend for another project is running: asks it to open this project too (IntelliJ's launcher `run <project>` hands it to the running instance, as Gateway does), waits until `status` lists it, then prints the same join link; `--lan`/`--port` are ignored then (since 2026-11-19) | `0` ok, `1` failed (stderr says why), `4` another IntelliJ is using the same settings (the desktop IntelliJ), `5` the backend's notification couldn't be shown, so nothing was started (stderr says why; since 2026-11-23) |
| `link` | the current join link, one line (asks the backend, about 1.5 s) | `0`, `1` the backend didn't answer, `3` not running |
| `status --json` | `{"running":true,"project":"/data/…/smoke","port":5990,"listenOn":"127.0.0.1","joinLink":"tcp://…","controllerConnected":true,"projects":[{"projectPath":"/data/…/smoke","controllerConnected":true},{"projectPath":"/data/…/commons","controllerConnected":false}]}` or `{"running":false}`. `project`: the project in IntelliJ's status file, which IntelliJ rewrites to the **last** project opened (seen on the phone 2026-11-19: after `start knowledge-base` in xtool's backend, `project` was knowledge-base); `projects` (since 2026-11-19): every open project, all on the same join link. `controllerConnected`: some client is connected now (could be this app) | `0`, `1` the backend didn't answer |
| `stop` | nothing | `0` (also when not running). Stops the whole backend, every open project with it (seen on the phone 2026-11-19 with xtool and knowledge-base open) |

While a backend runs, Termux:API shows an ongoing notification (`termux-notification --id intellij-backend`) on its own channel, "IntelliJ Backend" (id `intellij-backend`). Tapping it opens the app (`io.github.safeuq.ideate.client.android/.MainActivity`). It goes through three states:

| State | Title | Text | Button |
|---|---|---|---|
| starting | IntelliJ IDE Backend is starting... | This may take a few minutes | Cancel |
| running | IntelliJ IDE Backend is running | Projects: commons, xflow | Stop |
| stopping | IntelliJ IDE Backend is stopping... | (none) | (none) |

Both buttons run `intellij-backend stop`. While the backend is still starting (no status file yet), `stop` ends the launcher's process group, whose id is in `~/.local/state/intellij-backend/launcher.pid`. "Projects" lists the folder names of every open project; it is posted again when `start` or Gateway opens a second project. Termux:API can't do more (checked in its `NotificationAPI.java`, 2026-11-19):
- no progress bar, so the starting and stopping titles end in "..." instead (open request: termux/termux-api#600);
- the status-bar icon can only be one of Termux:API's own Material icons (`--icon code`). IntelliJ's logo (`bin/idea.png`) could only go in as the large icon with `--image-path`, which also shows it as a big picture when the notification is expanded; the user had it removed (2026-11-19), so the notification has no large icon;
- every tap dismisses the notification (`setAutoCancel(true)`, always, `NotificationAPI.java` line 290), so the tap action opens the app and then runs `intellij-backend internal-notify`, which posts it again (running with the projects open at that moment, or starting). Seen 2026-11-19 on the S24: the notification was gone after opening the app from it. The list isn't updated when a project closes by itself; the next tap or second project refreshes it;
- `termux-notification-channel` doesn't quote the channel name ("IntelliJ Backend" becomes "IntelliJ"), so the script calls `libexec/termux-api NotificationChannel` itself.

The notification is required (user's decision, 2026-11-23). Before IntelliJ runs, `start` posts "starting" and reads it back with `termux-notification-list`. `termux-notification`'s exit code proves nothing, because it is 0 even when nothing was posted. When the notification isn't listed, `start` exits with `5` and starts nothing. stderr gives the reason:

| Case | stderr |
|---|---|
| `termux-notification` not installed | `the termux-api package is missing: pkg install termux-api` |
| no answer within 10 s (the Termux:API app is missing) | `Termux:API didn't answer within 10 s: install the Termux:API app …` |
| posted but not listed (notifications blocked, or no notification access, which the read-back needs) | `the notification "…" isn't showing after posting it …` |

A Gateway or hand-typed start goes through the same check in `internal-run`; its launcher then exits with `5`. Later posts (running, stopping, after a tap) only print a warning, so `stop` and Cancel always go through. The Termux app doesn't have to be running: checked on the S24 on 2026-11-23, Termux:API posted and listed notifications while `termux-am` printed `Could not connect to socket`.

Every backend runs under a small parent (`intellij-backend internal-run`) that shows the notification, waits for IntelliJ's launcher, and then removes the notification and releases the wake lock. `start` uses it directly; for Gateway and hand-typed starts, the launcher wrapper that `intellij-backend setup` puts in place of `bin/remote-dev-server.sh` does. So that happens whenever the backend exits for good (stop, crash, killed by Android), and not on IntelliJ's own restarts (exit code 88), which the launcher handles in a loop. So the app doesn't need its own notification for the backend.

Without `--lan` the backend listens on `127.0.0.1` only (reachable from this phone and over SSH). With `--lan` it listens on `0.0.0.0`.

Termux setup the app needs (one time, done by the user):

1. In `~/.termux/termux.properties`: `allow-external-apps = true`, then `termux-reload-settings`.
2. The app declares `com.termux.permission.RUN_COMMAND` and `<queries><package android:name="com.termux" /></queries>`, and asks for the permission at runtime.
3. The app sends `com.termux.RUN_COMMAND` to `com.termux/.app.RunCommandService` with `RUN_COMMAND_PATH` = the path above, `RUN_COMMAND_ARGUMENTS`, `RUN_COMMAND_BACKGROUND = true`, and a `PendingIntent` that receives stdout, stderr and the exit code.

## Open

- Two devices on one backend at the same time: not as two controlling clients (the second takes over). Code With Me guests might allow it; not looked into.
- `intellij-backend` is written (`backend/termux/intellij-backend`, 2026-11-16) and tested on the phone over SSH and through Termux's RUN_COMMAND (the app's Start). It sets `IDEA_JDK`, `REMOTE_DEV_SERVER_USE_SELF_CONTAINED_LIBS` and `TMPDIR` itself, because RUN_COMMAND and notification buttons don't read a shell profile. `link` and `status` ask the running backend for the current token with IntelliJ's status command (about 1.5 s), because the `active/` status file keeps the first token after it has been used.
