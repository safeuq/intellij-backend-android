TERMUX_PKG_HOMEPAGE=https://github.com/java-native-access/jna
TERMUX_PKG_DESCRIPTION="JNA's native library (libjnidispatch.so) for Android, for IntelliJ's JNA plugin"
TERMUX_PKG_LICENSE="LGPL-2.1, Apache-2.0"
TERMUX_PKG_MAINTAINER="@safeuq"
# JNA's own Android build. 5.19.1 reports native interface 7.0.4, the same as the JNA bundled with
# IntelliJ IDEA 2026.3.
TERMUX_PKG_VERSION="5.19.1"
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686, x86_64"
# Installed at its path inside IntelliJ's folder; the install script copies it over IntelliJ's own.
_IDEA_FILES="opt/intellij-android"

termux_step_post_get_source() {
	local -r jar="$TERMUX_PKG_CACHEDIR/jna-$TERMUX_PKG_VERSION-android-aarch64.jar"
	termux_download \
		"https://github.com/java-native-access/jna/raw/$TERMUX_PKG_VERSION/dist/android-aarch64.jar" \
		"$jar" be093cb7796df563235ac17d77e6dd4e6d24b5e17b614be3675780a11d6aa8a1
	unzip -o -q "$jar" libjnidispatch.so -d "$TERMUX_PKG_SRCDIR"
}

termux_step_make_install() {
	install -Dm644 libjnidispatch.so "$TERMUX_PREFIX/$_IDEA_FILES/plugins/jna-plugin/lib/jna/aarch64/libjnidispatch.so"
}
