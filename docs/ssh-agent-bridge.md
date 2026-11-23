# ssh-agent bridge for the Ideate app

Ideate (the Android app) logs in over SSH with keys that Termux's `ssh-agent` holds, so the private key never leaves
Termux. `ideate-agent-bridge` is the small C program in Termux that makes this possible.

## Why a bridge

`ssh-agent` listens only on a Unix socket and refuses other users' uids. Ideate is another app, so it can't use that
socket:

- Test result: Ideate's `connect` to an abstract Unix socket owned by Termux got `Permission denied`. Android's SELinux
  blocks one app from connecting to another app's Unix socket, abstract or file.
- Localhost TCP between apps works. Tested on the S24+: it worked while Ideate was in front, and it hung while the app
  was in the background with the screen off.
- TCP gives no peer uid on Android, so anything on the phone could connect. The bridge therefore asks for a secret
  token first.

So the bridge listens on `127.0.0.1`, checks a token, and copies bytes between the TCP client and the agent socket.
Ideate reads the token once through Termux's `RUN_COMMAND`, which only apps holding that permission can use.

## Protocol

State file `~/.ideate/agent-bridge` (folder `0700`, file `0600`), one line, written at start by a temp file and a
rename, removed when the bridge exits on SIGTERM or SIGINT (only if it still holds its own token):

```
5980 3f9a7c0d51b8e2644a1c9d07be35f2a8c61d4e90b7a3258f0c1e6d4b9a7f21e
^    ^ 32 random bytes as 64 lowercase hex characters
port
```

Per connection:

| Client sends | Bridge answers | Then |
|---|---|---|
| `3f9a…c21e\n` (64 hex + newline, within 5 s) and the agent socket works | one byte `0x00` | relays bytes both ways until both sides close |
| the wrong, short or late token | one byte `T` (`0x54`) | closes |
| the right token but the agent socket can't be connected | one byte `A` (`0x41`) | closes |

After the `0x00` the connection is the plain ssh-agent protocol. For example `00 00 00 01 0b`
(SSH_AGENTC_REQUEST_IDENTITIES) gets back an SSH_AGENT_IDENTITIES_ANSWER (type 12).

Options: `--port N` (default 5980), `--agent <socket>` (default `$SSH_AUTH_SOCK`; with neither the bridge exits with a
message). A taken port is a non-zero exit with a message. The bridge logs one line per connection to stderr
(accepted, token rejected, agent unreachable, closed) and never prints the token.

## Why this is safe enough

- The token is 32 bytes from `/dev/urandom`, new on every start, and only in a `0600` file in Termux's private home.
  The apps that can read it are Termux and apps with `RUN_COMMAND` permission, which is the same group that can run
  any command in Termux anyway.
- It listens on `127.0.0.1` only, never `0.0.0.0`.
- The token is compared in constant time, and a client has 5 s to send it.
- The agent still decides what its keys may do: the bridge only gives a token holder the same access that
  `SSH_AUTH_SOCK` gives a shell in Termux. Keys added with `ssh-add -c` still ask for confirmation.

## Set up

Install the package (build it with `jbr/scripts/build.sh ideate-agent-bridge`), then in Termux:

```
intellij-backend ssh-agent start       # starts ssh-agent on a fixed socket, then the bridge
SSH_AUTH_SOCK=$PREFIX/var/run/intellij-backend/ssh-agent.sock ssh-add
intellij-backend ssh-agent status      # agent and bridge running, number of keys
intellij-backend ssh-agent stop
```

The socket is `$PREFIX/var/run/intellij-backend/ssh-agent.sock`. To use the same agent in Termux shells, add
`export SSH_AUTH_SOCK=$PREFIX/var/run/intellij-backend/ssh-agent.sock` to `~/.bashrc`. `start` reuses an agent that
already answers on that socket, removes a stale socket file left by a crashed agent, and starts the bridge only if it
isn't running. `stop` ends only the processes whose pid files it wrote, and only when the pid still belongs to
`ssh-agent` or `ideate-agent-bridge`. The bridge log is `~/.local/state/intellij-backend/agent-bridge.log`.

## Test

`jbr/termux-package/ideate-agent-bridge/test.sh [port]` (default 5996) builds the bridge with the local `cc`, starts a
private `ssh-agent` with a throwaway ed25519 key and a bridge with `HOME` in a scratch folder, and checks: the state
file is `0600` and looks like `<port> <64 hex>`; a wrong token and a short token get `T`; the right token gets `0x00`
and a request for identities returns type 12 with 1 key; a missing agent socket gets `A`; a taken port exits non-zero;
SIGTERM removes the state file; the token is not in the log. It stops everything it starts.

Not yet tested on the phone (the `intellij-backend ssh-agent` commands need Termux's `/proc` and `setsid`).
