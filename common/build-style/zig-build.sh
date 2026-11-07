do_build() {
	local zig_target zig_cpu zig_args cc_dir
	local zig_cmd="${_zig_cmd:-${_zig_pkg:-zig}}"

	# TODO: This duplication between build-profiles and cross-profiles
	# is totally unnecessary. It would be nice if there was some way to
	# avoid it.
	if [ "$CROSS_BUILD" ]; then
		zig_target="${XBPS_CROSS_ZIG_TARGET}"
		zig_cpu="${XBPS_CROSS_ZIG_CPU}"
	else
		zig_target="${XBPS_ZIG_TARGET}"
		zig_cpu="${XBPS_ZIG_CPU}"
	fi

	# zig >= 0.17 treats an explicit -Dtarget as a cross build: it then uses
	# its bundled libc headers and the build's translate-c() steps can no
	# longer see system headers (X11/Xlib.h, fontconfig/fontconfig.h, ...).
	# A native build therefore names no target and lets zig default to the
	# host's; -Dcpu is still passed so the artifact stays baseline-CPU
	# portable rather than tuned to the build machine.
	if [ "$CROSS_BUILD" ]; then
		zig_args="-Dtarget=${zig_target} -Dcpu=${zig_cpu}"
	elif [ -n "$zig_cpu" ]; then
		zig_args="-Dcpu=${zig_cpu}"
	else
		zig_args=
	fi

	# zig >= 0.17 renamed gcc_dir to cc_dir (gcc_dir is still accepted as an
	# alias), requires the key to be present, and rejects an empty value on
	# Linux; it also requires darwin_sdk_dir to exist. zig 0.13 ignores keys
	# it does not know, so one file serves both versions.
	cc_dir="$(dirname "$(${CC:-cc} -print-file-name=crtbegin.o 2>/dev/null)")"
	[ -f "${cc_dir}/crtbegin.o" ] || cc_dir="${XBPS_CROSS_BASE}/usr/lib"

	# Inform zig of the required libc include paths.
	cat > xbps_zig_libc.txt <<-EOF
		include_dir=${XBPS_CROSS_BASE}/usr/include
		sys_include_dir=${XBPS_CROSS_BASE}/usr/include
		crt_dir=${XBPS_CROSS_BASE}/usr/lib
		msvc_lib_dir=
		kernel32_lib_dir=
		gcc_dir=${cc_dir}
		darwin_sdk_dir=
	EOF

	# The Zig build system only has a single install step, there is no
	# way to build artifacts for a given prefix and then install those artifacts
	# to that prefix at some later time. Therefore, we build and install to the zig-out
	# directory and later copy the artifacts to the destdir in do_install().
	# We use zig-out to avoid path conflicts as it is the default install
	# prefix used by the zig build system.
	#
	# zig >= 0.17 removed --global-cache-dir in favour of the
	# ZIG_GLOBAL_CACHE_DIR environment variable; the variable is honoured by
	# 0.13 as well, which is why the flag can simply go away.
	ZIG_GLOBAL_CACHE_DIR=/host/zig DESTDIR="zig-out" "${zig_cmd}" build \
		${makejobs} \
		${XBPS_CROSS_BASE:+--sysroot ${XBPS_CROSS_BASE}} \
		--search-prefix "${XBPS_CROSS_BASE}/usr" \
		--prefix /usr \
		--libc xbps_zig_libc.txt \
		--release=safe \
		--verbose \
		${zig_args} \
		install \
		${configure_args}
}

do_install() {
	cp -r zig-out/* "${DESTDIR}"
}
