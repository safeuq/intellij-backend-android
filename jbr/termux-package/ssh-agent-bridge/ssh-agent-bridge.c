// Relays localhost TCP connections to an ssh-agent Unix socket, for clients that hold the right
// token. Why and how: docs/ssh-agent-bridge.md.
//
//   ssh-agent-bridge [--port N] [--agent <socket>]     (default port 5980, agent $SSH_AUTH_SOCK)
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define TOKEN_BYTES 32
#define TOKEN_HEX_LENGTH (TOKEN_BYTES * 2)
#define TOKEN_TIMEOUT_MILLISECONDS 5000

static volatile sig_atomic_t stop_requested;
static char state_path[PATH_MAX];
static char token[TOKEN_HEX_LENGTH + 1];

static void fail(const char *what) {
	fprintf(stderr, "ssh-agent-bridge: %s: %s\n", what, strerror(errno));
	exit(1);
}

static void on_stop(int signal_number) {
	(void)signal_number;
	stop_requested = 1;
}

static void make_token(void) {
	unsigned char random_bytes[TOKEN_BYTES];
	FILE *random_source = fopen("/dev/urandom", "rb");
	if (random_source == NULL || fread(random_bytes, 1, TOKEN_BYTES, random_source) != TOKEN_BYTES) {
		fail("can't read /dev/urandom");
	}
	fclose(random_source);
	for (int index = 0; index < TOKEN_BYTES; index++) {
		sprintf(token + index * 2, "%02x", random_bytes[index]);
	}
}

// ~/.ssh/agent-bridge holds "<port> <token>\n", written as a 0600 temp file and renamed.
static void write_state_file(int port) {
	const char *home = getenv("HOME");
	if (home == NULL || home[0] == '\0') {
		fprintf(stderr, "ssh-agent-bridge: HOME is not set\n");
		exit(1);
	}
	char directory[PATH_MAX], temporary_path[PATH_MAX];
	snprintf(directory, sizeof directory, "%s/.ssh", home);
	snprintf(state_path, sizeof state_path, "%s/agent-bridge", directory);
	snprintf(temporary_path, sizeof temporary_path, "%s/agent-bridge.%d.tmp", directory, (int)getpid());
	if (mkdir(directory, 0700) != 0 && errno != EEXIST) {
		fail("can't create ~/.ssh");
	}
	int file = open(temporary_path, O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (file < 0) {
		fail("can't create the state file");
	}
	char line[TOKEN_HEX_LENGTH + 16];
	int length = snprintf(line, sizeof line, "%d %s\n", port, token);
	if (write(file, line, (size_t)length) != length || close(file) != 0 || rename(temporary_path, state_path) != 0) {
		unlink(temporary_path);
		fail("can't write the state file");
	}
}

// Only removes the file if it still holds this run's token (a newer bridge may have replaced it).
static void remove_state_file(void) {
	char line[TOKEN_HEX_LENGTH + 16];
	FILE *file = fopen(state_path, "r");
	if (file == NULL) {
		return;
	}
	char *read_line = fgets(line, sizeof line, file);
	fclose(file);
	if (read_line != NULL && strstr(line, token) != NULL) {
		unlink(state_path);
	}
}

// Reads exactly `length` bytes, giving up after the deadline. Returns 0 on success.
static int read_with_deadline(int file, char *buffer, size_t length) {
	size_t have = 0;
	while (have < length) {
		struct pollfd waiting = {.fd = file, .events = POLLIN};
		int ready = poll(&waiting, 1, TOKEN_TIMEOUT_MILLISECONDS);
		if (ready <= 0) {
			return -1;
		}
		ssize_t count = read(file, buffer + have, length - have);
		if (count <= 0) {
			return -1;
		}
		have += (size_t)count;
	}
	return 0;
}

static int token_matches(const char *given) {
	unsigned char difference = 0;
	for (int index = 0; index < TOKEN_HEX_LENGTH; index++) {
		difference |= (unsigned char)(given[index] ^ token[index]);
	}
	return given[TOKEN_HEX_LENGTH] == '\n' && difference == 0;
}

static int connect_to_agent(const char *agent_path) {
	struct sockaddr_un address = {.sun_family = AF_UNIX};
	if (strlen(agent_path) >= sizeof address.sun_path) {
		return -1;
	}
	strcpy(address.sun_path, agent_path);
	int agent = socket(AF_UNIX, SOCK_STREAM, 0);
	if (agent >= 0 && connect(agent, (struct sockaddr *)&address, sizeof address) != 0) {
		close(agent);
		return -1;
	}
	return agent;
}

// Copies both ways until both sides have closed; a side that closes first gets a half-close.
static void relay(int client, int agent) {
	int open_sides[2] = {1, 1};
	int files[2] = {client, agent};
	char buffer[16384];
	while (open_sides[0] || open_sides[1]) {
		struct pollfd waiting[2] = {
			{.fd = open_sides[0] ? files[0] : -1, .events = POLLIN},
			{.fd = open_sides[1] ? files[1] : -1, .events = POLLIN},
		};
		if (poll(waiting, 2, -1) < 0 && errno != EINTR) {
			return;
		}
		for (int side = 0; side < 2; side++) {
			if (!(waiting[side].revents & (POLLIN | POLLHUP | POLLERR))) {
				continue;
			}
			ssize_t count = read(files[side], buffer, sizeof buffer);
			if (count > 0) {
				for (ssize_t sent = 0; sent < count;) {
					ssize_t written = write(files[1 - side], buffer + sent, (size_t)(count - sent));
					if (written <= 0) {
						return;
					}
					sent += written;
				}
			} else {
				open_sides[side] = 0;
				shutdown(files[1 - side], SHUT_WR);
			}
		}
	}
}

static void serve(int client, const char *agent_path) {
	char given[TOKEN_HEX_LENGTH + 1];
	if (read_with_deadline(client, given, sizeof given) != 0 || !token_matches(given)) {
		fprintf(stderr, "ssh-agent-bridge: token rejected\n");
		(void)!write(client, "T", 1);
		return;
	}
	int agent = connect_to_agent(agent_path);
	if (agent < 0) {
		fprintf(stderr, "ssh-agent-bridge: agent unreachable (%s)\n", agent_path);
		(void)!write(client, "A", 1);
		return;
	}
	(void)!write(client, "\0", 1);
	relay(client, agent);
	close(agent);
}

int main(int argc, char **argv) {
	int port = 5980;
	const char *agent_path = getenv("SSH_AUTH_SOCK");
	for (int index = 1; index < argc; index++) {
		if (strcmp(argv[index], "--port") == 0 && index + 1 < argc) {
			port = atoi(argv[++index]);
		} else if (strcmp(argv[index], "--agent") == 0 && index + 1 < argc) {
			agent_path = argv[++index];
		} else {
			fprintf(stderr, "usage: ssh-agent-bridge [--port N] [--agent <socket>]\n");
			return 2;
		}
	}
	if (port < 1 || port > 65535) {
		fprintf(stderr, "ssh-agent-bridge: --port needs a number from 1 to 65535\n");
		return 2;
	}
	if (agent_path == NULL || agent_path[0] == '\0') {
		fprintf(stderr, "ssh-agent-bridge: no agent socket: pass --agent <path> or set SSH_AUTH_SOCK\n");
		return 2;
	}

	int listener = socket(AF_INET, SOCK_STREAM, 0);
	int enabled = 1;
	setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof enabled);
	struct sockaddr_in address = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
	inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
	if (bind(listener, (struct sockaddr *)&address, sizeof address) != 0) {
		fail("can't listen on 127.0.0.1 (is the port taken?)");
	}
	if (listen(listener, 16) != 0) {
		fail("listen");
	}

	make_token();
	write_state_file(port);
	struct sigaction stop_action = {.sa_handler = on_stop};  // no SA_RESTART: accept returns on a signal
	sigaction(SIGTERM, &stop_action, NULL);
	sigaction(SIGINT, &stop_action, NULL);
	signal(SIGCHLD, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);
	fprintf(stderr, "ssh-agent-bridge: listening on 127.0.0.1:%d, agent %s\n", port, agent_path);

	while (!stop_requested) {
		int client = accept(listener, NULL, NULL);
		if (client < 0) {
			continue;
		}
		fprintf(stderr, "ssh-agent-bridge: accepted\n");
		pid_t child = fork();
		if (child == 0) {
			close(listener);
			signal(SIGTERM, SIG_DFL);
			signal(SIGINT, SIG_DFL);
			serve(client, agent_path);
			fprintf(stderr, "ssh-agent-bridge: closed\n");
			_exit(0);
		}
		close(client);
	}
	remove_state_file();
	return 0;
}
