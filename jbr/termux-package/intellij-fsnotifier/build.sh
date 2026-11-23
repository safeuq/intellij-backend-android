TERMUX_PKG_HOMEPAGE=https://github.com/JetBrains/intellij-community/tree/master/native/fsNotifier/linux
TERMUX_PKG_DESCRIPTION="IntelliJ's Linux file watcher (fsnotifier) built for Android"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@safeuq"
# intellij-community commit 1725b9d80229df4741d8089ba0011a8911e472d2 (2025-04-24), the last change
# to native/fsNotifier/linux
_COMMIT=1725b9d80229df4741d8089ba0011a8911e472d2
TERMUX_PKG_VERSION="2025.04.24"
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686, x86_64"
# Installed at its path inside IntelliJ's folder; the install script copies it over IntelliJ's own.
_IDEA_FILES="opt/intellij-android"

termux_step_post_get_source() {
	local -A checksums=(
		[main.c]=e44a8a8617b26b10ddae8289caa800d30e7f48ad436b4f7d2195a075e646b59f
		[inotify.c]=35e00a7bc0e190eefc3dd636c1b6390fc97156b628e0e27b919269de9b795505
		[util.c]=3e5f17be74be45eaa8f03c1ff7a16071fba168c66733ea2a1ea326ddab162e06
		[fsnotifier.h]=41b2fc2d8ffd9fd8dbe110c3f71ee3856b627c48f549e557f5b268962110d431
	)
	local file_name
	for file_name in "${!checksums[@]}"; do
		termux_download \
			"https://raw.githubusercontent.com/JetBrains/intellij-community/$_COMMIT/native/fsNotifier/linux/$file_name" \
			"$TERMUX_PKG_CACHEDIR/$_COMMIT-$file_name" "${checksums[$file_name]}"
		cp "$TERMUX_PKG_CACHEDIR/$_COMMIT-$file_name" "$TERMUX_PKG_SRCDIR/$file_name"
	done
}

termux_step_make() {
	# Same flags as JetBrains' make.sh, minus -static: Termux runs ordinary bionic executables.
	$CC $CFLAGS $CPPFLAGS -O2 -Wall -Wextra -Wpedantic -std=c11 \
		-D "VERSION=\"${_COMMIT:0:10}-android\"" \
		main.c inotify.c util.c $LDFLAGS -o fsnotifier
}

termux_step_make_install() {
	install -Dm755 fsnotifier "$TERMUX_PREFIX/$_IDEA_FILES/bin/fsnotifier"
}
