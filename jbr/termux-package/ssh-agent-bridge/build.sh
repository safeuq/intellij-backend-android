TERMUX_PKG_HOMEPAGE=https://github.com/safeuq/intellij-backend-android
TERMUX_PKG_DESCRIPTION="Lets other Android apps use Termux's ssh-agent over localhost TCP, with a secret token"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@safeuq"
TERMUX_PKG_VERSION="1.0.0"
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686, x86_64"

termux_step_make() {
	# The source sits next to this recipe (build.sh copies the whole folder to packages/<name>).
	$CC $CFLAGS $CPPFLAGS -O2 -Wall -Wextra -Wpedantic -std=c11 \
		"$TERMUX_PKG_BUILDER_DIR/ssh-agent-bridge.c" $LDFLAGS -o ssh-agent-bridge
}

termux_step_make_install() {
	install -Dm755 ssh-agent-bridge "$TERMUX_PREFIX/bin/ssh-agent-bridge"
}
