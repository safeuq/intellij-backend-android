#!/bin/bash
# Builds one of our Termux packages (aarch64) in Termux's Docker build image.
#
# Fetches termux-packages at a pinned commit into work/termux-packages, copies our recipe in
# as packages/<package>, and runs Termux's build-package.sh there. The source itself is
# downloaded by the recipe, checked against its SHA-256.
#
# Usage: jbr/scripts/build.sh <package> [build-package.sh options]
#   <package>     a folder in jbr/termux-package: jbr-25, intellij-fsnotifier, pty4j-native, jna-native
#   (no options)  full build:              -I -a aarch64 <package>
#   -f            rebuild after changing the recipe (Termux skips packages it has built before)
#   -c            continue a failed build without re-downloading or re-patching
#
# The .deb is copied to output/ and the log written to logs/.

set -euo pipefail

readonly TERMUX_PACKAGES_URL="https://github.com/termux/termux-packages.git"
readonly TERMUX_PACKAGES_COMMIT="a755405a3af63ed4a05d425230b307d5c9a3ca96"
if [[ $# -lt 1 || "$1" == -* ]]; then
	echo "Usage: $0 <package> [build-package.sh options]" >&2
	exit 1
fi
readonly PACKAGE_NAME="$1"
shift
# Our own container, so it never reuses a container whose mount points at another checkout.
readonly BUILDER_CONTAINER_NAME="intellij-android-builder"

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly termux_packages_dir="${TERMUX_PACKAGES_DIR:-$repository_root/work/termux-packages}"
readonly recipe_dir="$repository_root/jbr/termux-package/$PACKAGE_NAME"
readonly jbr_patches_notes="$repository_root/docs/jbr-patches.md"
# Termux's package whose patches jbr-25's start from
readonly UPSTREAM_PACKAGE_NAME="openjdk-25"
readonly fsnotifier_notes="$repository_root/docs/fsnotifier.md"
readonly tar_wrapper="$repository_root/jbr/docker/tar-rosetta-wrapper.sh"
readonly output_dir="$repository_root/output"
readonly log_dir="$repository_root/logs"

if ! command -v docker >/dev/null; then
	echo "docker is required" >&2
	exit 1
fi
if [[ ! -f "$recipe_dir/build.sh" ]]; then
	echo "Recipe not found: $recipe_dir/build.sh" >&2
	exit 1
fi

fetch_termux_packages() {
	if [[ ! -d "$termux_packages_dir/.git" ]]; then
		echo "Fetching termux-packages at $TERMUX_PACKAGES_COMMIT into $termux_packages_dir"
		mkdir -p "$termux_packages_dir"
		git -C "$termux_packages_dir" init -q
		git -C "$termux_packages_dir" remote add origin "$TERMUX_PACKAGES_URL"
		git -C "$termux_packages_dir" fetch -q --depth 1 origin "$TERMUX_PACKAGES_COMMIT"
		git -C "$termux_packages_dir" checkout -q FETCH_HEAD
	fi
	local current_commit
	current_commit="$(git -C "$termux_packages_dir" rev-parse HEAD)"
	if [[ "$current_commit" != "$TERMUX_PACKAGES_COMMIT" ]]; then
		echo "$termux_packages_dir is at $current_commit, expected $TERMUX_PACKAGES_COMMIT." >&2
		echo "Remove it to fetch the pinned commit, or update TERMUX_PACKAGES_COMMIT." >&2
		exit 1
	fi
}

# jbr-25: every patch that differs from Termux's (altered, ours, or left out) must be named in
# docs/jbr-patches.md, so no change goes unrecorded.
check_jbr_patches_documented() {
	local upstream_dir="$termux_packages_dir/packages/$UPSTREAM_PACKAGE_NAME"
	local -a undocumented=()
	local patch_file patch_name

	for patch_file in "$recipe_dir"/*.patch "$recipe_dir"/*.diff; do
		[[ -e "$patch_file" ]] || continue
		patch_name="$(basename "$patch_file")"
		if [[ -f "$upstream_dir/$patch_name" ]] && cmp -s "$patch_file" "$upstream_dir/$patch_name"; then
			continue
		fi
		# altered Termux patch, or one of ours
		grep -qF "$patch_name" "$jbr_patches_notes" || undocumented+=("$patch_name (changed or added)")
	done
	for patch_file in "$upstream_dir"/*.patch "$upstream_dir"/*.diff; do
		[[ -e "$patch_file" ]] || continue
		patch_name="$(basename "$patch_file")"
		if [[ ! -f "$recipe_dir/$patch_name" ]]; then
			grep -qF "$patch_name" "$jbr_patches_notes" || undocumented+=("$patch_name (left out)")
		fi
	done

	if [[ ${#undocumented[@]} -gt 0 ]]; then
		echo "Patches that differ from Termux's $UPSTREAM_PACKAGE_NAME but are not named in docs/jbr-patches.md:" >&2
		printf '  %s\n' "${undocumented[@]}" >&2
		exit 1
	fi
}

# intellij-fsnotifier: every patch must be named in docs/fsnotifier.md.
check_fsnotifier_patches_documented() {
	local patch_file
	for patch_file in "$recipe_dir"/*.patch; do
		[[ -e "$patch_file" ]] || continue
		if ! grep -qF "$(basename "$patch_file")" "$fsnotifier_notes"; then
			echo "$(basename "$patch_file") is not named in docs/fsnotifier.md" >&2
			exit 1
		fi
	done
}

check_patches_documented() {
	case "$PACKAGE_NAME" in
	jbr-25) check_jbr_patches_documented ;;
	intellij-fsnotifier) check_fsnotifier_patches_documented ;;
	esac
}

copy_recipe() {
	# A copy, not a symlink: Docker only mounts termux-packages, so a link out of it would
	# point nowhere inside the container.
	rm -rf "$termux_packages_dir/packages/$PACKAGE_NAME"
	cp -R "$recipe_dir" "$termux_packages_dir/packages/$PACKAGE_NAME"
}

docker_settings_for_host() {
	if [[ "$(uname -s)" == "Darwin" ]]; then
		# The builder image is published for amd64 only.
		export DOCKER_DEFAULT_PLATFORM="linux/amd64"
		# run-docker.sh leaves these out on macOS, but the toolchain setup mounts the NDK
		# toolchain with fuse-overlayfs.
		export TERMUX_DOCKER_RUN_EXTRA_ARGS="--cap-add CAP_SYS_ADMIN --device /dev/fuse"
	fi
	export CONTAINER_NAME="$BUILDER_CONTAINER_NAME"
}

install_tar_wrapper_if_emulated() {
	# Only needed when the amd64 image runs under Rosetta, which lacks openat2.
	if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
		docker cp "$tar_wrapper" "$BUILDER_CONTAINER_NAME:/tmp/tar-wrapper" >/dev/null
		docker exec -u root "$BUILDER_CONTAINER_NAME" install -m 755 /tmp/tar-wrapper /usr/local/bin/tar
	fi
}

main() {
	local -a build_options=("$@")
	fetch_termux_packages
	check_patches_documented
	copy_recipe
	docker_settings_for_host

	cd "$termux_packages_dir"
	# Creates and starts the container if needed, so the wrapper can be installed before the build.
	./scripts/run-docker.sh true
	install_tar_wrapper_if_emulated

	mkdir -p "$output_dir" "$log_dir"
	local log_file
	log_file="$log_dir/build-$(date +%Y%m%d-%H%M%S).log"
	echo "Building $PACKAGE_NAME; log: $log_file"
	# ${array[@]+...} keeps an empty array from failing under set -u in macOS's bash 3.2.
	./scripts/run-docker.sh ./build-package.sh ${build_options[@]+"${build_options[@]}"} \
		-I -a aarch64 "$PACKAGE_NAME" >"$log_file" 2>&1 || {
		echo "Build failed; last lines of $log_file:" >&2
		tail -n 30 "$log_file" >&2
		exit 1
	}

	cp "$termux_packages_dir"/output/"${PACKAGE_NAME}"_*_aarch64.deb "$output_dir"/
	ls -la "$output_dir"/"${PACKAGE_NAME}"_*_aarch64.deb
}

# Run only when executed, so the functions can be sourced on their own (e.g. to test the
# patch check without building).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
