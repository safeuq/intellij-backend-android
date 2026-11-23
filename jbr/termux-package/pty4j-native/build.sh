TERMUX_PKG_HOMEPAGE=https://github.com/JetBrains/pty4j
TERMUX_PKG_DESCRIPTION="pty4j's native library (libpty.so) and the libutil.so it loads, built for Android, for IntelliJ's terminal"
TERMUX_PKG_LICENSE="EPL-1.0"
TERMUX_PKG_MAINTAINER="@safeuq"
# pty4j commit 7dd1378d167cb451fe6c50f4b73e129ec2925897 (2026-10-02, "bump version to 0.14.0")
_COMMIT=7dd1378d167cb451fe6c50f4b73e129ec2925897
TERMUX_PKG_VERSION="0.14.0"
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686, x86_64"
# Installed at their paths inside IntelliJ's folder; the install script copies them over IntelliJ's own.
_IDEA_FILES="opt/intellij-android"

termux_step_post_get_source() {
	local -A checksums=(
		[exec_pty.c]=93cd28367fdf2c39495f2ed112a076edf45eacc28489e4a0c6bc1833511e4443
		[exec_pty.h]=655f4cf572ef84deef1bd1e3b413261b7555f473411161c22409c008b7787e60
		[openpty.c]=6004aa9ca31090d1a34d03dd3d10ffa2a426105aa7554d1f0643294bf72d3ba4
		[pfind.c]=71bb5eff6813f6b80bd5db66adc4cff7a866458f4dd24cfd8d88991b9a031004
	)
	local file_name
	for file_name in "${!checksums[@]}"; do
		termux_download \
			"https://raw.githubusercontent.com/JetBrains/pty4j/$_COMMIT/native/$file_name" \
			"$TERMUX_PKG_CACHEDIR/$_COMMIT-$file_name" "${checksums[$file_name]}"
		cp "$TERMUX_PKG_CACHEDIR/$_COMMIT-$file_name" "$TERMUX_PKG_SRCDIR/$file_name"
	done
}

termux_step_make() {
	# pty4j's own flags; --no-undefined catches a missing source file (pfind.c) at build time.
	$CC $CFLAGS $CPPFLAGS -shared -fPIC -O2 -D_REENTRANT -D_GNU_SOURCE \
		exec_pty.c openpty.c pfind.c $LDFLAGS -Wl,--no-undefined -o libpty.so
	# pty4j loads "util" only for login_tty, which Android keeps in libc. An empty library that
	# depends on libc lets JNA find login_tty through that dependency.
	: >empty.c
	$CC $CFLAGS -shared -fPIC empty.c $LDFLAGS -Wl,--no-as-needed -lc -Wl,-soname,libutil.so -o libutil.so
}

termux_step_make_install() {
	install -Dm644 libpty.so "$TERMUX_PREFIX/$_IDEA_FILES/plugins/pty4j-plugin/lib/pty4j/linux/aarch64/libpty.so"
	# Not a file of its own in IntelliJ's folder: it goes into intellij.libraries.pty4j.jar as
	# linux-aarch64/libutil.so (see docs/terminal-natives.md).
	install -Dm644 libutil.so "$TERMUX_PREFIX/$_IDEA_FILES/jar-resources/intellij.libraries.pty4j/linux-aarch64/libutil.so"
}
