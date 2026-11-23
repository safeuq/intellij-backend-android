#!/bin/bash
# End-to-end check on a machine with cc, ssh-agent, ssh-add, ssh-keygen and python3 (python is for
# this test only). Starts a private agent and the bridge in a scratch folder and stops both.
#   jbr/termux-package/ideate-agent-bridge/test.sh [port]      (default 5996)
set -euo pipefail

readonly here="$(cd "$(dirname "$0")" && pwd)"
readonly port="${1:-5996}"
readonly scratch="$(mktemp -d)"
agent_pid="" bridge_pid=""

cleanup() {
	[[ -z "$bridge_pid" ]] || kill "$bridge_pid" 2>/dev/null || true
	[[ -z "$agent_pid" ]] || kill "$agent_pid" 2>/dev/null || true
	rm -rf "$scratch"
}
trap cleanup EXIT

cc -std=c11 -Wall -Wextra -Wpedantic -O2 "$here/ideate-agent-bridge.c" -o "$scratch/bridge"
ssh-keygen -q -t ed25519 -N "" -f "$scratch/key"
ssh-agent -a "$scratch/agent.sock" >/dev/null
agent_pid="$(pgrep -f "ssh-agent -a $scratch/agent.sock")"
SSH_AUTH_SOCK="$scratch/agent.sock" ssh-add -q "$scratch/key"

mkdir "$scratch/home"
export HOME="$scratch/home"
"$scratch/bridge" --port "$port" --agent "$scratch/agent.sock" 2>"$scratch/bridge.log" &
bridge_pid=$!
state_file="$HOME/.ideate/agent-bridge"
for _ in $(seq 50); do [[ -f "$state_file" ]] && break; sleep 0.1; done
[[ -f "$state_file" ]] || { echo "FAIL: no state file"; cat "$scratch/bridge.log"; exit 1; }

[[ "$(stat -f %Lp "$state_file" 2>/dev/null || stat -c %a "$state_file")" == 600 ]] || { echo "FAIL: state file mode"; exit 1; }
[[ "$(<"$state_file")" =~ ^$port\ [0-9a-f]{64}$ ]] || { echo "FAIL: state file format"; exit 1; }
echo "ok: state file 0600, '<port> <64 hex>'"

python3 -I - "$port" "$state_file" "$scratch/agent.sock" <<'PYTHON'
import socket, struct, sys
port, state_file, agent_socket = int(sys.argv[1]), sys.argv[2], sys.argv[3]
token = open(state_file).read().split()[1]

def first_byte(token_line):
    with socket.create_connection(("127.0.0.1", port), timeout=10) as client:
        client.sendall(token_line)
        return client.recv(1)

assert first_byte(b"0" * 64 + b"\n") == b"T", "wrong token"
print("ok: wrong token -> T")
assert first_byte(b"short\n") == b"T", "short token (the bridge waits 5 s for the rest)"
print("ok: short token -> T after the 5 s deadline")

with socket.create_connection(("127.0.0.1", port), timeout=10) as client:
    client.sendall(token.encode() + b"\n")
    assert client.recv(1) == b"\x00", "right token"
    client.sendall(bytes([0, 0, 0, 1, 11]))
    reply = b""
    while len(reply) < 5:
        reply += client.recv(5 - len(reply))
    length, kind = struct.unpack(">IB", reply)
    body = b""
    while len(body) < length - 1:
        body += client.recv(length - 1 - len(body))
    assert kind == 12, f"expected identities answer (12), got {kind}"
    assert struct.unpack(">I", body[:4])[0] == 1, "expected 1 key"
print("ok: token accepted (0x00), identities answer with 1 key")
PYTHON

# Agent socket missing: the bridge was started with the right path, so start a second one for this.
mkdir "$scratch/home2"
HOME="$scratch/home2" "$scratch/bridge" --port "$((port + 1))" --agent "$scratch/missing.sock" 2>>"$scratch/bridge.log" &
second_pid=$!
for _ in $(seq 50); do [[ -f "$scratch/home2/.ideate/agent-bridge" ]] && break; sleep 0.1; done
python3 -I - "$((port + 1))" "$scratch/home2/.ideate/agent-bridge" <<'PYTHON'
import socket, sys
port, state_file = int(sys.argv[1]), sys.argv[2]
token = open(state_file).read().split()[1]
with socket.create_connection(("127.0.0.1", port), timeout=10) as client:
    client.sendall(token.encode() + b"\n")
    assert client.recv(1) == b"A", "agent missing"
print("ok: agent socket missing -> A")
PYTHON
kill "$second_pid"
wait "$second_pid" 2>/dev/null || true
[[ ! -e "$scratch/home2/.ideate/agent-bridge" ]] || { echo "FAIL: second state file left"; exit 1; }

# Port taken: the first bridge still holds $port.
if "$scratch/bridge" --port "$port" --agent "$scratch/agent.sock" 2>"$scratch/taken.log"; then
	echo "FAIL: started on a taken port"; exit 1
fi
grep -q "port taken" "$scratch/taken.log" || { echo "FAIL: no clear port message"; exit 1; }
echo "ok: port taken -> non-zero exit with a message"

kill "$bridge_pid"
wait "$bridge_pid" 2>/dev/null || true
bridge_pid=""
[[ ! -e "$state_file" ]] || { echo "FAIL: state file left after SIGTERM"; exit 1; }
echo "ok: state file removed on SIGTERM"
grep -q "[0-9a-f]\{64\}" "$scratch/bridge.log" && { echo "FAIL: token in the log"; exit 1; }
echo "PASS"
