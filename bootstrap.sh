#!/bin/sh

set -v
set -e
set -u

export DEB_BUILD_OPTIONS="nocheck noddebs parallel=1"
export DH_VERBOSE=1
HOST_ARCH=undefined
# select gcc version from gcc-defaults package unless set
GCC_VER=
: ${MIRROR:="http://http.debian.net/debian"}
ENABLE_MULTILIB=no
ENABLE_MULTIARCH_GCC=yes
REPODIR=/tmp/repo
APT_GET="apt-get --no-install-recommends -y -o Debug::pkgProblemResolver=true -o Debug::pkgDepCache::Marker=1 -o Debug::pkgDepCache::AutoInstall=1 -o Acquire::Languages=none -o Debug::BuildDeps=1"
DEFAULT_PROFILES="cross nocheck"
LIBC_NAME=glibc
DROP_PRIVS=buildd
GCC_NOLANG=ada,brig,d,go,java,jit,hppa64,objc,obj-c++
ENABLE_DIFFOSCOPE=no

if df -t tmpfs /var/cache/apt/archives >/dev/null 2>&1; then
	APT_GET="$APT_GET -o APT::Keep-Downloaded-Packages=false"
fi

# evaluate command line parameters of the form KEY=VALUE
for param in "$@"; do
	echo "bootstrap-configuration: $param"
	eval $param
done

# test whether element $2 is in set $1
set_contains() {
	case " $1 " in
		*" $2 "*) return 0; ;;
		*) return 1; ;;
	esac
}

# add element $2 to set $1
set_add() {
	case " $1 " in
		"  ") echo "$2" ;;
		*" $2 "*) echo "$1" ;;
		*) echo "$1 $2" ;;
	esac
}

# remove element $2 from set $1
set_discard() {
	local word result
	if set_contains "$1" "$2"; then
		result=
		for word in $1; do
			test "$word" = "$2" || result="$result $word"
		done
		echo "${result# }"
	else
		echo "$1"
	fi
}

# create a set from a string of words with duplicates and excess white space
set_create() {
	local word result
	result=
	for word in $1; do
		result=`set_add "$result" "$word"`
	done
	echo "$result"
}

# intersect two sets
set_intersect() {
	local word result
	result=
	for word in $1; do
		if set_contains "$2" "$word"; then
			result=`set_add "$result" "$word"`
		fi
	done
	echo "$result"
}

# compute the set of elements in set $1 but not in set $2
set_difference() {
	local word result
	result=
	for word in $1; do
		if ! set_contains "$2" "$word"; then
			result=`set_add "$result" "$word"`
		fi
	done
	echo "$result"
}

# compute the union of two sets $1 and $2
set_union() {
	local word result
	result=$1
	for word in $2; do
		result=`set_add "$result" "$word"`
	done
	echo "$result"
}

check_arch() {
	local FILE_RES
	FILE_RES=`file -b "$1"`
	case "$FILE_RES" in
		"ELF 32-bit "*)
			if test 32 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_BITS`; then
				echo "bit mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		"ELF 64-bit "*)
			if test "$2" = hppa64; then :
			elif test 64 != "`dpkg-architecture "-a$2" -qDEB_HOST_ARCH_BITS`"; then
				echo "bit mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*)
			echo "not an ELF binary"
			echo "got $FILE_RES"
			return 1
		;;
	esac
	case "$FILE_RES" in
		*"-bit LSB "*)
			if test little != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_ENDIAN`; then
				echo "endianess mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*"-bit MSB "*)
			if test "$2" = hppa64; then :
			elif test big != "`dpkg-architecture "-a$2" -qDEB_HOST_ARCH_ENDIAN`"; then
				echo "endianess mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*)
			echo "unknown ELF endianess"
			echo "got $FILE_RES"
			return 1
		;;
	esac
	case "$FILE_RES" in
		*" version 1 (SYSV),"*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_OS)" in
				linux|hurd|kfreebsd) ;;
				*)
					echo "os mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*" version 1 (GNU/Linux), "*)
			if test "$2" != hppa64 && test linux != "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_OS)"; then
				echo "os mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*" version 1 (FreeBSD)",*)
			if test kfreebsd != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_OS`; then
				echo "os mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*" version 1, "*)
			echo "skipping os check for $FILE_RES"
		;;
		*)
			echo "unknown ELF os"
			echo "got $FILE_RES"
			return 1
		;;
	esac
	case "$FILE_RES" in
		*", Intel 80386, version "*)
			if test i386 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", x86-64, version "*)
			if test amd64 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", ARM, version "*|*", ARM, EABI5 version "*)
			if test arm != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", ARM aarch64, version "*)
			if test arm64 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", Motorola 68020, version "*|*", Motorola m68k, 68020, version "*)
			if test m68k != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", IA-64, version "*)
			if test ia64 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", MIPS, MIPS-II version "* | *", MIPS, MIPS-I version "* | *", MIPS, MIPS32 rel2 version "*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)" in
				mips|mipsel) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", MIPS, MIPS-III version "* | *", MIPS, MIPS64 version "* | *", MIPS, MIPS64 rel2 version "*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)" in
				mips64|mips64el) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", MIPS, MIPS32 rel6 version "*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)" in
				mipsr6|mipsr6el) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", MIPS, MIPS64 rel6 version "*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)" in
				mips64r6|mips64r6el) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", OpenRISC"*)
			if test or1k != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", PowerPC or cisco 4500, version "*)
			case `dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU` in
				powerpc|powerpcel) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", 64-bit PowerPC or cisco 7500, version "*)
			case "`dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`" in
				ppc64|ppc64el) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", UCB RISC-V, version "*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)" in
				riscv*) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", IBM S/390, version "*)
			case "`dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`" in
				s390|s390x) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", Alpha (unofficial), version "*)
			if test alpha != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", SPARC version "*|*", SPARC, version "*)
			if test sparc != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", SPARC V9, relaxed memory ordering, version "*)
			if test sparc64 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", PA-RISC, version "* | *", PA-RISC, *unknown arch 0xf* version "*)
			if test hppa != "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)"; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", PA-RISC, 2.0 (LP64) version "*)
			if test "$2" != hppa64; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", Renesas SH, version "*)
			case "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)" in
				sh3|sh4) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", Altera Nios II, version"*)
			if test nios2 != "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)"; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*", Tilera TILE-Gx, version"*)
			if test tilegx != "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU)"; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
		;;
		*)
			echo "unknown ELF cpu"
			echo "got $FILE_RES"
			return 1
		;;
	esac
	return 0
}

filter_dpkg_tracked() {
	local pkg pkgs
	pkgs=""
	for pkg in "$@"; do
		dpkg-query -s "$pkg" >/dev/null 2>&1 && pkgs=`set_add "$pkgs" "$pkg"`
	done
	echo "$pkgs"
}

apt_get_install() {
	$APT_GET install "$@"
}

apt_get_build_dep() {
	$APT_GET build-dep "$@"
}

apt_get_remove() {
	local pkgs
	pkgs=$(filter_dpkg_tracked "$@")
	if test -n "$pkgs"; then
		$APT_GET remove $pkgs
	fi
}

apt_get_purge() {
	local pkgs
	pkgs=$(filter_dpkg_tracked "$@")
	if test -n "$pkgs"; then
		$APT_GET purge $pkgs
	fi
}

$APT_GET update
$APT_GET dist-upgrade # we need upgrade later, so make sure the system is clean
$APT_GET install build-essential debhelper reprepro quilt

if dpkg-architecture "-a$HOST_ARCH" -ikfreebsd-any; then
	echo "correcting debhelper's CMAKE_SYSTEM_NAME for kfreebsd-any #856688"
	sed -i -e "s/'FreeBSD'/'kFreeBSD'/" /usr/share/perl5/Debian/Debhelper/Buildsystem/cmake.pm
fi

if test -z "$DROP_PRIVS"; then
	drop_privs_exec() {
		exec env -- "$@"
	}
else
	$APT_GET install adduser fakeroot
	if ! getent passwd "$DROP_PRIVS" >/dev/null; then
		adduser --system --group --home /tmp/buildd --no-create-home --shell /bin/false "$DROP_PRIVS"
	fi
	drop_privs_exec() {
		# Two "--" are necessary here. The first is for start-stop-daemon, the second is for env.
		exec /sbin/start-stop-daemon --start --pidfile /dev/null --chuid "$DROP_PRIVS:$DROP_PRIVS" --chdir "`pwd`" --startas /usr/bin/env -- -- "$@"
	}
fi
drop_privs() {
	( drop_privs_exec "$@" )
}

if test "$ENABLE_MULTIARCH_GCC" = yes; then
	$APT_GET install cross-gcc-dev
	echo "removing unused unstripped_exe patch"
	sed -i '/made-unstripped_exe-setting-overridable/d' /usr/share/cross-gcc/patches/gcc-*/series
	if test "$GCC_VER" = 8; then
		echo "fixing patch application #880917"
		sed -i -e '/^+@@ -223,7 +235,45 @@/s/45/16/' /usr/share/cross-gcc/patches/gcc-8/0008-g-include-directories-functional-again.patch
	fi
fi

obtain_source_package() {
	local use_experimental
	use_experimental=
	case "$1" in
		gcc-[0-9]*)
			test -n "$(apt-cache showsrc "$1")" || use_experimental=yes
		;;
	esac
	if test "$use_experimental" = yes; then
		echo "deb-src $MIRROR experimental main" > /etc/apt/sources.list.d/tmp-experimental.list
		$APT_GET update
	fi
	drop_privs apt-get source "$1"
	if test -f /etc/apt/sources.list.d/tmp-experimental.list; then
		rm /etc/apt/sources.list.d/tmp-experimental.list
		$APT_GET update
	fi
}

if test "$HOST_ARCH" = riscv64; then
	echo "adding riscv64 to dpkg's cputable #822914"
	cat <<EOF >> /usr/share/dpkg/cputable
riscv64		riscv64		riscv64		64	little
EOF
fi

if test -z "$HOST_ARCH" || ! dpkg-architecture "-a$HOST_ARCH"; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
fi

# ensure that the rebootstrap list comes first
test -f /etc/apt/sources.list && mv -v /etc/apt/sources.list /etc/apt/sources.list.d/local.list
for f in /etc/apt/sources.list.d/*.list; do
	test -f "$f" && sed -i "s/^deb \(\[.*\] \)*/deb [ arch-=$HOST_ARCH ] /" $f
done
grep -q '^deb-src .*sid' /etc/apt/sources.list.d/*.list || echo "deb-src $MIRROR sid main" >> /etc/apt/sources.list.d/sid-source.list

dpkg --add-architecture $HOST_ARCH
$APT_GET update

if test -z "$GCC_VER"; then
	GCC_VER=`apt-cache depends gcc | sed 's/^ *Depends: gcc-\([0-9.]*\)$/\1/;t;d'`
fi

rm -Rf /tmp/buildd
drop_privs mkdir -p /tmp/buildd

HOST_ARCH_SUFFIX="-`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE | tr _ -`"

case "$HOST_ARCH" in
	amd64) MULTILIB_NAMES="i386 x32" ;;
	i386) MULTILIB_NAMES="amd64 x32" ;;
	mips|mipsel) MULTILIB_NAMES="mips64 mipsn32" ;;
	mips64|mips64el) MULTILIB_NAMES="mips32 mipsn32" ;;
	mipsn32|mipsn32el) MULTILIB_NAMES="mips32 mips64" ;;
	powerpc) MULTILIB_NAMES=ppc64 ;;
	ppc64) MULTILIB_NAMES=powerpc ;;
	s390x) MULTILIB_NAMES=s390 ;;
	sparc) MULTILIB_NAMES=sparc64 ;;
	sparc64) MULTILIB_NAMES=sparc ;;
	x32) MULTILIB_NAMES="amd64 i386" ;;
	*) MULTILIB_NAMES="" ;;
esac
if test "$ENABLE_MULTILIB" != yes; then
	MULTILIB_NAMES=""
fi

mkdir -p "$REPODIR/conf" "$REPODIR/archive" "$REPODIR/stamps"
cat > "$REPODIR/conf/distributions" <<EOF
Codename: rebootstrap
Label: rebootstrap
Architectures: `dpkg --print-architecture` $HOST_ARCH
Components: main
UDebComponents: main
Description: cross toolchain and build results for $HOST_ARCH

Codename: rebootstrap-native
Label: rebootstrap-native
Architectures: `dpkg --print-architecture`
Components: main
UDebComponents: main
Description: native packages needed for bootstrap
EOF
cat > "$REPODIR/conf/options" <<EOF
verbose
ignore wrongdistribution
EOF
export REPREPRO_BASE_DIR="$REPODIR"
reprepro export
echo "deb [ arch=$(dpkg --print-architecture),$HOST_ARCH trusted=yes ] file://$REPODIR rebootstrap main" >/etc/apt/sources.list.d/000_rebootstrap.list
echo "deb [ arch=$(dpkg --print-architecture) trusted=yes ] file://$REPODIR rebootstrap-native main" >/etc/apt/sources.list.d/001_rebootstrap-native.list
cat >/etc/apt/preferences.d/rebootstrap.pref <<EOF
Explanation: prefer our own rebootstrap (native) packages over everything
Package: *
Pin: release l=rebootstrap-native
Pin-Priority: 1001

Explanation: prefer our own rebootstrap (toolchain) packages over everything
Package: *
Pin: release l=rebootstrap
Pin-Priority: 1002

Explanation: do not use archive cross toolchain
Package: *-$HOST_ARCH-cross *$HOST_ARCH_SUFFIX gcc-*$HOST_ARCH_SUFFIX-base
Pin: release a=unstable
Pin-Priority: -1
EOF
$APT_GET update

# Work around libglib2.0-0 bug #814668. Running kfreebsd-i386 binaries on linux
# can result in clock jumps.
cat >/etc/dpkg/dpkg.cfg.d/bug-814668 <<EOF
path-exclude=/usr/lib/$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH)/glib-2.0/glib-compile-schemas
path-exclude=/usr/lib/$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH)/glib-2.0/gio-querymodules
EOF

# Since most libraries (e.g. libgcc_s) do not include ABI-tags,
# glibc may be confused and try to use them. A typical symptom is:
# apt-get: error while loading shared libraries: /lib/x86_64-kfreebsd-gnu/libgcc_s.so.1: ELF file OS ABI invalid
cat >/etc/dpkg/dpkg.cfg.d/ignore-foreign-linker-paths <<EOF
path-exclude=/etc/ld.so.conf.d/$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH).conf
EOF

# Work around Multi-Arch: same file conflict in libxdmcp-dev. #825146
cat >/etc/dpkg/dpkg.cfg.d/bug-825146 <<'EOF'
path-exclude=/usr/share/doc/libxdmcp-dev/xdmcp.txt.gz
EOF

# Work around Multi-Arch: same file conflict in libgpg-error0. #872806
cat >/etc/dpkg/dpkg.cfg.d/bug-872806 <<'EOF'
path-exclude=/usr/share/locale/*/libgpg-error.mo
EOF

if test "$HOST_ARCH" = nios2; then
	echo "fixing libtool's nios2 misdetection as os2 #851253"
	apt_get_install libtool
	sed -i -e 's/\*os2\*/*-os2*/' /usr/share/libtool/build-aux/ltmain.sh
fi

# work around gtk-doc-tools requiring the native glib2.0.pc #875975
apt_get_install libglib2.0-dev

# removing libc*-dev conflict with each other
LIBC_DEV_PKG=$(apt-cache showpkg libc-dev | sed '1,/^Reverse Provides:/d;s/ .*//;q')
if test "$(apt-cache show "$LIBC_DEV_PKG" | sed -n 's/^Source: //;T;p;q')" = glibc; then
if test -f "$REPODIR/pool/main/g/glibc/$LIBC_DEV_PKG"_*_"$(dpkg --print-architecture).deb"; then
	dpkg -i "$REPODIR/pool/main/g/glibc/$LIBC_DEV_PKG"_*_"$(dpkg --print-architecture).deb"
else
	cd /tmp/buildd
	apt-get download "$LIBC_DEV_PKG"
	dpkg-deb -R "./$LIBC_DEV_PKG"_*.deb x
	sed -i -e '/^Conflicts: /d' x/DEBIAN/control
	mv -nv -t x/usr/include "x/usr/include/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/"*
	mv -nv x/usr/include x/usr/include.orig
	mkdir x/usr/include
	mv -nv x/usr/include.orig "x/usr/include/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
	dpkg-deb -b x "./$LIBC_DEV_PKG"_*.deb
	reprepro includedeb rebootstrap-native "./$LIBC_DEV_PKG"_*.deb
	dpkg -i "./$LIBC_DEV_PKG"_*.deb
	$APT_GET update
	rm -R "./$LIBC_DEV_PKG"_*.deb x
fi # already repacked
fi # is glibc

chdist_native() {
	local command
	command="$1"
	shift
	chdist --data-dir /tmp/chdist_native --arch "$HOST_ARCH" "$command" native "$@"
}

if test "$ENABLE_DIFFOSCOPE" = yes; then
	$APT_GET install devscripts
	chdist_native create "$MIRROR" sid main
	if ! chdist_native apt-get update; then
		echo "rebootstrap-warning: not comparing packages to native builds"
		rm -Rf /tmp/chdist_native
		ENABLE_DIFFOSCOPE=no
	fi
fi
if test "$ENABLE_DIFFOSCOPE" = yes; then
	compare_native() {
		local pkg pkgname tmpdir downloadname errcode
		apt_get_install diffoscope binutils-multiarch vim-common
		for pkg in "$@"; do
			if test "`dpkg-deb -f "$pkg" Architecture`" != "$HOST_ARCH"; then
				echo "not comparing $pkg: wrong architecture"
				continue
			fi
			pkgname=`dpkg-deb -f "$pkg" Package`
			tmpdir=`mktemp -d`
			mkdir "$tmpdir/a" "$tmpdir/b"
			cp "$pkg" "$tmpdir/a" # work around diffoscope recursing over the build tree
			if ! (cd "$tmpdir/b" && chdist_native apt-get download "$pkgname"); then
				echo "not comparing $pkg: download failed"
				rm -R "$tmpdir"
				continue
			fi
			downloadname=`dpkg-deb -W --showformat '${Package}_${Version}_${Architecture}.deb' "$pkg" | sed 's/:/%3a/'`
			if ! test -f "$tmpdir/b/$downloadname"; then
				echo "not comparing $pkg: downloaded different version"
				rm -R "$tmpdir"
				continue
			fi
			errcode=0
			timeout --kill-after=1m 1h diffoscope --text "$tmpdir/out" "$tmpdir/a/$(basename -- "$pkg")" "$tmpdir/b/$downloadname" || errcode=$?
			case $errcode in
				0)
					echo "diffoscope-success: $pkg"
				;;
				1)
					if ! test -f "$tmpdir/out"; then
						echo "rebootstrap-error: no diffoscope output for $pkg"
						exit 1
					elif test "`wc -l < "$tmpdir/out"`" -gt 1000; then
						echo "truncated diffoscope output for $pkg:"
						head -n1000 "$tmpdir/out"
					else
						echo "diffoscope output for $pkg:"
						cat "$tmpdir/out"
					fi
				;;
				124)
					echo "rebootstrap-warning: diffoscope timed out"
				;;
				*)
					echo "rebootstrap-error: diffoscope terminated with abnormal exit code $errcode"
					exit 1
				;;
			esac
			rm -R "$tmpdir"
		done
	}
else
	compare_native() { :
	}
fi

pickup_additional_packages() {
	local f
	for f in "$@"; do
		if test "${f%.deb}" != "$f"; then
			reprepro includedeb rebootstrap "$f"
		elif test "${f%.changes}" != "$f"; then
			reprepro include rebootstrap "$f"
		else
			echo "cannot pick up package $f"
			exit 1
		fi
	done
	$APT_GET update
}

pickup_packages() {
	local sources
	local source
	local f
	local i
	# collect source package names referenced
	sources=""
	for f in "$@"; do
		if test "${f%.deb}" != "$f"; then
			source=`dpkg-deb -f "$f" Source`
			test -z "$source" && source=${f%%_*}
		elif test "${f%.changes}" != "$f"; then
			source=${f%%_*}
		else
			echo "cannot pick up package $f"
			exit 1
		fi
		sources=`set_add "$sources" "$source"`
	done
	# archive old contents and remove them from the repository
	for source in $sources; do
		i=1
		while test -e "$REPODIR/archive/${source}_$i"; do
			i=`expr $i + 1`
		done
		i="$REPODIR/archive/${source}_$i"
		mkdir "$i"
		for f in $(reprepro --list-format '${Filename}\n' listfilter rebootstrap "\$Source (== $source)"); do
			cp -v "$REPODIR/$f" "$i"
		done
		find "$i" -type d -empty -delete
		reprepro removesrc rebootstrap "$source"
	done
	# add new contents
	pickup_additional_packages "$@"
}

# compute a function name from a hook prefix $1 and a package name $2
# returns success if the function actually exists
get_hook() {
	local hook
	hook=`echo "$2" | tr -- -. __` # - and . are invalid in function names
	hook="${1}_$hook"
	echo "$hook"
	type "$hook" >/dev/null 2>&1 || return 1
}

cross_build_setup() {
	local pkg subdir hook
	pkg="$1"
	subdir="${2:-$pkg}"
	cd /tmp/buildd
	drop_privs mkdir "$subdir"
	cd "$subdir"
	obtain_source_package "$pkg"
	cd "${pkg}-"*
	hook=`get_hook patch "$pkg"` && "$hook"
	return 0
}

# add a binNMU changelog entry
# . is a debian package
# $1 is the binNMU number
# $2 is reason
add_binNMU_changelog() {
	cat - debian/changelog <<EOF |
$(dpkg-parsechangelog -SSource) ($(dpkg-parsechangelog -SVersion)+b$1) sid; urgency=medium, binary-only=yes

  * Binary-only non-maintainer upload for $HOST_ARCH; no source changes.
  * $2

 -- rebootstrap <invalid@invalid>  $(dpkg-parsechangelog -SDate)

EOF
		drop_privs tee debian/changelog.new >/dev/null
	drop_privs mv debian/changelog.new debian/changelog
}

check_binNMU() {
	local pkg srcversion binversion maxversion
	srcversion=`dpkg-parsechangelog -SVersion`
	maxversion=$srcversion
	for pkg in `dh_listpackages`; do
		binversion=`apt-cache show "$pkg=$srcversion*" 2>/dev/null | sed -n 's/^Version: //p;T;q'`
		test -z "$binversion" && continue
		if dpkg --compare-versions "$maxversion" lt "$binversion"; then
			maxversion=$binversion
		fi
	done
	case "$maxversion" in
		"$srcversion+b"*)
			echo "rebootstrap-warning: binNMU detected for $(dpkg-parsechangelog -SSource) $srcversion/$maxversion"
			add_binNMU_changelog "${maxversion#$srcversion+b}" "Bump to binNMU version of $(dpkg --print-architecture)."
		;;
	esac
}

PROGRESS_MARK=1
progress_mark() {
	echo "progress-mark:$PROGRESS_MARK:$*"
	PROGRESS_MARK=$(($PROGRESS_MARK + 1 ))
}

# prints the set (as in set_create) of installed packages
record_installed_packages() {
	dpkg --get-selections | sed 's/\s\+install$//;t;d' | xargs
}

# Takes the set (as in set_create) of packages and apt-get removes any
# currently installed packages outside the given set.
remove_extra_packages() {
	local origpackages currentpackates removedpackages extrapackages
	origpackages="$1"
	currentpackages=$(record_installed_packages)
	removedpackages=$(set_difference "$origpackages" "$currentpackages")
	extrapackages=$(set_difference "$currentpackages" "$origpackages")
	echo "original packages: $origpackages"
	echo "removed packages:  $removedpackages"
	echo "extra packages:    $extrapackages"
	apt_get_remove $extrapackages
}

buildpackage_failed() {
	local err last_config_log
	err="$1"
	echo "rebootstrap-error: dpkg-buildpackage failed with status $err"
	last_config_log=$(find . -type f -name config.log -printf "%T@ %p\n" | sort -g | tail -n1 | cut "-d " -f2-)
	if test -f "$last_config_log"; then
		tail -v -n+0 "$last_config_log"
	fi
	exit "$err"
}

cross_build() {
	local pkg profiles ignorebd hook installedpackages
	pkg="$1"
	profiles="$DEFAULT_PROFILES ${2:-}"
	if test "$ENABLE_MULTILIB" = "no"; then
		profiles="$profiles nobiarch"
	fi
	profiles=`echo "$profiles" | sed 's/ /,/g;s/,,*/,/g;s/^,//;s/,$//'`
	if test -f "$REPODIR/stamps/$pkg"; then
		echo "skipping rebuild of $pkg with profiles $profiles"
	else
		echo "building $pkg with profiles $profiles"
		cross_build_setup "$pkg"
		installedpackages=$(record_installed_packages)
		if hook=`get_hook builddep "$pkg"`; then
			echo "installing Build-Depends for $pkg using custom function"
			"$hook" "$HOST_ARCH" "$profiles"
		else
			echo "installing Build-Depends for $pkg using apt-get build-dep"
			apt_get_build_dep "-a$HOST_ARCH" --arch-only -P "$profiles" ./
		fi
		check_binNMU
		ignorebd=
		if get_hook builddep "$pkg" >/dev/null; then
			if dpkg-checkbuilddeps -B "-a$HOST_ARCH" -P "$profiles"; then
				echo "rebootstrap-warning: Build-Depends for $pkg satisfied even though a custom builddep_  function is in use"
			fi
			ignorebd=-d
		fi
		(
			if hook=`get_hook buildenv "$pkg"`; then
				echo "adding environment variables via buildenv hook for $pkg"
				"$hook"
			fi
			drop_privs_exec dpkg-buildpackage "-a$HOST_ARCH" -B "-P$profiles" $ignorebd -uc -us
		) || buildpackage_failed "$?"
		cd ..
		remove_extra_packages "$installedpackages"
		ls -l
		pickup_packages *.changes
		touch "$REPODIR/stamps/$pkg"
		compare_native ./*.deb
		cd ..
		drop_privs rm -Rf "$pkg"
	fi
	progress_mark "$pkg cross build"
}

case "$HOST_ARCH" in
	musl-linux-*) LIBC_NAME=musl ;;
esac

if test "$ENABLE_MULTIARCH_GCC" != yes; then
	apt_get_install dpkg-cross
fi

# gcc0
patch_gcc_limits_h_test() {
	echo "patching gcc to always detect the availability of glibc's limits.h even in multiarch locations"
	drop_privs sed -i -e '/^series_stamp =/idebian_patches += multiarch-limits-h' debian/rules.patch
	drop_privs tee debian/patches/multiarch-limits-h.diff >/dev/null <<'EOF'
--- a/src/gcc/Makefile.in
+++ b/src/gcc/Makefile.in
@@ -494,7 +494,7 @@
 STMP_FIXINC = @STMP_FIXINC@

 # Test to see whether <limits.h> exists in the system header files.
-LIMITS_H_TEST = [ -f $(SYSTEM_HEADER_DIR)/limits.h ]
+LIMITS_H_TEST = :

 # Directory for prefix to system directories, for
 # each of $(system_prefix)/usr/include, $(system_prefix)/usr/lib, etc.
EOF
}
patch_gcc_rtlibs_non_cross_base() {
	test "$ENABLE_MULTIARCH_GCC" != yes || return 0
	echo "fixing gcc rtlibs to build the non-cross base #857074"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules2
+++ b/debian/rules2
@@ -1822,7 +1822,7 @@
   pkg_ver := -$(BASE_VERSION)
 endif

-ifneq ($(DEB_CROSS),yes)
+ifeq ($(if $(filter yes,$(DEB_CROSS)),$(if $(filter rtlibs,$(DEB_STAGE)),native,cross),native),native)
   p_base = gcc$(pkg_ver)-base
   p_lbase = $(p_base)
   p_xbase = gcc$(pkg_ver)-base
EOF
}
patch_gcc_rtlibs_libatomic() {
	test "$ENABLE_MULTIARCH_GCC" != yes || return 0
	echo "patching gcc to build libatomic with rtlibs"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -1352,7 +1352,6 @@
   with_hppa64 := $(call envfilt, hppa64, , , $(with_hppa64))

   ifeq ($(DEB_STAGE),rtlibs)
-    with_libatomic := disabled for rtlibs stage
     with_libasan := disabled for rtlibs stage
     with_liblsan := disabled for rtlibs stage
     with_libtsan := disabled for rtlibs stage
EOF
}
patch_gcc_include_multiarch() {
	test "$ENABLE_MULTIARCH_GCC" = yes || return 0
	echo "patching gcc-N to use all of /usr/include/<triplet>"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules2
+++ b/debian/rules2
@@ -1122,10 +1122,7 @@
 		../src/configure $(subst ___, ,$(CONFARGS))

 	: # multilib builds without b-d on gcc-multilib (used in FLAGS_FOR_TARGET)
-	if [ -d /usr/include/$(DEB_TARGET_MULTIARCH)/asm ]; then \
-	  mkdir -p $(builddir)/sys-include; \
-	  ln -sf /usr/include/$(DEB_TARGET_MULTIARCH)/asm $(builddir)/sys-include/asm; \
-	fi
+	ln -sf /usr/include/$(DEB_TARGET_MULTIARCH) $(builddir)/sys-include

 	touch $(configure_stamp)

EOF
}
patch_gcc_powerpcel() {
	test "$HOST_ARCH" = powerpcel || return 0
	echo "patching gcc for powerpcel"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.patch
+++ b/debian/rules.patch
@@ -233,6 +233,10 @@
   debian_patches += powerpc_nofprs
 endif

+ifeq ($(DEB_TARGET_ARCH),powerpcel)
+  debian_patches += powerpcel
+endif
+
 #debian_patches += link-libs

 # all patches below this line are applied for gcc-snapshot builds as well
--- /dev/null
+++ b/debian/patches/powerpcel.diff
@@ -0,0 +1,13 @@
+--- a/src/gcc/config.gcc
++++ b/src/gcc/config.gcc
+@@ -2401,6 +2401,10 @@
+ 		extra_options="${extra_options} rs6000/linux64.opt"
+ 		tmake_file="${tmake_file} rs6000/t-linux"
+ 		;;
++	    powerpcle-*)
++		tm_file="${tm_file} rs6000/linux.h glibc-stdint.h"
++		tmake_file="${tmake_file} rs6000/t-linux"
++		;;
+ 	    *)
+ 		tm_file="${tm_file} rs6000/linux.h glibc-stdint.h"
+ 		tmake_file="${tmake_file} rs6000/t-ppcos rs6000/t-linux"
EOF
}
patch_gcc_nonglibc() {
	test "$LIBC_NAME" != glibc || return 0
	echo "patching gcc to fix multiarch locations for non-glibc"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.patch
+++ b/debian/rules.patch
@@ -313,6 +313,8 @@
 endif
 debian_patches += gcc-multilib-multiarch
 
+debian_patches += gcc-multiarch-nonglibc
+
 ifneq (,$(filter $(derivative),Ubuntu))
   ifeq (,$(filter $(distrelease),dapper hardy intrepid jaunty karmic lucid maverick))
     debian_patches += gcc-as-needed
--- /dev/null
+++ b/debian/patches/gcc-multiarch-nonglibc.diff
@@ -0,0 +1,29 @@
+--- a/src/gcc/config.gcc
++++ b/src/gcc/config.gcc
+@@ -3002,6 +3002,16 @@
+ 	tm_file="${tm_file} rs6000/option-defaults.h"
+ esac
+ 
++# non-glibc systems
++case ${target} in
++*-linux-musl*)
++	tmake_file="${tmake_file} t-musl"
++	;;
++*-linux-uclibc*)
++	tmake_file="${tmake_file} t-uclibc"
++	;;
++esac
++
+ # Build mkoffload tool
+ case ${target} in
+ *-intelmic-* | *-intelmicemul-*)
+--- /dev/null
++++ b/src/gcc/config/t-musl
+@@ -0,0 +1,2 @@
++MULTIARCH_DIRNAME := $(subst -linux-gnu,-linux-musl,$(MULTIARCH_DIRNAME))
++MULTILIB_OSDIRNAMES := $(subst -linux-gnu,-linux-musl,$(MULTILIB_OSDIRNAMES))
+--- /dev/null
++++ b/src/gcc/config/t-uclibc
+@@ -0,0 +1,2 @@
++MULTIARCH_DIRNAME := $(subst -linux-gnu,-linux-uclibc,$(MULTIARCH_DIRNAME))
++MULTILIB_OSDIRNAMES := $(subst -linux-gnu,-linux-uclibc,$(MULTILIB_OSDIRNAMES))
EOF
}
patch_gcc_multilib_deps() {
	test "$ENABLE_MULTIARCH_GCC" != yes || return 0
	echo "fixing multilib libc dependencies #862756"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -1960,7 +1960,7 @@
 	if [ -f debian/$(1).substvars ]; then \
 	  sed -i \
 	    -e 's/:$(DEB_TARGET_ARCH)/$(cross_lib_arch)/g' \
-	    -e 's/\(libc[.0-9]*-[^:]*\):\([a-z0-9-]*\)/\1-\2-cross/g' \
+	    -e 's/\(libc[.0-9]*-[^: ]*\)\(:$(DEB_TARGET_ARCH)\)\?/\1$(cross_lib_arch)/g' \
 	    $(if $(filter armel,$(DEB_TARGET_ARCH)),-e 's/:armhf/-armhf-cross/g') \
 	    $(if $(filter armhf,$(DEB_TARGET_ARCH)),-e 's/:armel/-armel-cross/g') \
 	    debian/$(1).substvars; \
EOF
}
patch_gcc_arm64ilp32() {
	test "$HOST_ARCH" = arm64ilp32 || return 0
	echo "add support for arm64ilp32 #874583"
	drop_privs tee debian/patches/arm64-ilp32-default.diff >/dev/null <<'EOF'
--- a/src/gcc/config.gcc
+++ b/src/gcc/config.gcc
@@ -515,12 +515,15 @@
 	tm_p_file="${tm_p_file} arm/aarch-common-protos.h"
 	case ${with_abi} in
 	"")
-		if test "x$with_multilib_list" = xilp32; then
+		case ${target} in
+		aarch64*-*-*_ilp32)
 			tm_file="aarch64/biarchilp32.h ${tm_file}"
-		else
+			;;
+		*)
 			tm_file="aarch64/biarchlp64.h ${tm_file}"
-		fi
-		;;
+			;;
+		esac
+		;;
 	ilp32)
 		tm_file="aarch64/biarchilp32.h ${tm_file}"
 		;;
@@ -965,9 +965,16 @@
 	esac
 	aarch64_multilibs="${with_multilib_list}"
 	if test "$aarch64_multilibs" = "default"; then
-		# TODO: turn on ILP32 multilib build after its support is mature.
-		# aarch64_multilibs="lp64,ilp32"
-		aarch64_multilibs="lp64"
+		case $target in
+		aarch64*_ilp32*)
+			aarch64_multilibs="ilp32"
+			;;
+		aarch64*)
+			# TODO: turn on ILP32 multilib build after its support is mature.
+			# aarch64_multilibs="lp64,ilp32"
+			aarch64_multilibs="lp64"
+			;;
+		esac
 	fi
 	aarch64_multilibs=`echo $aarch64_multilibs | sed -e 's/,/ /g'`
 	for aarch64_multilib in ${aarch64_multilibs}; do
EOF
	if ! grep -q arm64-ilp32-default debian/rules.patch; then
		echo "debian_patches += arm64-ilp32-default" | drop_privs tee -a debian/rules.patch >/dev/null
	fi
	drop_privs patch -p1 <<'EOF'
--- a/debian/patches/gcc-multiarch.diff
+++ b/debian/patches/gcc-multiarch.diff
@@ -163,17 +163,21 @@
 ===================================================================
 --- a/src/gcc/config/aarch64/t-aarch64-linux
 +++ b/src/gcc/config/aarch64/t-aarch64-linux
-@@ -22,7 +22,7 @@ LIB1ASMSRC   = aarch64/lib1funcs.asm
+@@ -22,7 +22,12 @@ LIB1ASMSRC   = aarch64/lib1funcs.asm
  LIB1ASMFUNCS = _aarch64_sync_cache_range
  
  AARCH_BE = $(if $(findstring TARGET_BIG_ENDIAN_DEFAULT=1, $(tm_defines)),_be)
--MULTILIB_OSDIRNAMES = mabi.lp64=../lib64$(call if_multiarch,:aarch64$(AARCH_BE)-linux-gnu)
--MULTIARCH_DIRNAME = $(call if_multiarch,aarch64$(AARCH_BE)-linux-gnu)
++ifneq (,$(findstring _ilp32,$(target)))
+ MULTILIB_OSDIRNAMES = mabi.lp64=../lib64$(call if_multiarch,:aarch64$(AARCH_BE)-linux-gnu)
++MULTILIB_OSDIRNAMES += mabi.ilp32=../lib$(call if_multiarch,:aarch64$(AARCH_BE)-linux-gnu_ilp32)
++MULTIARCH_DIRNAME = $(call if_multiarch,aarch64$(AARCH_BE)-linux-gnu_ilp32)
++else
 +MULTILIB_OSDIRNAMES = mabi.lp64=../lib$(call if_multiarch,:aarch64$(AARCH_BE)-linux-gnu)
-+MULTILIB_OSDIRNAMES += mabi.ilp32=../libilp32$(call if_multiarch,:aarch64$(AARCH_BE)_ilp32-linux-gnu)
- 
++MULTILIB_OSDIRNAMES += mabi.ilp32=../libilp32$(call if_multiarch,:aarch64$(AARCH_BE)-linux-gnu_ilp32)
+ MULTIARCH_DIRNAME = $(call if_multiarch,aarch64$(AARCH_BE)-linux-gnu)
+-
 -MULTILIB_OSDIRNAMES += mabi.ilp32=../libilp32
-+MULTIARCH_DIRNAME = $(call if_multiarch,aarch64$(AARCH_BE)-linux-gnu)
++endif
 Index: b/src/gcc/config/mips/mips.h
 ===================================================================
 --- a/src/gcc/config/mips/mips.h
EOF
}
patch_gcc_strict_debhelper_p() {
	test "$ENABLE_MULTIARCH_GCC" = yes && return
	echo "patching gcc to work with debhelper's -p validation #877589"
	drop_privs sed -i -e 's/ -N$(p_hppa64)//' debian/rules2
}
patch_gcc_debhelper_skip_profile() {
	echo "fixing gcc to not let debhelper skip packages #879054"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/binary-fortran.mk
+++ b/debian/rules.d/binary-fortran.mk
@@ -86,8 +86,8 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_l) $(d_d)
-	dh_installdirs -p$(p_l) $(usr_lib$(2))
-	$(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libgfortran.so.*
+	$(for_target) dh_installdirs -p$(p_l) $(usr_lib$(2))
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libgfortran.so.*

 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
@@ -122,9 +122,9 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_l)
-	dh_installdirs -p$(p_l) $(gcc_lib_dir$(2))
+	$(for_target) dh_installdirs -p$(p_l) $(gcc_lib_dir$(2))

-	$(dh_compat2) dh_movefiles -p$(p_l) \
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_l) \
 		$(gcc_lib_dir$(2))/libcaf_single.a
 	$(call install_gcc_lib,libgfortran,$(FORTRAN_SONAME),$(2),$(p_l))

--- a/debian/rules.d/binary-libatomic.mk
+++ b/debian/rules.d/binary-libatomic.mk
@@ -24,8 +24,8 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_l) $(d_d)
-	dh_installdirs -p$(p_l) $(usr_lib$(2))
-	$(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libatomic.so.*
+	$(for_target) dh_installdirs -p$(p_l) $(usr_lib$(2))
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libatomic.so.*

 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
--- a/debian/rules.d/binary-libgcc.mk
+++ b/debian/rules.d/binary-libgcc.mk
@@ -158,8 +158,8 @@

 	test -n "$(2)"
 	rm -rf debian/$(2)
-	dh_installdirs -p$(2) $(docdir) #TODO
-	dh_installdirs -p$(2) $(3)
+	$(for_target) dh_installdirs -p$(2) $(docdir) #TODO
+	$(for_target) dh_installdirs -p$(2) $(3)

 	$(call __do_gcc_devels2,$(1),$(2),$(3),$(4))

@@ -182,17 +182,17 @@
 		set -e; \
 		if [ -h $(4)/libgcc_s.so ]; then \
 		  rm -f $(4)/libgcc_s.so; \
-		  dh_link -p$(2) /$(libgcc_dir$(1))/libgcc_s.so.$(GCC_SONAME) \
+		  $(for_target) dh_link -p$(2) /$(libgcc_dir$(1))/libgcc_s.so.$(GCC_SONAME) \
 		    /$(3)/libgcc_s.so; \
 		else \
 		  mv $(4)/libgcc_s.so $(d)/$(3)/libgcc_s.so; \
-		  dh_link -p$(2) /$(libgcc_dir$(1))/libgcc_s.so.$(GCC_SONAME) \
+		  $(for_target) dh_link -p$(2) /$(libgcc_dir$(1))/libgcc_s.so.$(GCC_SONAME) \
 		    /$(3)/libgcc_s.so.$(GCC_SONAME); \
 		fi; \
-		$(if $(1), dh_link -p$(2) /$(3)/libgcc_s.so \
+		$(if $(1), $(for_target) dh_link -p$(2) /$(3)/libgcc_s.so \
 		    /$(gcc_lib_dir)/libgcc_s_$(1).so;)
 	)
-	$(dh_compat2) dh_movefiles -p$(2) \
+	$(for_target) $(dh_compat2) dh_movefiles -p$(2) \
 		$(3)/{libgcc*,libgcov.a,*.o} \
 		$(if $(1),,$(header_files)) # Only move headers for the "main" package

@@ -281,7 +281,7 @@

 	rm -rf $(d_l) $(d_d)

-	dh_installdirs -p$(p_l) \
+	$(for_target) dh_installdirs -p$(p_l) \
 		$(docdir)/$(p_l) \
 		$(libgcc_dir$(2))

--- a/debian/rules.d/binary-libgomp.mk
+++ b/debian/rules.d/binary-libgomp.mk
@@ -24,8 +24,8 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_l) $(d_d)
-	dh_installdirs -p$(p_l) $(usr_lib$(2))
-	$(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libgomp.so.*
+	$(for_target) dh_installdirs -p$(p_l) $(usr_lib$(2))
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libgomp.so.*

 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
--- a/debian/rules.d/binary-libquadmath.mk
+++ b/debian/rules.d/binary-libquadmath.mk
@@ -24,8 +24,8 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_l) $(d_d)
-	dh_installdirs -p$(p_l) $(usr_lib$(2))
-	$(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libquadmath.so.*
+	$(for_target) dh_installdirs -p$(p_l) $(usr_lib$(2))
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_l) $(usr_lib$(2))/libquadmath.so.*

 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
--- a/debian/rules.d/binary-libstdcxx.mk
+++ b/debian/rules.d/binary-libstdcxx.mk
@@ -185,7 +185,7 @@

 	rm -rf $(d_l)

-	dh_installdirs -p$(p_l) \
+	$(for_target) dh_installdirs -p$(p_l) \
 		$(docdir) \
 		$(usr_lib$(2)) \
 		$(PF)/share/gdb/auto-load/$(usr_lib$(2))
@@ -231,7 +231,7 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_d)
-	dh_installdirs -p$(p_d) \
+	$(for_target) dh_installdirs -p$(p_d) \
 		$(PF)/lib/debug/$(usr_lib$(2)) \
 		$(usr_lib$(2))

@@ -274,9 +274,9 @@
 		$(d)/$(gcc_lib_dir$(2))/

 	rm -rf $(d_l)
-	dh_installdirs -p$(p_l) $(gcc_lib_dir$(2))
+	$(for_target) dh_installdirs -p$(p_l) $(gcc_lib_dir$(2))

-	$(dh_compat2) dh_movefiles -p$(p_l) \
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_l) \
 		$(gcc_lib_dir$(2))/libstdc++.a \
 		$(gcc_lib_dir$(2))/libstdc++fs.a \
 		$(gcc_lib_dir$(2))/libsupc++.a \
@@ -369,9 +369,9 @@
 	mv $(install_stamp) $(install_stamp)-tmp

 	rm -rf $(d_dev) $(d_pic)
-	dh_installdirs -p$(p_dev) $(dirs_dev)
-	dh_installdirs -p$(p_pic) $(dirs_pic)
-	dh_installdirs -p$(p_dbg) $(dirs_dbg)
+	$(for_target) dh_installdirs -p$(p_dev) $(dirs_dev)
+	$(for_target) dh_installdirs -p$(p_pic) $(dirs_pic)
+	$(for_target) dh_installdirs -p$(p_dbg) $(dirs_dbg)

 	: # - correct libstdc++-v3 file locations
 	mv $(d)/$(usr_lib)/libsupc++.a $(d)/$(gcc_lib_dir)/
@@ -391,18 +391,18 @@
 	  if [ -d $$i ]; then mv $$i $$i-gnu; fi; \
 	done
 
-	$(dh_compat2) dh_movefiles -p$(p_dev) $(files_dev)
-	$(dh_compat2) dh_movefiles -p$(p_pic) $(files_pic)
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_dev) $(files_dev)
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_pic) $(files_pic)
 ifeq ($(with_cxx_debug),yes)
-	$(dh_compat2) dh_movefiles -p$(p_dbg) $(files_dbg)
+	$(for_target) $(dh_compat2) dh_movefiles -p$(p_dbg) $(files_dbg)
 endif
 
-	dh_link -p$(p_dev) \
+	$(for_target) dh_link -p$(p_dev) \
 		/$(usr_lib)/libstdc++.so.$(CXX_SONAME) \
 		/$(gcc_lib_dir)/libstdc++.so \
 		/$(PFL)/include/c++/$(BASE_VERSION) /$(PFL)/include/c++/$(GCC_VERSION)
 ifeq ($(with_multiarch_cxxheaders),yes)
-	dh_link -p$(p_dev) \
+	$(for_target) dh_link -p$(p_dev) \
 		/$(PFL)/include/$(DEB_TARGET_MULTIARCH)/c++/$(BASE_VERSION) \
 		/$(PFL)/include/$(DEB_TARGET_MULTIARCH)/c++/$(GCC_VERSION)
 endif
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -239,6 +239,7 @@
   TARGET_ALIAS := $(DEB_TARGET_ALIAS)

   lib_binaries := indep_binaries
+  for_target = env `dpkg-architecture -f -a$(DEB_TARGET_ARCH)`
   cross_shlibdeps =  DEB_HOST_ARCH=$(TARGET) ARCH=$(DEB_TARGET_ARCH) MAKEFLAGS="CC=something"
   cross_gencontrol = DEB_HOST_ARCH=$(TARGET)
   cross_makeshlibs = DEB_HOST_ARCH=$(TARGET)
@@ -273,6 +274,7 @@
   #TARGET_ALIAS := $(subst linux-gnu,linux,$(TARGET_ALIAS))

   lib_binaries := arch_binaries
+  for_target :=
   cross_shlibdeps :=
   cross_gencontrol :=
   cross_makeshlibs :=
--- a/debian/rules2
+++ b/debian/rules2
@@ -935,7 +935,7 @@
 define install_gcc_lib
 	mv $(d)/$(usr_lib$(3))/$(1)*.a debian/$(4)/$(gcc_lib_dir$(3))/
 	rm -f $(d)/$(usr_lib$(3))/$(1)*.{la,so}
-	dh_link -p$(4) \
+	$(for_target) dh_link -p$(4) \
 	  /$(usr_lib$(3))/$(1).so.$(2) /$(gcc_lib_dir$(3))/$(1).so

 endef
@@ -2434,9 +2434,9 @@
 	cat debian/indep_binaries debian/indep_binaries.epoch > debian/indep_binaries.all

 binary-indep: debian/indep_binaries.all
-	dh_compress $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p)) \
+	$(for_target) dh_compress $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p)) \
 	  -X.log.xz -X.sum.xz -X.c -X.txt -X.tag -X.map -XREADME.Bugs
-	dh_fixperms $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
+	$(for_target) dh_fixperms $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
 	: # the export should be harmless for the binary indep packages of a native build
 	export DEB_HOST_ARCH=$(TARGET); \
 	dh_gencontrol $(foreach p,$(shell echo `cat debian/indep_binaries`),-p$(p)) \
@@ -2459,9 +2459,9 @@
 	done
 endif

-	dh_installdeb $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
-	dh_md5sums $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
-	dh_builddeb $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
+	$(for_target) dh_installdeb $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
+	$(for_target) dh_md5sums $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))
+	$(for_target) dh_builddeb $(foreach p,$(shell echo `cat debian/indep_binaries.all`),-p$(p))

 	@echo XXXXX `date -R`

EOF
}
patch_gcc_wdotap() {
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		echo "applying patches for with_deps_on_target_arch_pkgs"
		drop_privs QUILT_PATCHES="/usr/share/cross-gcc/patches/gcc-$GCC_VER" quilt push -a
		drop_privs rm -Rf .pc
	fi
}
patch_gcc_6() {
	echo "patching gcc-6 to support building without binutils-multiarch #804190"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/binary-ada.mk
+++ b/debian/rules.d/binary-ada.mk
@@ -126,7 +126,7 @@
 		$(d_lgnat)/usr/share/lintian/overrides/$(p_lgnat)
 endif
 
-	dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_lgnat) \
 		$(call shlibdirs_to_search, \
 			$(subst gnat-$(GNAT_SONAME),gcc$(GCC_SONAME),$(p_lgnat)) \
@@ -160,7 +160,7 @@
 	   $(usr_lib)/libgnatvsn.so.$(GNAT_VERSION) \
 	   $(usr_lib)/libgnatvsn.so
 	debian/dh_doclink -p$(p_lgnatvsn_dev) $(p_glbase)
-	dh_strip -p$(p_lgnatvsn_dev) -X.a --keep-debug
+	$(cross_strip) dh_strip -p$(p_lgnatvsn_dev) -X.a --keep-debug
 
 	: # $(p_lgnatvsn)
 ifneq (,$(filter $(build_type), build-native cross-build-native))
@@ -170,7 +170,7 @@
 endif
 	$(dh_compat2) dh_movefiles -p$(p_lgnatvsn) $(usr_lib)/libgnatvsn.so.$(GNAT_VERSION)
 	debian/dh_doclink -p$(p_lgnatvsn) $(p_glbase)
-	dh_strip -p$(p_lgnatvsn) --dbg-package=$(p_lgnatvsn_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnatvsn) --dbg-package=$(p_lgnatvsn_dbg)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_lgnatvsn) \
 		-V '$(p_lgnatvsn) (>= $(DEB_VERSION))'
 	$(call cross_mangle_shlibs,$(p_lgnatvsn))
@@ -206,7 +206,7 @@
 	dh_link -p$(p_lgnatprj_dev) \
 	   $(usr_lib)/libgnatprj.so.$(GNAT_VERSION) \
 	   $(usr_lib)/libgnatprj.so
-	dh_strip -p$(p_lgnatprj_dev) -X.a --keep-debug
+	$(cross_strip) dh_strip -p$(p_lgnatprj_dev) -X.a --keep-debug
 	debian/dh_doclink -p$(p_lgnatprj_dev) $(p_glbase)
 
 	: # $(p_lgnatprj)
@@ -217,7 +217,7 @@
 endif
 	$(dh_compat2) dh_movefiles -p$(p_lgnatprj) $(usr_lib)/libgnatprj.so.$(GNAT_VERSION)
 	debian/dh_doclink -p$(p_lgnatprj) $(p_glbase)
-	dh_strip -p$(p_lgnatprj) --dbg-package=$(p_lgnatprj_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnatprj) --dbg-package=$(p_lgnatprj_dbg)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_lgnatprj) \
 		-V '$(p_lgnatprj) (>= $(DEB_VERSION))'
 	$(call cross_mangle_shlibs,$(p_lgnatprj))
@@ -347,7 +347,7 @@
 
 	debian/dh_rmemptydirs -p$(p_gnat)
 
-	dh_strip -p$(p_gnat)
+	$(cross_strip) dh_strip -p$(p_gnat)
 	find $(d_gnat) -name '*.ali' | xargs chmod 444
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_gnat) \
 		$(call shlibdirs_to_search, \
@@ -356,7 +356,7 @@
 	echo $(p_gnat) >> debian/arch_binaries
 
 ifeq ($(with_gnatsjlj),yes)
-	dh_strip -p$(p_gnatsjlj)
+	$(cross_strip) dh_strip -p$(p_gnatsjlj)
 	find $(d_gnatsjlj) -name '*.ali' | xargs chmod 444
 	$(cross_makeshlibs) dh_shlibdeps -p$(p_gnatsjlj)
 	echo $(p_gnatsjlj) >> debian/arch_binaries
--- a/debian/rules.d/binary-fortran.mk
+++ b/debian/rules.d/binary-fortran.mk
@@ -97,7 +97,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgfortran.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
@@ -130,7 +130,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_l)
 	$(call cross_mangle_substvars,$(p_l))
 	echo $(p_l) >> debian/$(lib_binaries)
--- a/debian/rules.d/binary-go.mk
+++ b/debian/rules.d/binary-go.mk
@@ -120,7 +120,7 @@
 	  >> debian/$(p_l)/usr/share/lintian/overrides/$(p_l)
 
 	: # don't strip: https://gcc.gnu.org/ml/gcc-patches/2015-02/msg01722.html
-	: # dh_strip -p$(p_l) --dbg-package=$(p_d)
+	: # $(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libasan.mk
+++ b/debian/rules.d/binary-libasan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l) || echo XXXXXXXXXXXXXX ERROR $(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libatomic.mk
+++ b/debian/rules.d/binary-libatomic.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libatomic.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libcilkrts.mk
+++ b/debian/rules.d/binary-libcilkrts.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libcilkrts.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libgcc.mk
+++ b/debian/rules.d/binary-libgcc.mk
@@ -161,7 +161,7 @@
 	debian/dh_doclink -p$(2) $(p_lbase)
 	debian/dh_rmemptydirs -p$(2)
 
-	dh_strip -p$(2)
+	$(cross_strip) dh_strip -p$(2)
 	$(cross_shlibdeps) dh_shlibdeps -p$(2)
 	$(call cross_mangle_substvars,$(2))
 	echo $(2) >> debian/$(lib_binaries)
@@ -289,7 +289,7 @@
 	debian/dh_doclink -p$(p_d) $(if $(3),$(3),$(p_lbase))
 	debian/dh_rmemptydirs -p$(p_l)
 	debian/dh_rmemptydirs -p$(p_d)
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 
 	# see Debian #533843 for the __aeabi symbol handling; this construct is
 	# just to include the symbols for dpkg versions older than 1.15.3 which
--- a/debian/rules.d/binary-libgccjit.mk
+++ b/debian/rules.d/binary-libgccjit.mk
@@ -42,7 +42,7 @@
 	debian/dh_doclink -p$(p_jitdev) $(p_base)
 	debian/dh_doclink -p$(p_jitdbg) $(p_base)
 
-	dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
+	$(cross_strip) dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_jitlib)
 	$(call cross_mangle_shlibs,$(p_jitlib))
 	$(ignshld)$(cross_shlibdeps) dh_shlibdeps -p$(p_jitlib)
--- a/debian/rules.d/binary-libgomp.mk
+++ b/debian/rules.d/binary-libgomp.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgomp.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libitm.mk
+++ b/debian/rules.d/binary-libitm.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libitm.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-liblsan.mk
+++ b/debian/rules.d/binary-liblsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libmpx.mk
+++ b/debian/rules.d/binary-libmpx.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libmpx.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libobjc.mk
+++ b/debian/rules.d/binary-libobjc.mk
@@ -65,7 +65,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	rm -f debian/$(p_l).symbols
 	$(if $(2),
 	  ln -sf libobjc.symbols debian/$(p_l).symbols ,
--- a/debian/rules.d/binary-libquadmath.mk
+++ b/debian/rules.d/binary-libquadmath.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libquadmath.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libstdcxx.mk
+++ b/debian/rules.d/binary-libstdcxx.mk
@@ -207,7 +207,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
+	$(cross_strip) dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
 
 	$(if $(filter $(DEB_TARGET_ARCH), armel hppa sparc64), \
 	  -$(cross_makeshlibs) dh_makeshlibs -p$(p_l) \
@@ -237,7 +237,7 @@
 	$(if $(filter yes,$(with_lib$(2)cxx)),
 		cp -a $(d)/$(usr_lib$(2))/libstdc++.so.*[0-9] \
 			$(d_d)/$(usr_lib$(2))/.;
-		dh_strip -p$(p_d) --keep-debug;
+		$(cross_strip) dh_strip -p$(p_d) --keep-debug;
 		$(if $(filter yes,$(with_common_libs)),, # if !with_common_libs
 			# remove the debug symbols for libstdc++
 			# built by a newer version of GCC
@@ -283,7 +283,7 @@
 
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	dh_shlibdeps -p$(p_l) \
 		$(call shlibdirs_to_search,$(subst stdc++$(CXX_SONAME),gcc$(GCC_SONAME),$(p_l)),$(2))
 	echo $(p_l) >> debian/$(lib_binaries)
@@ -430,16 +430,16 @@
 ifeq ($(with_libcxx),yes)
 	cp -a $(d)/$(usr_lib)/libstdc++.so.*[0-9] \
 		$(d_dbg)/$(usr_lib)/
-	dh_strip -p$(p_dbg) --keep-debug
+	$(cross_strip) dh_strip -p$(p_dbg) --keep-debug
 	rm -f $(d_dbg)/$(usr_lib)/libstdc++.so.*[0-9]
 endif
 
-	dh_strip -p$(p_dev) --dbg-package=$(p_dbg)
+	$(cross_strip) dh_strip -p$(p_dev) --dbg-package=$(p_dbg)
 ifneq ($(with_common_libs),yes)
 	: # remove the debug symbols for libstdc++ built by a newer version of GCC
 	rm -rf $(d_dbg)/usr/lib/debug/$(PF)
 endif
-	dh_strip -p$(p_pic)
+	$(cross_strip) dh_strip -p$(p_pic)
 
 ifeq ($(with_cxxdev),yes)
 	debian/dh_rmemptydirs -p$(p_dev)
--- a/debian/rules.d/binary-libtsan.mk
+++ b/debian/rules.d/binary-libtsan.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libubsan.mk
+++ b/debian/rules.d/binary-libubsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libvtv.mk
+++ b/debian/rules.d/binary-libvtv.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -212,6 +212,7 @@
   cross_gencontrol = DEB_HOST_ARCH=$(TARGET)
   cross_makeshlibs = DEB_HOST_ARCH=$(TARGET)
   cross_clean = DEB_HOST_ARCH=$(TARGET)
+  cross_strip = dpkg-architecture -f -a$(TARGET) -c
 else
   TARGET_ALIAS := $(DEB_TARGET_GNU_TYPE)
 
@@ -240,6 +241,7 @@
   cross_gencontrol :=
   cross_makeshlibs :=
   cross_clean :=
+  cross_strip :=
 endif
 
 printarch:
EOF
	patch_gcc_limits_h_test
	patch_gcc_rtlibs_non_cross_base
	patch_gcc_rtlibs_libatomic
	patch_gcc_include_multiarch
	patch_gcc_powerpcel
	patch_gcc_nonglibc
	patch_gcc_multilib_deps
	echo "build common libraries again, not a bug"
	sed -i -e '/^with_common_/s/=.*/= yes/' debian/rules.defs
	patch_gcc_wdotap
}
patch_gcc_7() {
	echo "patching gcc-7 to support building without binutils-multiarch #804190"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/binary-ada.mk
+++ b/debian/rules.d/binary-ada.mk
@@ -126,7 +126,7 @@
 		$(d_lgnat)/usr/share/lintian/overrides/$(p_lgnat)
 endif
 
-	dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_lgnat) \
 		$(call shlibdirs_to_search, \
 			$(subst gnat-$(GNAT_SONAME),gcc$(GCC_SONAME),$(p_lgnat)) \
@@ -347,7 +347,7 @@
 
 	debian/dh_rmemptydirs -p$(p_gnat)
 
-	dh_strip -p$(p_gnat)
+	$(cross_strip) dh_strip -p$(p_gnat)
 	find $(d_gnat) -name '*.ali' | xargs chmod 444
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_gnat) \
 		$(call shlibdirs_to_search, \
@@ -356,7 +356,7 @@
 	echo $(p_gnat) >> debian/arch_binaries
 
 ifeq ($(with_gnatsjlj),yes)
-	dh_strip -p$(p_gnatsjlj)
+	$(cross_strip) dh_strip -p$(p_gnatsjlj)
 	find $(d_gnatsjlj) -name '*.ali' | xargs chmod 444
 	$(cross_makeshlibs) dh_shlibdeps -p$(p_gnatsjlj)
 	echo $(p_gnatsjlj) >> debian/arch_binaries
--- a/debian/rules.d/binary-fortran.mk
+++ b/debian/rules.d/binary-fortran.mk
@@ -97,7 +97,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgfortran.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
@@ -130,7 +130,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_l)
 	$(call cross_mangle_substvars,$(p_l))
 	echo $(p_l) >> debian/$(lib_binaries)
--- a/debian/rules.d/binary-go.mk
+++ b/debian/rules.d/binary-go.mk
@@ -120,7 +120,7 @@
 	  >> debian/$(p_l)/usr/share/lintian/overrides/$(p_l)
 
 	: # don't strip: https://gcc.gnu.org/ml/gcc-patches/2015-02/msg01722.html
-	: # dh_strip -p$(p_l) --dbg-package=$(p_d)
+	: # $(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libasan.mk
+++ b/debian/rules.d/binary-libasan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libatomic.mk
+++ b/debian/rules.d/binary-libatomic.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libatomic.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libcilkrts.mk
+++ b/debian/rules.d/binary-libcilkrts.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libcilkrts.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libgcc.mk
+++ b/debian/rules.d/binary-libgcc.mk
@@ -161,7 +161,7 @@
 	debian/dh_doclink -p$(2) $(p_lbase)
 	debian/dh_rmemptydirs -p$(2)
 
-	dh_strip -p$(2)
+	$(cross_strip) dh_strip -p$(2)
 	$(cross_shlibdeps) dh_shlibdeps -p$(2)
 	$(call cross_mangle_substvars,$(2))
 	echo $(2) >> debian/$(lib_binaries)
@@ -289,7 +289,7 @@
 	debian/dh_doclink -p$(p_d) $(if $(3),$(3),$(p_lbase))
 	debian/dh_rmemptydirs -p$(p_l)
 	debian/dh_rmemptydirs -p$(p_d)
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 
 	# see Debian #533843 for the __aeabi symbol handling; this construct is
 	# just to include the symbols for dpkg versions older than 1.15.3 which
--- a/debian/rules.d/binary-libgccjit.mk
+++ b/debian/rules.d/binary-libgccjit.mk
@@ -42,7 +42,7 @@
 	debian/dh_doclink -p$(p_jitdev) $(p_base)
 	debian/dh_doclink -p$(p_jitdbg) $(p_base)
 
-	dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
+	$(cross_strip) dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_jitlib)
 	$(call cross_mangle_shlibs,$(p_jitlib))
 	$(ignshld)$(cross_shlibdeps) dh_shlibdeps -p$(p_jitlib)
--- a/debian/rules.d/binary-libgomp.mk
+++ b/debian/rules.d/binary-libgomp.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgomp.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libitm.mk
+++ b/debian/rules.d/binary-libitm.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libitm.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-liblsan.mk
+++ b/debian/rules.d/binary-liblsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libmpx.mk
+++ b/debian/rules.d/binary-libmpx.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libmpx.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libobjc.mk
+++ b/debian/rules.d/binary-libobjc.mk
@@ -65,7 +65,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	rm -f debian/$(p_l).symbols
 	$(if $(2),
 	  ln -sf libobjc.symbols debian/$(p_l).symbols ,
--- a/debian/rules.d/binary-libquadmath.mk
+++ b/debian/rules.d/binary-libquadmath.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libquadmath.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libstdcxx.mk
+++ b/debian/rules.d/binary-libstdcxx.mk
@@ -207,7 +207,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
+	$(cross_strip) dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
 
 	$(if $(filter $(DEB_TARGET_ARCH), armel hppa sparc64), \
 	  -$(cross_makeshlibs) dh_makeshlibs -p$(p_l) \
@@ -237,7 +237,7 @@
 	$(if $(filter yes,$(with_lib$(2)cxx)),
 		cp -a $(d)/$(usr_lib$(2))/libstdc++.so.*[0-9] \
 			$(d_d)/$(usr_lib$(2))/.;
-		dh_strip -p$(p_d) --keep-debug;
+		$(cross_strip) dh_strip -p$(p_d) --keep-debug;
 		$(if $(filter yes,$(with_common_libs)),, # if !with_common_libs
 			# remove the debug symbols for libstdc++
 			# built by a newer version of GCC
@@ -283,7 +283,7 @@
 
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	dh_shlibdeps -p$(p_l) \
 		$(call shlibdirs_to_search,$(subst stdc++$(CXX_SONAME),gcc$(GCC_SONAME),$(p_l)),$(2))
 	echo $(p_l) >> debian/$(lib_binaries)
@@ -430,16 +430,16 @@
 ifeq ($(with_libcxx),yes)
 	cp -a $(d)/$(usr_lib)/libstdc++.so.*[0-9] \
 		$(d_dbg)/$(usr_lib)/
-	dh_strip -p$(p_dbg) --keep-debug
+	$(cross_strip) dh_strip -p$(p_dbg) --keep-debug
 	rm -f $(d_dbg)/$(usr_lib)/libstdc++.so.*[0-9]
 endif
 
-	dh_strip -p$(p_dev) --dbg-package=$(p_dbg)
+	$(cross_strip) dh_strip -p$(p_dev) --dbg-package=$(p_dbg)
 ifneq ($(with_common_libs),yes)
 	: # remove the debug symbols for libstdc++ built by a newer version of GCC
 	rm -rf $(d_dbg)/usr/lib/debug/$(PF)
 endif
-	dh_strip -p$(p_pic)
+	$(cross_strip) dh_strip -p$(p_pic)
 
 ifeq ($(with_cxxdev),yes)
 	debian/dh_rmemptydirs -p$(p_dev)
--- a/debian/rules.d/binary-libtsan.mk
+++ b/debian/rules.d/binary-libtsan.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libubsan.mk
+++ b/debian/rules.d/binary-libubsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libvtv.mk
+++ b/debian/rules.d/binary-libvtv.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -212,6 +212,7 @@
   cross_gencontrol = DEB_HOST_ARCH=$(TARGET)
   cross_makeshlibs = DEB_HOST_ARCH=$(TARGET)
   cross_clean = DEB_HOST_ARCH=$(TARGET)
+  cross_strip = dpkg-architecture -f -a$(TARGET) -c
 else
   TARGET_ALIAS := $(DEB_TARGET_GNU_TYPE)
 
@@ -240,6 +241,7 @@
   cross_gencontrol :=
   cross_makeshlibs :=
   cross_clean :=
+  cross_strip :=
 endif
 
 printarch:
EOF
	patch_gcc_multilib_deps
	echo "fix LIMITS_H_TEST again https://gcc.gnu.org/bugzilla/show_bug.cgi?id=80677"
	sed -i -e 's,^\(+LIMITS_H_TEST = \).*,\1:,' debian/patches/gcc-multiarch.diff
	patch_gcc_arm64ilp32
	patch_gcc_strict_debhelper_p
	patch_gcc_debhelper_skip_profile
	patch_gcc_wdotap
}
patch_gcc_8() {
	echo "patching gcc-8 to support building without binutils-multiarch #804190"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/binary-ada.mk
+++ b/debian/rules.d/binary-ada.mk
@@ -126,7 +126,7 @@
 		$(d_lgnat)/usr/share/lintian/overrides/$(p_lgnat)
 endif
 
-	dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_lgnat) \
 		$(call shlibdirs_to_search, \
 			$(subst gnat-$(GNAT_SONAME),gcc$(GCC_SONAME),$(p_lgnat)) \
@@ -347,7 +347,7 @@
 
 	debian/dh_rmemptydirs -p$(p_gnat)
 
-	dh_strip -p$(p_gnat)
+	$(cross_strip) dh_strip -p$(p_gnat)
 	find $(d_gnat) -name '*.ali' | xargs chmod 444
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_gnat) \
 		$(call shlibdirs_to_search, \
@@ -356,7 +356,7 @@
 	echo $(p_gnat) >> debian/arch_binaries
 
 ifeq ($(with_gnatsjlj),yes)
-	dh_strip -p$(p_gnatsjlj)
+	$(cross_strip) dh_strip -p$(p_gnatsjlj)
 	find $(d_gnatsjlj) -name '*.ali' | xargs chmod 444
 	$(cross_makeshlibs) dh_shlibdeps -p$(p_gnatsjlj)
 	echo $(p_gnatsjlj) >> debian/arch_binaries
--- a/debian/rules.d/binary-fortran.mk
+++ b/debian/rules.d/binary-fortran.mk
@@ -97,7 +97,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgfortran.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
@@ -130,7 +130,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_l)
 	$(call cross_mangle_substvars,$(p_l))
 	echo $(p_l) >> debian/$(lib_binaries)
--- a/debian/rules.d/binary-go.mk
+++ b/debian/rules.d/binary-go.mk
@@ -120,7 +120,7 @@
 	  >> debian/$(p_l)/usr/share/lintian/overrides/$(p_l)
 
 	: # don't strip: https://gcc.gnu.org/ml/gcc-patches/2015-02/msg01722.html
-	: # dh_strip -p$(p_l) --dbg-package=$(p_d)
+	: # $(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libasan.mk
+++ b/debian/rules.d/binary-libasan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libatomic.mk
+++ b/debian/rules.d/binary-libatomic.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libatomic.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libcilkrts.mk
+++ b/debian/rules.d/binary-libcilkrts.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libcilkrts.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libgcc.mk
+++ b/debian/rules.d/binary-libgcc.mk
@@ -161,7 +161,7 @@
 	debian/dh_doclink -p$(2) $(p_lbase)
 	debian/dh_rmemptydirs -p$(2)
 
-	dh_strip -p$(2)
+	$(cross_strip) dh_strip -p$(2)
 	$(cross_shlibdeps) dh_shlibdeps -p$(2)
 	$(call cross_mangle_substvars,$(2))
 	echo $(2) >> debian/$(lib_binaries)
@@ -289,7 +289,7 @@
 	debian/dh_doclink -p$(p_d) $(if $(3),$(3),$(p_lbase))
 	debian/dh_rmemptydirs -p$(p_l)
 	debian/dh_rmemptydirs -p$(p_d)
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 
 	# see Debian #533843 for the __aeabi symbol handling; this construct is
 	# just to include the symbols for dpkg versions older than 1.15.3 which
--- a/debian/rules.d/binary-libgccjit.mk
+++ b/debian/rules.d/binary-libgccjit.mk
@@ -42,7 +42,7 @@
 	debian/dh_doclink -p$(p_jitdev) $(p_base)
 	debian/dh_doclink -p$(p_jitdbg) $(p_base)
 
-	dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
+	$(cross_strip) dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_jitlib)
 	$(call cross_mangle_shlibs,$(p_jitlib))
 	$(ignshld)$(cross_shlibdeps) dh_shlibdeps -p$(p_jitlib)
--- a/debian/rules.d/binary-libgomp.mk
+++ b/debian/rules.d/binary-libgomp.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgomp.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libitm.mk
+++ b/debian/rules.d/binary-libitm.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libitm.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-liblsan.mk
+++ b/debian/rules.d/binary-liblsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libmpx.mk
+++ b/debian/rules.d/binary-libmpx.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libmpx.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libobjc.mk
+++ b/debian/rules.d/binary-libobjc.mk
@@ -65,7 +65,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	rm -f debian/$(p_l).symbols
 	$(if $(2),
 	  ln -sf libobjc.symbols debian/$(p_l).symbols ,
--- a/debian/rules.d/binary-libquadmath.mk
+++ b/debian/rules.d/binary-libquadmath.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libquadmath.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
--- a/debian/rules.d/binary-libstdcxx.mk
+++ b/debian/rules.d/binary-libstdcxx.mk
@@ -207,7 +207,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
+	$(cross_strip) dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
 
 	$(if $(filter $(DEB_TARGET_ARCH), armel hppa sparc64), \
 	  -$(cross_makeshlibs) dh_makeshlibs -p$(p_l) \
@@ -237,7 +237,7 @@
 	$(if $(filter yes,$(with_lib$(2)cxx)),
 		cp -a $(d)/$(usr_lib$(2))/libstdc++.so.*[0-9] \
 			$(d_d)/$(usr_lib$(2))/.;
-		dh_strip -p$(p_d) --keep-debug;
+		$(cross_strip) dh_strip -p$(p_d) --keep-debug;
 		$(if $(filter yes,$(with_common_libs)),, # if !with_common_libs
 			# remove the debug symbols for libstdc++
 			# built by a newer version of GCC
@@ -283,7 +283,7 @@
 
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	dh_shlibdeps -p$(p_l) \
 		$(call shlibdirs_to_search,$(subst stdc++$(CXX_SONAME),gcc$(GCC_SONAME),$(p_l)),$(2))
 	echo $(p_l) >> debian/$(lib_binaries)
@@ -430,16 +430,16 @@
 ifeq ($(with_libcxx),yes)
 	cp -a $(d)/$(usr_lib)/libstdc++.so.*[0-9] \
 		$(d_dbg)/$(usr_lib)/
-	dh_strip -p$(p_dbg) --keep-debug
+	$(cross_strip) dh_strip -p$(p_dbg) --keep-debug
 	rm -f $(d_dbg)/$(usr_lib)/libstdc++.so.*[0-9]
 endif
 
-	dh_strip -p$(p_dev) --dbg-package=$(p_dbg)
+	$(cross_strip) dh_strip -p$(p_dev) --dbg-package=$(p_dbg)
 ifneq ($(with_common_libs),yes)
 	: # remove the debug symbols for libstdc++ built by a newer version of GCC
 	rm -rf $(d_dbg)/usr/lib/debug/$(PF)
 endif
-	dh_strip -p$(p_pic)
+	$(cross_strip) dh_strip -p$(p_pic)
 
 ifeq ($(with_cxxdev),yes)
 	debian/dh_rmemptydirs -p$(p_dev)
--- a/debian/rules.d/binary-libtsan.mk
+++ b/debian/rules.d/binary-libtsan.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libubsan.mk
+++ b/debian/rules.d/binary-libubsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.d/binary-libvtv.mk
+++ b/debian/rules.d/binary-libvtv.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -212,6 +212,7 @@
   cross_gencontrol = DEB_HOST_ARCH=$(TARGET)
   cross_makeshlibs = DEB_HOST_ARCH=$(TARGET)
   cross_clean = DEB_HOST_ARCH=$(TARGET)
+  cross_strip = dpkg-architecture -f -a$(TARGET) -c
 else
   TARGET_ALIAS := $(DEB_TARGET_GNU_TYPE)
 
@@ -240,6 +241,7 @@
   cross_gencontrol :=
   cross_makeshlibs :=
   cross_clean :=
+  cross_strip :=
 endif
 
 printarch:
EOF
	patch_gcc_debhelper_skip_profile
	patch_gcc_wdotap
}
# choosing libatomic1 arbitrarily here, cause it never bumped soname
BUILD_GCC_MULTIARCH_VER=`apt-cache show --no-all-versions libatomic1 | sed 's/^Source: gcc-\([0-9.]*\)$/\1/;t;d'`
if test "$GCC_VER" != "$BUILD_GCC_MULTIARCH_VER"; then
	echo "host gcc version ($GCC_VER) and build gcc version ($BUILD_GCC_MULTIARCH_VER) mismatch. need different build gcc"
if dpkg --compare-versions "$GCC_VER" gt "$BUILD_GCC_MULTIARCH_VER"; then
	echo "deb [ arch=$(dpkg --print-architecture) ] $MIRROR experimental main" > /etc/apt/sources.list.d/tmp-experimental.list
	$APT_GET update
	$APT_GET -t experimental install gcc g++
	rm -f /etc/apt/sources.list.d/tmp-experimental.list
	$APT_GET update
elif test -f "$REPODIR/stamps/gcc_0"; then
	echo "skipping rebuild of build gcc"
	$APT_GET --force-yes dist-upgrade # downgrade!
else
	$APT_GET build-dep --arch-only gcc-$GCC_VER
	# dependencies for common libs no longer declared
	$APT_GET install doxygen graphviz ghostscript texlive-latex-base xsltproc docbook-xsl-ns
	cross_build_setup "gcc-$GCC_VER" gcc0
	drop_privs gcc_cv_libc_provides_ssp=yes DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,$GCC_NOLANG" dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	reprepro include rebootstrap-native ./*.changes
	drop_privs rm -fv ./*-plugin-dev_*.deb ./*-dbg_*.deb
	dpkg -i *.deb
	touch "$REPODIR/stamps/gcc_0"
	cd ..
	drop_privs rm -Rf gcc0
fi
progress_mark "build compiler complete"
else
echo "host gcc version and build gcc version match. good for multiarch"
fi

# binutils
patch_binutils() {
	if test "$HOST_ARCH" = "hurd-amd64"; then
		echo "patching binutils for hurd-amd64"
		drop_privs patch -p1 <<'EOF'
--- a/bfd/config.bfd
+++ b/bfd/config.bfd
@@ -671,7 +671,7 @@
     targ_selvecs="i386_elf32_vec i386_aout_nbsd_vec i386_coff_vec i386_pei_vec x86_64_pei_vec l1om_elf64_vec k1om_elf64_vec"
     want64=true
     ;;
-  x86_64-*-linux-*)
+  x86_64-*-linux-* | x86_64-*-gnu*)
     targ_defvec=x86_64_elf64_vec
     targ_selvecs="i386_elf32_vec x86_64_elf32_vec i386_aout_linux_vec i386_pei_vec x86_64_pei_vec l1om_elf64_vec k1om_elf64_vec"
     want64=true
--- a/ld/configure.tgt
+++ b/ld/configure.tgt
@@ -311,6 +311,7 @@
 i[3-7]86-*-mach*)	targ_emul=i386mach ;;
 i[3-7]86-*-gnu*)	targ_emul=elf_i386
 			targ_extra_emuls=elf_iamcu ;;
+x86_64-*-gnu*)		targ_emul=elf_x86_64 ;;
 i[3-7]86-*-msdos*)	targ_emul=i386msdos; targ_extra_emuls=i386aout ;;
 i[3-7]86-*-moss*)	targ_emul=i386moss; targ_extra_emuls=i386msdos ;;
 i[3-7]86-*-winnt*)	targ_emul=i386pe ;
EOF
	fi
	if test "$HOST_ARCH" = "kfreebsd-armhf"; then
		echo "patching binutils for kfreebsd-armhf"
		drop_privs patch -p1 <<'EOF'
--- a/bfd/config.bfd
+++ b/bfd/config.bfd
@@ -337,7 +337,7 @@
     targ_selvecs=arm_elf32_be_vec
     ;;
   arm-*-elf | arm*-*-freebsd* | arm*-*-linux-* | arm*-*-conix* | \
-  arm*-*-uclinux* | arm-*-kfreebsd*-gnu | \
+  arm*-*-uclinux* | arm-*-kfreebsd*-gnu* | \
   arm*-*-eabi* | arm-*-rtems*)
     targ_defvec=arm_elf32_le_vec
     targ_selvecs=arm_elf32_be_vec
--- a/gas/configure.tgt
+++ b/gas/configure.tgt
@@ -140,7 +140,8 @@
   arm-*-conix*)				fmt=elf ;;
   arm-*-freebsd[89].* | armeb-*-freebsd[89].*)
 					fmt=elf  em=freebsd ;;
-  arm-*-freebsd* | armeb-*-freebsd*)	fmt=elf  em=armfbsdeabi ;;
+  arm-*-freebsd* | armeb-*-freebsd* | arm-*-kfreebsd-gnueabi*)
+                                       fmt=elf  em=armfbsdeabi ;;
   arm*-*-freebsd*)			fmt=elf  em=armfbsdvfp ;;
   arm-*-linux*aout*)			fmt=aout em=linux ;;
   arm-*-linux-*eabi*)			fmt=elf  em=armlinuxeabi ;;
--- a/ld/configure.tgt
+++ b/ld/configure.tgt
@@ -83,7 +83,7 @@
 arm-*-coff)		targ_emul=armcoff ;;
 arm*b-*-freebsd*)	targ_emul=armelfb_fbsd
 			targ_extra_emuls="armelf_fbsd armelf" ;;
-arm*-*-freebsd* | arm-*-kfreebsd*-gnu)
+arm*-*-freebsd* | arm-*-kfreebsd*-gnu*)
 	       		targ_emul=armelf_fbsd
 			targ_extra_emuls="armelfb_fbsd armelf" ;;
 armeb-*-netbsdelf*)	targ_emul=armelfb_nbsd;
EOF
	fi
	echo "patching binutils to discard ldscripts"
	# They cause file conflicts with binutils and the in-archive cross
	# binutils discard ldscripts as well.
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -751,6 +751,7 @@
 		mandir=$(pwd)/$(D_CROSS)/$(PF)/share/man install
 
 	rm -rf \
+		$(D_CROSS)/$(PF)/lib/ldscripts \
 		$(D_CROSS)/$(PF)/share/info \
 		$(D_CROSS)/$(PF)/share/locale
 
EOF
	if test "$HOST_ARCH" = hppa; then
		echo "patching binutils to discard hppa64 ldscripts"
		# They cause file conflicts with binutils and the in-archive
		# cross binutils discard ldscripts as well.
		drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -1233,6 +1233,7 @@
 		$(d_hppa64)/$(PF)/lib/$(DEB_HOST_MULTIARCH)/.

 	: # Now get rid of just about everything in binutils-hppa64
+	rm -rf $(d_hppa64)/$(PF)/lib/ldscripts
 	rm -rf $(d_hppa64)/$(PF)/man
 	rm -rf $(d_hppa64)/$(PF)/info
 	rm -rf $(d_hppa64)/$(PF)/include
EOF
	fi
	echo "fixing TARGET= builds #876677"
	drop_privs sed -i -e '/^p_bld =/ap_cross = $(p_bin)-$(subst _,-,$(TARGET))\n' -e '/^d_bld =/ad_cross = debian/$(p_cross)' debian/rules
}
if test -f "$REPODIR/stamps/cross-binutils"; then
	echo "skipping rebuild of binutils-target"
else
	cross_build_setup binutils
	check_binNMU
	apt_get_build_dep --arch-only -Pnocheck ./
	drop_privs TARGET=$HOST_ARCH dpkg-buildpackage -B -Pnocheck --target=stamps/control
	drop_privs TARGET=$HOST_ARCH dpkg-buildpackage -B -uc -us -Pnocheck
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET install binutils$HOST_ARCH_SUFFIX
	assembler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-as"
	if ! which "$assembler"; then echo "$assembler missing in binutils package"; exit 1; fi
	if ! drop_privs "$assembler" -o test.o /dev/null; then echo "binutils fail to execute"; exit 1; fi
	if ! test -f test.o; then echo "binutils fail to create object"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	touch "$REPODIR/stamps/cross-binutils"
	cd ..
	drop_privs rm -Rf binutils
fi
progress_mark "cross binutils"

if test "$HOST_ARCH" = hppa && ! test -f "$REPODIR/stamps/cross-binutils-hppa64"; then
	cross_build_setup binutils binutils-hppa64
	check_binNMU
	apt_get_build_dep --arch-only -Pnocheck ./
	drop_privs TARGET=hppa64-linux-gnu dpkg-buildpackage -B -Pnocheck --target=stamps/control
	drop_privs TARGET=hppa64-linux-gnu dpkg-buildpackage -B -uc -us -Pnocheck
	cd ..
	ls -l
	pickup_additional_packages *.changes
	$APT_GET install binutils-hppa64-linux-gnu
	if ! which hppa64-linux-gnu-as; then echo "hppa64-linux-gnu-as missing in binutils package"; exit 1; fi
	if ! drop_privs hppa64-linux-gnu-as -o test.o /dev/null; then echo "binutils-hppa64 fail to execute"; exit 1; fi
	if ! test -f test.o; then echo "binutils-hppa64 fail to create object"; exit 1; fi
	check_arch test.o hppa64
	touch "$REPODIR/stamps/cross-binutils-hppa64"
	cd ..
	drop_privs rm -Rf binutils-hppa64-linux-gnu
	progress_mark "cross binutils-hppa64"
fi

# linux
patch_linux() {
	local kernel_arch comment
	kernel_arch=
	comment="just building headers yet"
	case "$HOST_ARCH" in
		arm|ia64|nios2)
			kernel_arch=$HOST_ARCH
		;;
		arm64ilp32) kernel_arch=arm64; ;;
		mipsr6|mipsr6el|mipsn32r6|mipsn32r6el|mips64r6|mips64r6el)
			kernel_arch=defines-only
		;;
		powerpcel) kernel_arch=powerpc; ;;
		riscv64) kernel_arch=riscv; ;;
		*-linux-*)
			if ! test -d "debian/config/$HOST_ARCH"; then
				kernel_arch=$(sed 's/^kernel-arch: //;t;d' < "debian/config/${HOST_ARCH#*-linux-}/defines")
				comment="$HOST_ARCH must be part of a multiarch installation with a ${HOST_ARCH#*-linux-*} kernel"
			fi
		;;
	esac
	if test -n "$kernel_arch"; then
		if test "$kernel_arch" != defines-only; then
			echo "patching linux for $HOST_ARCH with kernel-arch $kernel_arch"
			drop_privs mkdir -p "debian/config/$HOST_ARCH"
			drop_privs tee "debian/config/$HOST_ARCH/defines" >/dev/null <<EOF
[base]
kernel-arch: $kernel_arch
featuresets:
# empty; $comment
EOF
		else
			echo "patching linux to enable $HOST_ARCH"
		fi
		drop_privs sed -i -e "/^arches:/a\\ $HOST_ARCH" debian/config/defines
		apt_get_install kernel-wedge
		drop_privs ./debian/rules debian/rules.gen || : # intentionally exits 1 to avoid being called automatically. we are doing it wrong
	fi
}
if test "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS`" = "linux"; then
if test -f "$REPODIR/stamps/linux_1"; then
	echo "skipping rebuild of linux-libc-dev"
else
	cross_build_setup linux
	check_binNMU
	if dpkg-architecture -ilinux-any && test "$(dpkg-query -W -f '${Version}' "linux-libc-dev:$(dpkg --print-architecture)")" != "$(dpkg-parsechangelog -SVersion)"; then
		echo "rebootstrap-warning: working around linux-libc-dev m-a:same skew"
		apt_get_build_dep --arch-only -Pstage1 ./
		drop_privs KBUILD_VERBOSE=1 dpkg-buildpackage -B -Pstage1 -uc -us
	fi
	apt_get_build_dep --arch-only "-a$HOST_ARCH" -Pstage1 ./
	drop_privs KBUILD_VERBOSE=1 dpkg-buildpackage -B "-a$HOST_ARCH" -Pstage1 -uc -us
	cd ..
	ls -l
	if test "$ENABLE_MULTIARCH_GCC" != yes; then
		drop_privs dpkg-cross -M -a "$HOST_ARCH" -b ./*"_$HOST_ARCH.deb"
	fi
	pickup_packages *.deb
	touch "$REPODIR/stamps/linux_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf linux
fi
progress_mark "linux-libc-dev cross build"
fi

# gnumach
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -f "$REPODIR/stamps/gnumach_1"; then
	echo "skipping rebuild of gnumach stage1"
else
	$APT_GET install debhelper sharutils autoconf automake texinfo
	cross_build_setup gnumach gnumach_1
	drop_privs dpkg-buildpackage -B "-a$HOST_ARCH" -Pstage1 -uc -us
	cd ..
	pickup_packages ./*.deb
	touch "$REPODIR/stamps/gnumach_1"
	cd ..
	drop_privs rm -Rf gnumach_1
fi
progress_mark "gnumach stage1 cross build"
fi

if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = kfreebsd; then
cross_build kfreebsd-kernel-headers
fi

# gcc
if test -f "$REPODIR/stamps/gcc_1"; then
	echo "skipping rebuild of gcc stage1"
else
	apt_get_install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev sharutils "binutils$HOST_ARCH_SUFFIX"
	if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
		if test "$ENABLE_MULTIARCH_GCC" = yes; then
			apt_get_install "linux-libc-dev:$HOST_ARCH"
		else
			apt_get_install "linux-libc-dev-${HOST_ARCH}-cross"
		fi
	fi
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	cross_build_setup "gcc-$GCC_VER" gcc1
	dpkg-checkbuilddeps || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	if test "$ENABLE_MULTILIB" = yes; then
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=stage1 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=stage1 dpkg-buildpackage -d -b -uc -us
	else
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -b -uc -us
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	apt_get_remove gcc-multilib
	if test "$ENABLE_MULTILIB" = yes && ls | grep -q multilib; then
		$APT_GET install "gcc-$GCC_VER-multilib$HOST_ARCH_SUFFIX"
	else
		rm -vf ./*multilib*.deb
		$APT_GET install "gcc-$GCC_VER$HOST_ARCH_SUFFIX"
	fi
	compiler="`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage1 gcc package"; exit 1; fi
	if ! drop_privs "$compiler" -x c -c /dev/null -o test.o; then echo "stage1 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage1 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	touch "$REPODIR/stamps/gcc_1"
	cd ..
	drop_privs rm -Rf gcc1
fi
progress_mark "cross gcc stage1 build"

# replacement for cross-gcc-defaults
for prog in c++ cpp g++ gcc gcc-ar gcc-ranlib gfortran; do
	ln -fs "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-$prog-$GCC_VER" "/usr/bin/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-$prog"
done

# hurd
patch_hurd() {
	echo "working around #818618"
	sed -i -e '/^#.*818618/d;s/^#//' debian/control
}
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -f "$REPODIR/stamps/hurd_1"; then
	echo "skipping rebuild of hurd stage1"
else
	apt_get_install texinfo debhelper dh-exec autoconf dh-autoreconf gawk flex bison autotools-dev perl
	cross_build_setup hurd hurd_1
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1 || :
	drop_privs dpkg-buildpackage -d -B "-a$HOST_ARCH" -Pstage1 -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/hurd_1"
	cd ..
	drop_privs rm -Rf hurd_1
fi
progress_mark "hurd stage1 cross build"
fi

# mig
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -f "$REPODIR/stamps/mig_1"; then
	echo "skipping rebuild of mig cross"
else
	cross_build_setup mig mig_1
	apt_get_install dpkg-dev debhelper "gnumach-dev:$HOST_ARCH" flex libfl-dev bison dh-autoreconf
	drop_privs dpkg-buildpackage -d -B "--target-arch=$HOST_ARCH" -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/mig_1"
	cd ..
	drop_privs rm -Rf mig_1
fi
progress_mark "cross mig build"
fi

# libc
patch_glibc() {
	echo "patching glibc to select the correct packages in stage1"
	drop_privs patch -p1 <<EOF
diff -Nru glibc-2.19/debian/rules glibc-2.19/debian/rules
--- glibc-2.19/debian/rules
+++ glibc-2.19/debian/rules
@@ -196,6 +196,15 @@
   endif
 endif
 
+ifneq (\$(filter stage1,\$(DEB_BUILD_PROFILES)),)
+ifneq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+override GLIBC_PASSES = libc
+override DEB_ARCH_REGULAR_PACKAGES = \$(libc)-dev
+else
+override DEB_ARCH_REGULAR_PACKAGES := \$(foreach p,\$(DEB_ARCH_REGULAR_PACKAGES),\$(if \$(findstring -dev,\$(p)),\$(if \$(findstring -bin,\$(p)),,\$(p))))
+endif
+endif
+
 # And now the rules...
 include debian/rules.d/*.mk
 
EOF
	echo "patching eglibc to avoid dependency on libc6 from libc6-dev in stage1"
	drop_privs sed -i '/^Depends:/s/\(\(libc[0-9.]\+-[^d]\|@libc@\)[^,]*\)\(,\|$\)/\1 <!stage1>\3/g' debian/control.in/*
	echo "patching glibc to pass -l to dh_shlibdeps for multilib"
	drop_privs patch -p1 <<'EOF'
diff -Nru glibc-2.19/debian/rules.d/debhelper.mk glibc-2.19/debian/rules.d/debhelper.mk
--- glibc-2.19/debian/rules.d/debhelper.mk
+++ glibc-2.19/debian/rules.d/debhelper.mk
@@ -109,7 +109,7 @@
 	./debian/shlibs-add-udebs $(curpass)
 
 	dh_installdeb -p$(curpass)
-	dh_shlibdeps -p$(curpass)
+	dh_shlibdeps $(if $($(lastword $(subst -, ,$(curpass)))_slibdir),-l$(CURDIR)/debian/$(curpass)/$($(lastword $(subst -, ,$(curpass)))_slibdir)) -p$(curpass)
 	dh_gencontrol -p$(curpass)
 	if [ $(curpass) = nscd ] ; then \
 		sed -i -e "s/\(Depends:.*libc[0-9.]\+\)-[a-z0-9]\+/\1/" debian/nscd/DEBIAN/control ; \
EOF
	echo "patching glibc to find standard linux headers"
	drop_privs patch -p1 <<'EOF'
diff -Nru glibc-2.19/debian/sysdeps/linux.mk glibc-2.19/debian/sysdeps/linux.mk
--- glibc-2.19/debian/sysdeps/linux.mk
+++ glibc-2.19/debian/sysdeps/linux.mk
@@ -16,7 +16,7 @@
 endif

 ifndef LINUX_SOURCE
-  ifeq ($(DEB_HOST_GNU_TYPE),$(DEB_BUILD_GNU_TYPE))
+  ifeq ($(shell dpkg-query --status linux-libc-dev-$(DEB_HOST_ARCH)-cross 2>/dev/null),)
     LINUX_HEADERS := /usr/include
   else
     LINUX_HEADERS := /usr/$(DEB_HOST_GNU_TYPE)/include
EOF
	if ! grep -q '^libc[0-9_]\+_archs *:=.*\<'"$HOST_ARCH"'\>' debian/rules.d/control.mk; then
		echo "adding $HOST_ARCH to libc6_archs"
		drop_privs sed -i -e "s/^libc6_archs *:=.*/& $HOST_ARCH/" debian/rules.d/control.mk
		drop_privs ./debian/rules debian/control
	fi
	echo "patching glibc to drop dev package conflict"
	sed -i -e '/^Conflicts: @libc-dev-conflict@$/d' debian/control.in/libc
	echo "patching glibc to move all headers to multiarch locations #798955"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/build.mk
+++ b/debian/rules.d/build.mk
@@ -10,6 +10,20 @@
 define logme
 (exec 3>&1; exit `( ( ( $(2) ) 2>&1 3>&-; echo $$? >&4) | tee $(1) >&3) 4>&1`)
 endef
+define generic_multilib_extra_pkg_install
+set -e; \
+mkdir -p debian/$(1)/usr/include; \
+for i in `ls debian/tmp-libc/usr/include/$(DEB_HOST_MULTIARCH)`; do \
+	if test -d debian/tmp-libc/usr/include/$(DEB_HOST_MULTIARCH)/$$i && ! test $$i = bits -o $$i = gnu; then \
+		mkdir -p debian/$(1)/usr/include/$$i; \
+		for j in `ls debian/tmp-libc/usr/include/$(DEB_HOST_MULTIARCH)/$$i`; do \
+			ln -sf ../$(DEB_HOST_MULTIARCH)/$$i/$$j debian/$(1)/usr/include/$$i/$$j; \
+		done; \
+	else \
+		ln -sf $(DEB_HOST_MULTIARCH)/$$i debian/$(1)/usr/include/$$i; \
+	fi; \
+done
+endef
 
 ifneq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
     libc_extra_config_options = $(extra_config_options) --disable-sanity-checks \
@@ -218,13 +218,9 @@
 	    echo "/lib/$(DEB_HOST_GNU_TYPE)" >> $$conffile; \
 	    echo "/usr/lib/$(DEB_HOST_GNU_TYPE)" >> $$conffile; \
 	  fi; \
-	  mkdir -p debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
-	  mv debian/tmp-$(curpass)/usr/include/bits debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
-	  mv debian/tmp-$(curpass)/usr/include/gnu debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
-	  mv debian/tmp-$(curpass)/usr/include/sys debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
-	  mv debian/tmp-$(curpass)/usr/include/fpu_control.h debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
-	  mv debian/tmp-$(curpass)/usr/include/a.out.h debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
-	  mv debian/tmp-$(curpass)/usr/include/ieee754.h debian/tmp-$(curpass)/usr/include/$(DEB_HOST_MULTIARCH); \
+	  mkdir -p debian/tmp-$(curpass)/usr/include.tmp; \
+	  mv debian/tmp-$(curpass)/usr/include debian/tmp-$(curpass)/usr/include.tmp/$(DEB_HOST_MULTIARCH); \
+	  mv debian/tmp-$(curpass)/usr/include.tmp debian/tmp-$(curpass)/usr/include; \
 	fi
 
 	# For our biarch libc, add an ld.so.conf.d configuration; this
--- a/debian/sysdeps/ppc64.mk
+++ b/debian/sysdeps/ppc64.mk
@@ -15,19 +15,11 @@

 define libc6-dev-powerpc_extra_pkg_install

-mkdir -p debian/libc6-dev-powerpc/usr/include
-ln -s powerpc64-linux-gnu/bits debian/libc6-dev-powerpc/usr/include/
-ln -s powerpc64-linux-gnu/gnu debian/libc6-dev-powerpc/usr/include/
-ln -s powerpc64-linux-gnu/fpu_control.h debian/libc6-dev-powerpc/usr/include/
+$(call generic_multilib_extra_pkg_install,libc6-dev-powerpc)

 mkdir -p debian/libc6-dev-powerpc/usr/include/powerpc64-linux-gnu/gnu
 cp -a debian/tmp-powerpc/usr/include/gnu/stubs-32.h \
         debian/libc6-dev-powerpc/usr/include/powerpc64-linux-gnu/gnu
-
-mkdir -p debian/libc6-dev-powerpc/usr/include/sys
-for i in `ls debian/tmp-libc/usr/include/powerpc64-linux-gnu/sys` ; do \
-        ln -s ../powerpc64-linux-gnu/sys/$$i debian/libc6-dev-powerpc/usr/include/sys/$$i ; \
-done

 endef

--- a/debian/sysdeps/mips.mk
+++ b/debian/sysdeps/mips.mk
@@ -31,19 +31,11 @@

 define libc6-dev-mips64_extra_pkg_install
 
-mkdir -p debian/libc6-dev-mips64/usr/include
-ln -sf mips-linux-gnu/bits debian/libc6-dev-mips64/usr/include/
-ln -sf mips-linux-gnu/gnu debian/libc6-dev-mips64/usr/include/
-ln -sf mips-linux-gnu/fpu_control.h debian/libc6-dev-mips64/usr/include/
+$(call generic_multilib_extra_pkg_install,libc6-dev-mips64)
 
 mkdir -p debian/libc6-dev-mips64/usr/include/mips-linux-gnu/gnu
 cp -a debian/tmp-mips64/usr/include/gnu/stubs-n64_hard.h \
         debian/libc6-dev-mips64/usr/include/mips-linux-gnu/gnu
-
-mkdir -p debian/libc6-dev-mips64/usr/include/sys
-for i in `ls debian/tmp-libc/usr/include/mips-linux-gnu/sys` ; do \
-        ln -sf ../mips-linux-gnu/sys/$$i debian/libc6-dev-mips64/usr/include/sys/$$i ; \
-done
 
 endef
 
--- a/debian/sysdeps/mipsel.mk
+++ b/debian/sysdeps/mipsel.mk
@@ -31,19 +31,11 @@

 define libc6-dev-mips64_extra_pkg_install

-mkdir -p debian/libc6-dev-mips64/usr/include
-ln -sf mipsel-linux-gnu/bits debian/libc6-dev-mips64/usr/include/
-ln -sf mipsel-linux-gnu/gnu debian/libc6-dev-mips64/usr/include/
-ln -sf mipsel-linux-gnu/fpu_control.h debian/libc6-dev-mips64/usr/include/
+$(call generic_multilib_extra_pkg_install,libc6-dev-mips64)

 mkdir -p debian/libc6-dev-mips64/usr/include/mipsel-linux-gnu/gnu
 cp -a debian/tmp-mips64/usr/include/gnu/stubs-n64_hard.h \
         debian/libc6-dev-mips64/usr/include/mipsel-linux-gnu/gnu
-
-mkdir -p debian/libc6-dev-mips64/usr/include/sys
-for i in `ls debian/tmp-libc/usr/include/mipsel-linux-gnu/sys` ; do \
-        ln -sf ../mipsel-linux-gnu/sys/$$i debian/libc6-dev-mips64/usr/include/sys/$$i ; \
-done

 endef

--- a/debian/sysdeps/powerpc.mk
+++ b/debian/sysdeps/powerpc.mk
@@ -15,19 +15,11 @@

 define libc6-dev-ppc64_extra_pkg_install

-mkdir -p debian/libc6-dev-ppc64/usr/include
-ln -s powerpc-linux-gnu/bits debian/libc6-dev-ppc64/usr/include/
-ln -s powerpc-linux-gnu/gnu debian/libc6-dev-ppc64/usr/include/
-ln -s powerpc-linux-gnu/fpu_control.h debian/libc6-dev-ppc64/usr/include/
+$(call generic_multilib_extra_pkg_install,libc6-dev-ppc64)

 mkdir -p debian/libc6-dev-ppc64/usr/include/powerpc-linux-gnu/gnu
 cp -a debian/tmp-ppc64/usr/include/gnu/stubs-64-v1.h \
         debian/libc6-dev-ppc64/usr/include/powerpc-linux-gnu/gnu
-
-mkdir -p debian/libc6-dev-ppc64/usr/include/sys
-for i in `ls debian/tmp-libc/usr/include/powerpc-linux-gnu/sys` ; do \
-        ln -s ../powerpc-linux-gnu/sys/$$i debian/libc6-dev-ppc64/usr/include/sys/$$i ; \
-done

 endef

--- a/debian/sysdeps/s390x.mk
+++ b/debian/sysdeps/s390x.mk
@@ -14,19 +14,11 @@

 define libc6-dev-s390_extra_pkg_install

-mkdir -p debian/libc6-dev-s390/usr/include
-ln -s s390x-linux-gnu/bits debian/libc6-dev-s390/usr/include/
-ln -s s390x-linux-gnu/gnu debian/libc6-dev-s390/usr/include/
-ln -s s390x-linux-gnu/fpu_control.h debian/libc6-dev-s390/usr/include/
+$(call generic_multilib_extra_pkg_install,libc6-dev-s390)

 mkdir -p debian/libc6-dev-s390/usr/include/s390x-linux-gnu/gnu
 cp -a debian/tmp-s390/usr/include/gnu/stubs-32.h \
         debian/libc6-dev-s390/usr/include/s390x-linux-gnu/gnu
-
-mkdir -p debian/libc6-dev-s390/usr/include/sys
-for i in `ls debian/tmp-libc/usr/include/s390x-linux-gnu/sys` ; do \
-        ln -s ../s390x-linux-gnu/sys/$$i debian/libc6-dev-s390/usr/include/sys/$$i ; \
-done

 endef

--- a/debian/sysdeps/sparc.mk
+++ b/debian/sysdeps/sparc.mk
@@ -15,18 +15,10 @@

 define libc6-dev-sparc64_extra_pkg_install

-mkdir -p debian/libc6-dev-sparc64/usr/include
-ln -s sparc-linux-gnu/bits debian/libc6-dev-sparc64/usr/include/
-ln -s sparc-linux-gnu/gnu debian/libc6-dev-sparc64/usr/include/
-ln -s sparc-linux-gnu/fpu_control.h debian/libc6-dev-sparc64/usr/include/
+$(call generic_multilib_extra_pkg_install,libc6-dev-sparc64)

 mkdir -p debian/libc6-dev-sparc64/usr/include/sparc-linux-gnu/gnu
 cp -a debian/tmp-sparc64/usr/include/gnu/stubs-64.h \
         debian/libc6-dev-sparc64/usr/include/sparc-linux-gnu/gnu
-
-mkdir -p debian/libc6-dev-sparc64/usr/include/sys
-for i in `ls debian/tmp-libc/usr/include/sparc-linux-gnu/sys` ; do \
-        ln -s ../sparc-linux-gnu/sys/$$i debian/libc6-dev-sparc64/usr/include/sys/$$i ; \
-done

 endef
EOF
	echo "patching glibc to work with regular kfreebsd-kernel-headers"
	drop_privs patch -p1 <<'EOF'
--- a/debian/sysdeps/kfreebsd.mk
+++ b/debian/sysdeps/kfreebsd.mk
@@ -13,7 +13,7 @@
 libc_extra_config_options = $(extra_config_options)

 ifndef KFREEBSD_SOURCE
-  ifeq ($(DEB_HOST_GNU_TYPE),$(DEB_BUILD_GNU_TYPE))
+  ifeq ($(shell dpkg-query --status kfreebsd-kernel-headers-$(DEB_HOST_ARCH)-cross 2>/dev/null),)
     KFREEBSD_HEADERS := /usr/include
   else
     KFREEBSD_HEADERS := /usr/$(DEB_HOST_GNU_TYPE)/include
EOF
	echo "patching glibc to avoid -Werror"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/build.mk
+++ b/debian/rules.d/build.mk
@@ -85,6 +85,7 @@
 		$(CURDIR)/configure \
 		--host=$(call xx,configure_target) \
 		--build=$$configure_build --prefix=/usr \
+		--disable-werror \
 		--enable-add-ons=$(standard-add-ons)"$(call xx,add-ons)" \
 		--without-selinux \
 		--enable-stackguard-randomization \
EOF
	echo "patching glibc for sh3 #851867"
	drop_privs cp -nv debian/sysdeps/sh4.mk debian/sysdeps/sh3.mk
}
if test -f "$REPODIR/stamps/${LIBC_NAME}_1"; then
	echo "skipping rebuild of $LIBC_NAME stage1"
else
	if test "$LIBC_NAME" = musl; then
		$APT_GET build-dep "-a$HOST_ARCH" --arch-only musl
	else
		$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks binutils bison netbase "gcc-$GCC_VER$HOST_ARCH_SUFFIX"
		case "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" in
			linux)
				if test "$ENABLE_MULTIARCH_GCC" = yes; then
					$APT_GET install "linux-libc-dev:$HOST_ARCH"
				else
					$APT_GET install "linux-libc-dev-$HOST_ARCH-cross"
				fi
			;;
			hurd)
				apt_get_install "gnumach-dev:$HOST_ARCH" "hurd-headers-dev:$HOST_ARCH" "mig$HOST_ARCH_SUFFIX"
			;;
			kfreebsd)
				$APT_GET install "kfreebsd-kernel-headers:$HOST_ARCH"
			;;
			*)
				echo "rebootstrap-error: unsupported kernel"
				exit 1
			;;
		esac
	fi
	cross_build_setup "$LIBC_NAME" "${LIBC_NAME}1"
	if test "$ENABLE_MULTILIB" = yes; then
		dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1 || : # tell unmet build depends
		drop_privs DEB_GCC_VERSION="-$GCC_VER" dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -d -Pstage1
	else
		dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1,nobiarch || : # tell unmet build depends
		drop_privs DEB_GCC_VERSION="-$GCC_VER" dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -d -Pstage1,nobiarch
	fi
	cd ..
	ls -l
	apt_get_remove libc6-dev-i386
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
			$APT_GET install "linux-libc-dev:$HOST_ARCH"
		fi
		pickup_packages *.changes
		if test "$LIBC_NAME" = musl; then
			dpkg -i musl*.deb
		else
			dpkg -i libc*.deb
		fi
	else
		if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
			$APT_GET install "linux-libc-dev-$HOST_ARCH-cross"
		fi
		for pkg in *.deb; do
			drop_privs dpkg-cross -M -a "$HOST_ARCH" -X tzdata -X libc-bin -X libc-dev-bin -b "$pkg"
		done
		pickup_packages *.changes *-cross_*.deb
		dpkg -i libc*-cross_*.deb
	fi
	touch "$REPODIR/stamps/${LIBC_NAME}_1"
	cd ..
	drop_privs rm -Rf "${LIBC_NAME}1"
fi
progress_mark "$LIBC_NAME stage1 cross build"

# dpkg happily breaks depends when upgrading build arch multilibs to host arch multilibs
apt_get_remove $(dpkg-query -W "lib*gcc*:$(dpkg --print-architecture)" | sed "s/\\s.*//;/:$(dpkg --print-architecture)/d")

if test "$LIBC_NAME" != musl; then

if test -f "$REPODIR/stamps/gcc_2"; then
	echo "skipping rebuild of gcc stage2"
else
	apt_get_install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev sharutils "binutils$HOST_ARCH_SUFFIX"
	if test "$ENABLE_MULTIARCH_GCC" = yes -o "$LIBC_NAME" != glibc; then
		apt_get_install "libc-dev:$HOST_ARCH"
	else
		apt_get_install "libc6-dev-${HOST_ARCH}-cross"
	fi
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	cross_build_setup "gcc-$GCC_VER" gcc2
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	(
		export DEB_STAGE=stage2
		if test "$ENABLE_MULTILIB" = yes; then
			nolang="${GCC_NOLANG:+nolang=$GCC_NOLANG}"
		else
			nolang="nolang=${GCC_NOLANG:+$GCC_NOLANG,}biarch"
		fi
		export DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS${nolang:+ $nolang}"
		if test "$ENABLE_MULTIARCH_GCC" = yes; then
			export with_deps_on_target_arch_pkgs=yes
		fi
		export gcc_cv_libc_provides_ssp=yes
		export gcc_cv_initfini_array=yes
		drop_privs dpkg-buildpackage -d -T control
		drop_privs dpkg-buildpackage -d -T clean
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs_exec dpkg-buildpackage -d -b -uc -us
	)
	cd ..
	ls -l
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		drop_privs changestool ./*.changes dumbremove "gcc-${GCC_VER}-base_"*"_$(dpkg --print-architecture).deb"
		drop_privs rm "gcc-${GCC_VER}-base_"*"_$(dpkg --print-architecture).deb"
	fi
	pickup_packages *.changes
	drop_privs rm -vf ./*multilib*.deb
	dpkg -i *.deb
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage2 gcc package"; exit 1; fi
	if ! drop_privs "$compiler" -x c -c /dev/null -o test.o; then echo "stage2 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage2 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	touch "$REPODIR/stamps/gcc_2"
	cd ..
	drop_privs rm -Rf gcc2
fi
progress_mark "cross gcc stage2 build"

if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -f "$REPODIR/stamps/hurd_2"; then
	echo "skipping rebuild of hurd stage2"
else
	apt_get_install texinfo debhelper dh-exec autoconf dh-autoreconf gawk flex bison autotools-dev "libc-dev:$HOST_ARCH" perl
	cross_build_setup hurd hurd_2
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage2 || :
	drop_privs dpkg-buildpackage -d -B "-a$HOST_ARCH" -Pstage2 -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/hurd_2"
	cd ..
	drop_privs rm -Rf hurd_2
fi
progress_mark "hurd stage2 cross build"
fi

# several undeclared file conflicts such as #745552 or #784015
apt_get_remove $(dpkg-query -W "libc[0-9]*:$(dpkg --print-architecture)" | sed "s/\\s.*//;/:$(dpkg --print-architecture)/d")

if test -f "$REPODIR/stamps/${LIBC_NAME}_2"; then
	echo "skipping rebuild of $LIBC_NAME stage2"
else
	$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks binutils bison netbase "gcc-$GCC_VER$HOST_ARCH_SUFFIX"
	case "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" in
		linux)
			if test "$ENABLE_MULTIARCH_GCC" = yes; then
				$APT_GET install "linux-libc-dev:$HOST_ARCH"
			else
				$APT_GET install "linux-libc-dev-$HOST_ARCH-cross"
			fi
		;;
		hurd)
			apt_get_install "gnumach-dev:$HOST_ARCH" "hurd-headers-dev:$HOST_ARCH" "libihash-dev:$HOST_ARCH" "mig$HOST_ARCH_SUFFIX"
		;;
		kfreebsd)
			$APT_GET install "kfreebsd-kernel-headers:$HOST_ARCH"
		;;
		*)
			echo "rebootstrap-error: unsupported kernel"
			exit 1
		;;
	esac
	cross_build_setup "$LIBC_NAME" "${LIBC_NAME}2"
	if test "$ENABLE_MULTILIB" = yes; then
		dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage2 || : # tell unmet build depends
		drop_privs DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -d -Pstage2
	else
		dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage2,nobiarch || : # tell unmet build depends
		drop_privs DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -d -Pstage2,nobiarch
	fi
	cd ..
	ls -l
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		pickup_packages *.changes
		$APT_GET dist-upgrade
	else
		for pkg in libc[0-9]*.deb; do
			# dpkg-cross cannot handle these
			test "${pkg%%_*}" = "libc6-i686" && continue
			test "${pkg%%_*}" = "libc6-loongson2f" && continue
			test "${pkg%%_*}" = "libc6-xen" && continue
			test "${pkg%%_*}" = "libc6.1-alphaev67" && continue
			drop_privs dpkg-cross -M -a "$HOST_ARCH" -X tzdata -X libc-bin -X libc-dev-bin -X multiarch-support -b "$pkg"
		done
		pickup_packages *.changes *-cross_*.deb
		$APT_GET dist-upgrade
	fi
	touch "$REPODIR/stamps/${LIBC_NAME}_2"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf "${LIBC_NAME}2"
fi
progress_mark "$LIBC_NAME stage2 cross build"

fi # $LIBC_NAME != musl

if test -f "$REPODIR/stamps/gcc_3"; then
	echo "skipping rebuild of gcc stage3"
else
	apt_get_install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen systemtap-sdt-dev sharutils "binutils$HOST_ARCH_SUFFIX"
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		apt_get_install "libc-dev:$HOST_ARCH" $(echo $MULTILIB_NAMES | sed "s/\(\S\+\)/libc6-dev-\1:$HOST_ARCH/g")
	else
		case "$LIBC_NAME" in
			glibc)
				apt_get_install "libc6-dev-$HOST_ARCH-cross" $(echo $MULTILIB_NAMES | sed "s/\(\S\+\)/libc6-dev-\1-$HOST_ARCH-cross/g")
			;;
			musl)
				apt_get_install "musl-dev-$HOST_ARCH-cross"
			;;
		esac
	fi
	cross_build_setup "gcc-$GCC_VER" gcc3
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	(
		if test "$ENABLE_MULTILIB" = yes; then
			nolang="${GCC_NOLANG:+nolang=$GCC_NOLANG}"
		else
			nolang="nolang=${GCC_NOLANG:+$GCC_NOLANG,}biarch"
		fi
		export DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS${nolang:+ $nolang}"
		if test "$ENABLE_MULTIARCH_GCC" = yes; then
			export with_deps_on_target_arch_pkgs=yes
		else
			export WITH_SYSROOT=/
		fi
		export gcc_cv_libc_provides_ssp=yes
		export gcc_cv_initfini_array=yes
		drop_privs dpkg-buildpackage -d -T control
		drop_privs dpkg-buildpackage -d -T clean
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs_exec dpkg-buildpackage -d -b -uc -us
	)
	cd ..
	ls -l
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		drop_privs changestool ./*.changes dumbremove "gcc-${GCC_VER}-base_"*"_$(dpkg --print-architecture).deb"
		drop_privs rm "gcc-${GCC_VER}-base_"*"_$(dpkg --print-architecture).deb"
	fi
	pickup_packages *.changes
	# avoid file conflicts between differently staged M-A:same packages
	apt_get_remove "gcc-$GCC_VER-base:$HOST_ARCH"
	drop_privs rm -fv gcc-*-plugin-*.deb gcj-*.deb gdc-*.deb ./*objc*.deb ./*-dbg_*.deb
	dpkg -i *.deb
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage3 gcc package"; exit 1; fi
	if ! drop_privs "$compiler" -x c -c /dev/null -o test.o; then echo "stage3 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage3 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	mkdir -p "/usr/include/$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH)"
	touch /usr/include/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH`/include_path_test_header.h
	preproc="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-cpp-$GCC_VER"
	if ! echo '#include "include_path_test_header.h"' | drop_privs "$preproc" -E -; then echo "stage3 gcc fails to search /usr/include/<triplet>"; exit 1; fi
	touch "$REPODIR/stamps/gcc_3"
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		compare_native ./*.deb
	fi
	cd ..
	drop_privs rm -Rf gcc3
fi
progress_mark "cross gcc stage3 build"

if test "$ENABLE_MULTIARCH_GCC" != yes; then
if test -f "$REPODIR/stamps/gcc_f1"; then
	echo "skipping rebuild of gcc rtlibs"
else
	apt_get_install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen systemtap-sdt-dev sharutils "binutils$HOST_ARCH_SUFFIX" "libc-dev:$HOST_ARCH"
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	if test "$ENABLE_MULTILIB" = yes -a -n "$MULTILIB_NAMES"; then
		$APT_GET install $(echo $MULTILIB_NAMES | sed "s/\(\S\+\)/libc6-dev-\1-$HOST_ARCH-cross libc6-dev-\1:$HOST_ARCH/g")
	fi
	cross_build_setup "gcc-$GCC_VER" gcc_f1
	dpkg-checkbuilddeps || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	export WITH_SYSROOT=/
	if test "$ENABLE_MULTILIB" = yes; then
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=rtlibs dpkg-buildpackage -d -T control
		cat debian/control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=rtlibs dpkg-buildpackage -d -b -uc -us
	else
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG,biarch" DEB_STAGE=rtlibs dpkg-buildpackage -d -T control
		cat debian/control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG,biarch" DEB_STAGE=rtlibs dpkg-buildpackage -d -b -uc -us
	fi
	unset WITH_SYSROOT
	cd ..
	ls -l
	rm -vf "gcc-$GCC_VER-base_"*"_$(dpkg --print-architecture).deb"
	pickup_additional_packages *.deb
	$APT_GET dist-upgrade
	dpkg -i ./*.deb
	touch "$REPODIR/stamps/gcc_f1"
	cd ..
	drop_privs rm -Rf gcc_f1
fi
progress_mark "gcc cross rtlibs build"
fi

apt_get_remove libc6-i386 # breaks cross builds

if dpkg-architecture "-a$HOST_ARCH" -ihurd-any; then
if test -f "$REPODIR/stamps/hurd_3"; then
	echo "skipping rebuild of hurd stage3"
else
	apt_get_install "gnumach-dev:$HOST_ARCH" "libc0.3-dev:$HOST_ARCH" texinfo debhelper dpkg-dev dh-exec autoconf dh-autoreconf gawk flex bison autotools-dev
	cross_build_setup hurd hurd_3
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage3 || : # gcc-5 dependency unsatisfiable
	drop_privs dpkg-buildpackage -d -B "-a$HOST_ARCH" -Pstage3 -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/hurd_3"
	cd ..
	drop_privs rm -Rf hurd_3
fi
apt_get_install "hurd-dev:$HOST_ARCH"
progress_mark "hurd stage3 cross build"
fi

automatic_packages=
add_automatic() { automatic_packages=`set_add "$automatic_packages" "$1"`; }

add_automatic acl

add_automatic adns
patch_adns() {
	echo "patching adns to support DEB_BUILD_OPTIONS=nocheck #812229"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -15,7 +15,9 @@
 	dh build --before configure
 	dh_auto_configure
 	dh_auto_build
+ifeq ($(filter nocheck,$(DEB_BUILD_OPTIONS)),)
 	make -C regress check
+endif
 	dh build --after test
 	touch $@
 
EOF
}

builddep_apt() {
	# g++ dependency needs toolchain translation
	apt_get_install cmake debhelper dh-systemd docbook-xml docbook-xsl dpkg-dev gettext "libbz2-dev:$1" "libcurl4-gnutls-dev:$1" "libdb-dev:$1" "libgnutls28-dev:$1" "liblz4-dev:$1" "liblzma-dev:$1" pkg-config po4a xsltproc "zlib1g-dev:$1"
}

add_automatic attr
patch_attr() {
	echo "patching attr to support musl #782830"
	drop_privs patch -p1 <<'EOF'
diff -Nru attr-2.4.47/debian/patches/20-remove-attr-xattr.patch attr-2.4.47/debian/patches/20-remove-attr-xattr.patch
--- attr-2.4.47/debian/patches/20-remove-attr-xattr.patch
+++ attr-2.4.47/debian/patches/20-remove-attr-xattr.patch
@@ -0,0 +1,89 @@
+Description: Backport upstream patch for musl support
+ Drop attr/xattr.h and use sys/xattr.h from libc instead.
+Author: Szabolcs Nagy <nsz@port70.net>
+Origin: upstream, http://git.savannah.gnu.org/cgit/attr.git/commit/?id=7921157890d07858d092f4003ca4c6bae9fd2c38
+Last-Update: 2015-04-18
+
+Index: attr-2.4.47/include/attributes.h
+===================================================================
+--- attr-2.4.47.orig/include/attributes.h
++++ attr-2.4.47/include/attributes.h
+@@ -21,6 +21,10 @@
+ #ifdef __cplusplus
+ extern "C" {
+ #endif
++#include <errno.h>
++#ifndef ENOATTR
++# define ENOATTR ENODATA
++#endif
+ 
+ /*
+  *	An almost-IRIX-compatible extended attributes API
+Index: attr-2.4.47/include/xattr.h
+===================================================================
+--- attr-2.4.47.orig/include/xattr.h
++++ attr-2.4.47/include/xattr.h
+@@ -19,45 +19,13 @@
+  */
+ #ifndef __XATTR_H__
+ #define __XATTR_H__
+ 
+ #include <features.h>
+ 
++#include <sys/xattr.h>
+ #include <errno.h>
+ #ifndef ENOATTR
+ # define ENOATTR ENODATA        /* No such attribute */
+ #endif
+-
+-#define XATTR_CREATE  0x1       /* set value, fail if attr already exists */
+-#define XATTR_REPLACE 0x2       /* set value, fail if attr does not exist */
+-
+-
+-__BEGIN_DECLS
+-
+-extern int setxattr (const char *__path, const char *__name,
+-		      const void *__value, size_t __size, int __flags) __THROW;
+-extern int lsetxattr (const char *__path, const char *__name,
+-		      const void *__value, size_t __size, int __flags) __THROW;
+-extern int fsetxattr (int __filedes, const char *__name,
+-		      const void *__value, size_t __size, int __flags) __THROW;
+-
+-extern ssize_t getxattr (const char *__path, const char *__name,
+-				void *__value, size_t __size) __THROW;
+-extern ssize_t lgetxattr (const char *__path, const char *__name,
+-				void *__value, size_t __size) __THROW;
+-extern ssize_t fgetxattr (int __filedes, const char *__name,
+-				void *__value, size_t __size) __THROW;
+-
+-extern ssize_t listxattr (const char *__path, char *__list,
+-				size_t __size) __THROW;
+-extern ssize_t llistxattr (const char *__path, char *__list,
+-				size_t __size) __THROW;
+-extern ssize_t flistxattr (int __filedes, char *__list,
+-				size_t __size) __THROW;
+-
+-extern int removexattr (const char *__path, const char *__name) __THROW;
+-extern int lremovexattr (const char *__path, const char *__name) __THROW;
+-extern int fremovexattr (int __filedes,   const char *__name) __THROW;
+-
+-__END_DECLS
+ 
+ #endif	/* __XATTR_H__ */
+Index: attr-2.4.47/libattr/Makefile
+===================================================================
+--- attr-2.4.47.orig/libattr/Makefile
++++ attr-2.4.47/libattr/Makefile
+@@ -29,12 +29,6 @@ LT_AGE = 1
+ CFILES = libattr.c attr_copy_fd.c attr_copy_file.c attr_copy_check.c attr_copy_action.c
+ HFILES = libattr.h
+ 
+-ifeq ($(PKG_PLATFORM),linux)
+-CFILES += syscalls.c
+-else
+-LSRCFILES = syscalls.c
+-endif
+-
+ LCFLAGS = -include libattr.h
+ 
+ default: $(LTLIBRARY)
diff -Nru attr-2.4.47/debian/patches/series attr-2.4.47/debian/patches/series
--- attr-2.4.47/debian/patches/series
+++ attr-2.4.47/debian/patches/series
@@ -1,3 +1,4 @@
 01-configure.in.patch
 02-687531-fix-missing-ldflags.patch
 12-643587-attr-autoconf-version-check.patch
+20-remove-attr-xattr.patch
EOF
	drop_privs quilt push -a
}

add_automatic autogen
add_automatic base-files
add_automatic bash

builddep_build_essential() {
	# g++ dependency needs cross translation
	$APT_GET install debhelper python3
}

add_automatic bzip2
add_automatic c-ares

add_automatic cloog
builddep_cloog() {
	$APT_GET install debhelper dh-autoreconf "libisl-dev:$1" "libgmp-dev:$1" texinfo help2man
}
patch_cloog() {
	echo "patching cloog to fix build on ppc64el #801337"
	drop_privs patch -p1 <<'EOF'
diff -Nru cloog-0.18.3/debian/control cloog-0.18.3/debian/control
--- cloog-0.18.3/debian/control
+++ cloog-0.18.3/debian/control
@@ -2,7 +2,7 @@
 Priority: optional
 Maintainer: Debian GCC Maintainers <debian-gcc@lists.debian.org>
 Uploaders: Matthias Klose <doko@debian.org>, Michael Tautschnig <mt@debian.org>
-Build-Depends: debhelper (>= 5), autotools-dev,
+Build-Depends: debhelper (>= 5), dh-autoreconf,
   libisl-dev (>= 0.15), libgmp-dev,
   texinfo, help2man
 # Build-Depends-Indep: libpod-latex-perl | perl (<< 5.17.0) # not needed, no docs built
diff -Nru cloog-0.18.3/debian/patches/series cloog-0.18.3/debian/patches/series
--- cloog-0.18.3/debian/patches/series
+++ cloog-0.18.3/debian/patches/series
@@ -0,0 +1 @@
+use_autoreconf.patch
diff -Nru cloog-0.18.3/debian/patches/use_autoreconf.patch cloog-0.18.3/debian/patches/use_autoreconf.patch
--- cloog-0.18.3/debian/patches/use_autoreconf.patch
+++ cloog-0.18.3/debian/patches/use_autoreconf.patch
@@ -0,0 +1,42 @@
+Description: Use autoreconf to build
+ This package failed to run autoreconf because configure.ac includes isl subdir
+ to its configuration even if it is not used.
+ Solution is to include the Makefile.am that would be downloaded if built from
+ scratch. The file is short.
+Author: Fernando Furusato <ferseiti@br.ibm.com>
+
+--- /dev/null
++++ cloog-0.18.3/isl/interface/Makefile.am
+@@ -0,0 +1,32 @@
++AUTOMAKE_OPTIONS = nostdinc
++
++noinst_PROGRAMS = extract_interface
++
++AM_CXXFLAGS = $(CLANG_CXXFLAGS)
++AM_LDFLAGS = $(CLANG_LDFLAGS)
++
++includes = -I$(top_builddir) -I$(top_srcdir) \
++	-I$(top_builddir)/include -I$(top_srcdir)/include
++
++extract_interface_CPPFLAGS = $(includes)
++extract_interface_SOURCES = \
++	python.h \
++	python.cc \
++	extract_interface.h \
++	extract_interface.cc
++extract_interface_LDADD = \
++	-lclangFrontend -lclangSerialization -lclangParse -lclangSema \
++	$(LIB_CLANG_EDIT) \
++	-lclangAnalysis -lclangAST -lclangLex -lclangBasic -lclangDriver \
++	$(CLANG_LIBS) $(CLANG_LDFLAGS)
++
++test: extract_interface
++	./extract_interface$(EXEEXT) $(includes) $(srcdir)/all.h
++
++isl.py: extract_interface isl.py.top
++	(cat $(srcdir)/isl.py.top; \
++		./extract_interface$(EXEEXT) $(includes) $(srcdir)/all.h) \
++			> isl.py
++
++dist-hook: isl.py
++	cp isl.py $(distdir)/
diff -Nru cloog-0.18.3/debian/rules cloog-0.18.3/debian/rules
--- cloog-0.18.3/debian/rules
+++ cloog-0.18.3/debian/rules
@@ -19,7 +19,7 @@
 configure: configure-stamp
 configure-stamp:
 	dh_testdir
-	dh_autotools-dev_updateconfig
+	dh_autoreconf
 	chmod +x configure
 	./configure $(CROSS) \
 		--prefix=/usr \
@@ -49,7 +49,7 @@
 	rm -f doc/*.info
 	rm -f cloog-isl-uninstalled.sh *.pc *.pc.in doc/gitversion.texi version.h
 	rm -f config.log config.status
-	dh_autotools-dev_restoreconfig
+	dh_autoreconf_clean
 	dh_clean 
 
 install: build
EOF
	drop_privs quilt push -a
}

add_automatic curl
patch_curl() {
	echo "patching curl to not install absent zsh completions #812965"
	drop_privs patch -p1 <<'EOF'
--- a/debian/curl.install
+++ b/debian/curl.install
@@ -1,2 +1,3 @@
+#!/usr/bin/dh-exec
 usr/bin/curl
-usr/share/zsh/*
+<!cross> usr/share/zsh/*
EOF
	chmod +x debian/curl.install
}

add_automatic dash
add_automatic datefudge
add_automatic db-defaults
add_automatic debianutils

add_automatic diffutils
patch_diffutils() {
	echo "work around diffutils FTBFS with gcc-7 #853373"
	# disable gcc-7-specific code until it is unbroken
	sed -i -e 's/^\(#define _GL_HAS_BUILTIN_OVERFLOW_WITH_NULL \).*/\1 0/' lib/intprops.h
}

add_automatic dpkg

patch_e2fsprogs() {
	echo "fix e2fsprogs FTBFS with strict debhelper #876551"
	drop_privs sed -i -e 's/ -Nlibblkid1-udeb//' -e 's/ -Nlibuuid1-udeb//' -e 's/ -Nuuid-dev//' debian/rules
}

builddep_elfutils() {
	assert_built "bzip2 xz-utils zlib"
	# gcc-multilib dependency lacks nocheck profile
	apt_get_install debhelper autotools-dev autoconf automake bzip2 "zlib1g-dev:$1" zlib1g-dev "libbz2-dev:$1" "liblzma-dev:$1" m4 gettext gawk dpkg-dev flex libfl-dev bison
}
patch_elfutils() {
	echo "work around FTBFS with gcc-7 #853387"
	sed -i -e 's/-Werror//' config/eu.am
}

patch_expat() {
	echo "patching expat to add nobiarch build profile #779459"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -5,7 +5,7 @@
 Build-Depends: debhelper (>= 9), docbook-to-man, dh-autoreconf,
  dpkg-dev (>= 1.16.0),
  libbsd-dev [kfreebsd-amd64 kfreebsd-i386 hurd-i386],
- gcc-multilib [i386 powerpc sparc s390]
+ gcc-multilib [i386 powerpc sparc s390] <!nobiarch>
 Homepage: http://expat.sourceforge.net
 Vcs-Browser: http://svn.debian.org/wsvn/debian-xml-sgml/packages/expat/trunk/
 Vcs-Svn: svn://svn.debian.org/svn/debian-xml-sgml/packages/expat/trunk/
@@ -14,6 +14,7 @@
 Section: libdevel
 Architecture: i386 powerpc sparc s390
 Depends: ${misc:Depends}, lib64expat1 (= ${binary:Version}), libexpat1-dev, gcc-multilib
+Build-Profiles: <!nobiarch>
 Description: XML parsing C library - development kit (64bit)
  This package contains the header file and development libraries of
  expat, the C library for parsing XML.  Expat is a stream oriented XML
@@ -30,6 +31,7 @@
 Section: libs
 Architecture: i386 powerpc sparc s390
 Depends: ${shlibs:Depends}, ${misc:Depends}
+Build-Profiles: <!nobiarch>
 Description: XML parsing C library - runtime library (64bit)
  This package contains the runtime, shared library of expat, the C
  library for parsing XML. Expat is a stream-oriented parser in
--- a/debian/rules
+++ b/debian/rules
@@ -11,7 +11,9 @@
 DEB_HOST_ARCH      ?= $(shell dpkg-architecture -qDEB_HOST_ARCH)
 DEB_HOST_MULTIARCH ?= $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)
 
+ifeq ($(filter nobiarch,$(DEB_BUILD_PROFILES)),)
 BUILD64 = $(filter $(DEB_HOST_ARCH), i386 powerpc sparc s390)
+endif
 
 ifeq ($(DEB_BUILD_GNU_TYPE), $(DEB_HOST_GNU_TYPE))
 	CONFFLAGS = --build=$(DEB_HOST_GNU_TYPE)
EOF
	echo "patching expat to use the cross compiler for multilib builds #775942"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -32,6 +32,10 @@
 	HOST64FLAG = --host=s390x-linux-gnu
 endif
 
+ifeq ($(origin CC),default)
+CC = $(DEB_HOST_GNU_TYPE)-gcc
+endif
+
 # -pthread -D_REENTRANT #551079
 CFLAGS  = `dpkg-buildflags --get CFLAGS`
 CFLAGS  += -Wall
@@ -65,13 +69,13 @@
 
 build64/config.status: config-common-stamp
 	dh_testdir
-	(mkdir -p $(@D); cd $(@D); CFLAGS="-m64 $(CFLAGS)" CPPFLAGS="$(CPPFLAGS)"  LDFLAGS="$(LDFLAGS)" \
+	(mkdir -p $(@D); cd $(@D); CC="$(CC) -m64" CFLAGS="$(CFLAGS)" CPPFLAGS="$(CPPFLAGS)"  LDFLAGS="$(LDFLAGS)" \
 	 ../configure $(CONFFLAGS) $(HOST64FLAG) --prefix=/usr --mandir=\$${prefix}/share/man \
 	 --libdir=\$${prefix}/lib64)
 
 buildw64/config.status: config-common-stamp
 	dh_testdir
-	(mkdir -p $(@D); cd $(@D); CFLAGS="-m64 $(CFLAGS) -DXML_UNICODE" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)" \
+	(mkdir -p $(@D); cd $(@D); CC="$(CC) -m64" CFLAGS="$(CFLAGS) -DXML_UNICODE" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)" \
 	 ../configure $(CONFFLAGS) $(HOST64FLAG) --prefix=/usr --mandir=\$${prefix}/share/man \
 	 --libdir=\$${prefix}/lib64)
 
EOF
}
builddep_expat() {
	# gcc-multilib lacks nobiarch profile #779459
	apt_get_install debhelper docbook-to-man dh-autoreconf dpkg-dev
	if dpkg-architecture "-a$1" -ikfreebsd-any; then
		apt_get_install "libbsd-dev:$1"
	fi
}

add_automatic file
add_automatic findutils

add_automatic flex
patch_flex() {
	echo "patching flex to fix FTCBFS #833146"
	drop_privs patch -p1 <<'EOF'
--- flex-2.6.1/configure.ac
+++ flex-2.6.1/configure.ac
@@ -70,6 +70,7 @@
 FLEXexe='$(top_builddir)/src/flex$(EXEEXT)'
 fi
 AC_SUBST(FLEXexe)
+AM_CONDITIONAL([CROSS_COMPILING],[test "$cross_compiling" = yes])
 
 # Check for a m4 that supports -P
 
--- flex-2.6.1/src/Makefile.am
+++ flex-2.6.1/src/Makefile.am
@@ -89,8 +89,13 @@
 stage1scan.l: scan.l
 	cp $(srcdir)/scan.l $(srcdir)/stage1scan.l
 
+if CROSS_COMPILING
+stage1scan.c: stage1scan.l
+	$(FLEXexe) -o $@ $<
+else
 stage1scan.c: stage1scan.l stage1flex$(EXEEXT)
 	$(top_builddir)/src/stage1flex$(EXEEXT) -o $@ $<
+endif
 
 # Explicitly describe dependencies.
 # You can recreate this with `gcc -I. -MM *.c'
EOF
}

add_automatic fontconfig
builddep_fontconfig() {
	# help apt with finding a solution
	apt_get_remove "libfreetype6-dev:$(dpkg --print-architecture)"
	apt_get_build_dep "-a$1" ./
}
patch_fontconfig() {
	echo "fixing fontconfig ftbfs with newer gperf #869584"
	echo src/fcobjshash.h | drop_privs tee -a debian/clean >/dev/null
}

add_automatic freebsd-glue
add_automatic freetype
add_automatic fuse
add_automatic gdbm

add_automatic glib2.0
buildenv_glib2_0() {
	export glib_cv_stack_grows=no
	export glib_cv_uscore=no
	export ac_cv_func_posix_getgrgid_r=yes
	export ac_cv_func_posix_getpwuid_r=yes
}
patch_glib2_0() {
	echo "fix FTCBFS #870346"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -28,15 +28,15 @@
 	dh_auto_configure \
 		--builddirectory=debian/build/deb \
 		-- \
-		$(DEB_CONFIGURE_EXTRA_FLAGS) \
 		$(DEB_CONFIGURE_FLAGS_deb) \
+		$(DEB_CONFIGURE_EXTRA_FLAGS) \
 		$(NULL)
 ifneq ($(filter %-udeb,$(binaries)),)
 	dh_auto_configure \
 		--builddirectory=debian/build/udeb \
 		-- \
-		$(DEB_CONFIGURE_EXTRA_FLAGS) \
 		$(DEB_CONFIGURE_FLAGS_udeb) \
+		$(DEB_CONFIGURE_EXTRA_FLAGS) \
 		$(NULL)
 endif

EOF
}

add_automatic gmp
patch_gmp() {
	if test "$LIBC_NAME" = musl; then
		echo "patching gmp symbols for musl arch #788411"
		sed -i -r "s/([= ])(\!)?\<(${HOST_ARCH#musl-linux-})\>/\1\2\3 \2musl-linux-\3/" debian/libgmp10.symbols
		# musl does not implement GNU obstack
		sed -i -r 's/^ (.*_obstack_)/ (arch=!musl-linux-any !musleabihf-linux-any)\1/' debian/libgmp10.symbols
	fi
	echo "patching gmp symbols for nios2 #814671"
	sed -i 's/!mips /!nios2 &/' debian/libgmp10.symbols
	echo "patching gmp symbols for tilegx #850010"
	sed -i '/^ /s/!m68k /!tilegx &/' debian/libgmp10.symbols
	if test "$HOST_ARCH" = sh3; then
		echo "patching gmp symbols for sh3 #851895"
		sed -i 's/!sh4/!sh3 !sh4/g' debian/libgmp10.symbols
	fi
}

builddep_gnu_efi() {
	# binutils dependency needs cross translation
	$APT_GET install debhelper
}

add_automatic gnupg2
add_automatic gnutls28

add_automatic gpm
patch_gpm() {
	echo "patching gpm to support musl #813751"
	drop_privs patch -p1 <<'EOF'
--- a/src/lib/liblow.c
+++ a/src/lib/liblow.c
@@ -173,7 +173,7 @@
   /* Reincarnation. Prepare for another death early. */
   sigemptyset(&sa.sa_mask);
   sa.sa_handler = gpm_suspend_hook;
-  sa.sa_flags = SA_NOMASK;
+  sa.sa_flags = SA_NODEFER;
   sigaction (SIGTSTP, &sa, 0);
 
   /* Pop the gpm stack by closing the useless connection */
@@ -350,7 +350,7 @@
 
          /* if signal was originally ignored, job control is not supported */
          if (gpm_saved_suspend_hook.sa_handler != SIG_IGN) {
-            sa.sa_flags = SA_NOMASK;
+            sa.sa_flags = SA_NODEFER;
             sa.sa_handler = gpm_suspend_hook;
             sigaction(SIGTSTP, &sa, 0);
          }
--- a/src/prog/display-buttons.c
+++ b/src/prog/display-buttons.c
@@ -36,6 +36,7 @@
 #include <stdio.h>            /* printf()             */
 #include <time.h>             /* time()               */
 #include <errno.h>            /* errno                */
+#include <sys/select.h>       /* fd_set, FD_ZERO      */
 #include <gpm.h>              /* gpm information      */
 
 /* display resulting data */
--- a/src/prog/display-coords.c
+++ b/src/prog/display-coords.c
@@ -37,6 +37,7 @@
 #include <stdio.h>            /* printf()             */
 #include <time.h>             /* time()               */
 #include <errno.h>            /* errno                */
+#include <sys/select.h>       /* fd_set, FD_ZERO      */
 #include <gpm.h>              /* gpm information      */
 
 /* display resulting data */
--- a/src/prog/gpm-root.y
+++ b/src/prog/gpm-root.y
@@ -1197,11 +1197,10 @@
                                                         LOG_DAEMON : LOG_USER);
    /* reap your zombies */
    childaction.sa_handler=reap_children;
-#if defined(__GLIBC__)
-   __sigemptyset(&childaction.sa_mask);
-#else /* __GLIBC__ */
-   childaction.sa_mask=0;
-#endif /* __GLIBC__ */
+   sigemptyset(&childaction.sa_mask);
+#ifndef SA_INTERRUPT
+#define SA_INTERRUPT 0
+#endif
    childaction.sa_flags=SA_INTERRUPT; /* need to break the select() call */
    sigaction(SIGCHLD,&childaction,NULL);
 
--- a/src/prog/open_console.c
+++ b/src/prog/open_console.c
@@ -22,6 +22,7 @@
 #include "headers/message.h"        /* messaging in gpm */
 #include "headers/daemon.h"         /* daemon internals */
 #include <unistd.h>
+#include <fcntl.h>
 
 int open_console(const int mode)
 {
EOF
}

add_automatic grep
add_automatic groff

add_automatic guile-2.0
builddep_guile_2_0() {
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -P cross ./
	if test "$HOST_ARCH" = tilegx; then
		patch /usr/share/guile/2.0/system/base/target.scm <<'EOF'
--- a/module/system/base/target.scm
+++ b/module/system/base/target.scm
@@ -65,7 +65,7 @@
       (cond ((string-match "^i[0-9]86$" cpu)
              (endianness little))
             ((member cpu '("x86_64" "ia64"
-                           "powerpcle" "powerpc64le" "mipsel" "mips64el" "nios2" "sh4" "alpha"))
+                           "powerpcle" "powerpc64le" "mipsel" "mips64el" "nios2" "sh4" "alpha" "tilegx"))
              (endianness little))
             ((member cpu '("sparc" "sparc64" "powerpc" "powerpc64" "spu"
                            "mips" "mips64" "m68k" "s390x"))
@@ -105,7 +105,7 @@
           ((string-match "64$" cpu) 8)
           ((string-match "64_?[lbe][lbe]$" cpu) 8)
           ((member cpu '("sparc" "powerpc" "mips" "mipsel" "nios2" "m68k" "sh4")) 4)
-          ((member cpu '("s390x" "alpha")) 8)
+          ((member cpu '("s390x" "alpha" "tilegx")) 8)
           ((string-match "^arm.*" cpu) 4)
           (else (error "unknown CPU word size" cpu)))))
 
EOF
	fi
	if test "$HOST_ARCH" = sh3; then
		echo "adding sh3 support to guile-2.0 http://git.savannah.gnu.org/cgit/guile.git/commit/?id=92222727f81b2a03cde124b88d7e6224ecb29199"
		sed -i -e 's/"sh4"/"sh3" &/' /usr/share/guile/2.0/system/base/target.scm
	fi
}
patch_guile_2_0() {
	if test "$HOST_ARCH" = tilegx; then
		echo "patching guile tilegx support #855191"
		drop_privs patch -p1 <<'EOF'
--- a/module/system/base/target.scm
+++ b/module/system/base/target.scm
@@ -65,7 +65,7 @@
       (cond ((string-match "^i[0-9]86$" cpu)
              (endianness little))
             ((member cpu '("x86_64" "ia64"
-                           "powerpcle" "powerpc64le" "mipsel" "mips64el" "nios2" "sh4" "alpha"))
+                           "powerpcle" "powerpc64le" "mipsel" "mips64el" "nios2" "sh4" "alpha" "tilegx"))
              (endianness little))
             ((member cpu '("sparc" "sparc64" "powerpc" "powerpc64" "spu"
                            "mips" "mips64" "m68k" "s390x"))
@@ -105,7 +105,7 @@
           ((string-match "64$" cpu) 8)
           ((string-match "64_?[lbe][lbe]$" cpu) 8)
           ((member cpu '("sparc" "powerpc" "mips" "mipsel" "nios2" "m68k" "sh4")) 4)
-          ((member cpu '("s390x" "alpha")) 8)
+          ((member cpu '("s390x" "alpha" "tilegx")) 8)
           ((string-match "^arm.*" cpu) 4)
           (else (error "unknown CPU word size" cpu)))))
 
EOF
	fi
	if test "$HOST_ARCH" = sh3; then
		echo "adding sh3 support to guile-2.0 http://git.savannah.gnu.org/cgit/guile.git/commit/?id=92222727f81b2a03cde124b88d7e6224ecb29199"
		sed -i -e 's/"sh4"/"sh3" &/' module/system/base/target.scm
	fi
}

add_automatic gzip
buildenv_gzip() {
	if test "$LIBC_NAME" = musl; then
		# this avoids replacing fseeko with a variant that is broken
		echo gl_cv_func_fflush_stdin exported
		export gl_cv_func_fflush_stdin=yes
	fi
}

add_automatic hostname

add_automatic icu
patch_icu() {
	echo "patching icu to drop versioned libstdc++-dev dependency"
	sed -i -e '/^[^:]*Depends:/s/,\s*libstdc++-[0-9]-dev[^,]*\(,\|$\)/\1/g' debian/control
}

add_automatic isl
add_automatic jansson

add_automatic jemalloc
buildenv_jemalloc() {
	case "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_CPU)" in
		amd64|arm|arm64|hppa|i386|m68k|mips|s390x|sh3|sh4)
			echo "setting je_cv_static_page_shift=12"
			export je_cv_static_page_shift=12
		;;
		alpha|sparc|sparc64)
			echo "setting je_cv_static_page_shift=13"
			export je_cv_static_page_shift=13
		;;
		mips64el|mipsel|nios2|tilegx)
			echo "setting je_cv_static_page_shift=14"
			export je_cv_static_page_shift=14
		;;
		powerpc|ppc64|ppc64el)
			echo "setting je_cv_static_page_shift=16"
			export je_cv_static_page_shift=16
		;;
	esac
}
patch_jemalloc() {
	if test "$HOST_ARCH" = sh3; then
		echo "adding sh3 support to jemalloc #863424"
		drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -6,7 +6,7 @@
 DEB_HOST_ARCH := $(shell dpkg-architecture -qDEB_HOST_ARCH)
 DEB_HOST_ARCH_OS := $(shell dpkg-architecture -qDEB_HOST_ARCH_OS)

-ifneq (,$(findstring $(DEB_HOST_ARCH),sparc sparc64))
+ifneq (,$(findstring $(DEB_HOST_ARCH),sh3 sparc sparc64))
   DEB_CPPFLAGS_MAINT_APPEND += -DLG_QUANTUM=4
 endif

EOF
	fi
}

add_automatic keyutils
add_automatic kmod

add_automatic krb5
buildenv_krb5() {
	export krb5_cv_attr_constructor_destructor=yes,yes
	export ac_cv_func_regcomp=yes
	export ac_cv_printf_positional=yes
}

add_automatic libassuan

add_automatic libatomic-ops
patch_libatomic_ops() {
	if test "$HOST_ARCH" = nios2; then
		echo "cherry-picking https://github.com/ivmai/libatomic_ops/commit/4b005ee56898309e8afba9b3c48cf94f0f5f78e4"
		drop_privs patch -p1 <<'EOF'
--- a/src/Makefile.am
+++ b/src/Makefile.am
@@ -79,6 +79,7 @@
           atomic_ops/sysdeps/gcc/ia64.h \
           atomic_ops/sysdeps/gcc/m68k.h \
           atomic_ops/sysdeps/gcc/mips.h \
+          atomic_ops/sysdeps/gcc/nios2.h \
           atomic_ops/sysdeps/gcc/powerpc.h \
           atomic_ops/sysdeps/gcc/s390.h \
           atomic_ops/sysdeps/gcc/sh.h \
--- a/src/atomic_ops.h
+++ b/src/atomic_ops.h
@@ -262,6 +262,9 @@
 # if defined(__m68k__)
 #   include "atomic_ops/sysdeps/gcc/m68k.h"
 # endif /* __m68k__ */
+# if defined(__nios2__)
+#   include "atomic_ops/sysdeps/gcc/nios2.h"
+# endif /* __nios2__ */
 # if defined(__powerpc__) || defined(__ppc__) || defined(__PPC__) \
      || defined(__powerpc64__) || defined(__ppc64__)
 #   include "atomic_ops/sysdeps/gcc/powerpc.h"
--- a/src/atomic_ops/sysdeps/gcc/nios2.h
+++ b/src/atomic_ops/sysdeps/gcc/nios2.h
@@ -0,0 +1,17 @@
+/*
+ * Copyright (C) 2016 Marek Vasut <marex@denx.de>
+ *
+ * THIS MATERIAL IS PROVIDED AS IS, WITH ABSOLUTELY NO WARRANTY EXPRESSED
+ * OR IMPLIED. ANY USE IS AT YOUR OWN RISK.
+ *
+ * Permission is hereby granted to use or copy this program
+ * for any purpose, provided the above notices are retained on all copies.
+ * Permission to modify the code and to distribute modified code is granted,
+ * provided the above notices are retained, and a notice that the code was
+ * modified is included with the above copyright notice.
+ */
+
+#include "../test_and_set_t_is_ao_t.h"
+#include "generic.h"
+
+#define AO_T_IS_INT
EOF
	fi
	if test "$HOST_ARCH" = tilegx; then
		echo "adding tilegx support to libatomic-ops #841771"
		drop_privs tee debian/patches/0001-Basic-support-of-TILE-Gx-and-TILEPro-CPUs.patch > /dev/null <<'EOF'
--- a/src/Makefile.am
+++ b/src/Makefile.am
@@ -84,6 +84,7 @@
           atomic_ops/sysdeps/gcc/s390.h \
           atomic_ops/sysdeps/gcc/sh.h \
           atomic_ops/sysdeps/gcc/sparc.h \
+          atomic_ops/sysdeps/gcc/tile.h \
           atomic_ops/sysdeps/gcc/x86.h \
         \
           atomic_ops/sysdeps/hpc/hppa.h \
--- a/src/atomic_ops.h
+++ b/src/atomic_ops.h
@@ -294,6 +294,9 @@
 # if defined(__hexagon__)
 #   include "atomic_ops/sysdeps/gcc/hexagon.h"
 # endif
+# if defined(__tile__)
+#   include "atomic_ops/sysdeps/gcc/tile.h"
+# endif
 #endif /* __GNUC__ && !AO_USE_PTHREAD_DEFS */
 
 #if (defined(__IB
--- /dev/null
+++ b/src/atomic_ops/sysdeps/gcc/tile.h
@@ -0,0 +1,3 @@
+#include "../test_and_set_t_is_ao_t.h"
+#include "generic.h"
+#define AO_T_IS_INT
EOF
	fi
}

add_automatic libbsd

add_automatic libcap2
patch_libcap2() {
	echo "fixing misbuilt libcap.pc #871714"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -46,6 +46,8 @@
 	cd debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH) && \
 		mv    ../../../lib/$(DEB_HOST_MULTIARCH)/*.a . && \
 		ln -s ../../../lib/$(DEB_HOST_MULTIARCH)/libcap.so.*.* libcap.so
+	sed -i -e 's#^libdir=.*#libdir=/usr/lib/$(DEB_HOST_MULTIARCH)#' \
+		debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/pkgconfig/libcap.pc

 	# Remove unwanted/unused files (because of --fail-missing)
 	rm -f debian/tmp/lib/$(DEB_HOST_MULTIARCH)/*.so
EOF
}

add_automatic libdebian-installer
patch_libdebian_installer() {
	if dpkg-architecture "-a$HOST_ARCH" -imusl-linux-any; then
		echo "fixing libdebian-installer includes #861598"
		drop_privs patch -p1 <<'EOF'
--- a/src/exec.c
+++ b/src/exec.c
@@ -25,10 +25,10 @@
 
 #include <errno.h>
 #include <fcntl.h>
+#include <poll.h>
 #include <stdio.h>
 #include <stdlib.h>
 #include <string.h>
-#include <sys/poll.h>
 #include <sys/stat.h>
 #include <sys/types.h>
 #include <sys/wait.h>
EOF
	fi
}

add_automatic libev
add_automatic libevent
add_automatic libffi

add_automatic libgc
patch_libgc() {
	if test "$HOST_ARCH" = nios2; then
		echo "cherry-picking upstream commit https://github.com/ivmai/bdwgc/commit/2571df0e30b4976d7a12dbc6fbec4f1c4027924d"
		drop_privs patch -p1 <<'EOF'
--- a/include/private/gcconfig.h
+++ b/include/private/gcconfig.h
@@ -188,6 +188,10 @@
 #    endif
 #    define mach_type_known
 # endif
+# if defined(__NIOS2__) || defined(__NIOS2) || defined(__nios2__)
+#   define NIOS2 /* Altera NIOS2 */
+#   define mach_type_known
+# endif
 # if defined(__NetBSD__) && defined(__vax__)
 #    define VAX
 #    define mach_type_known
@@ -1729,6 +1733,24 @@
 #   endif
 # endif
 
+# ifdef NIOS2
+#  define CPP_WORDSZ 32
+#  define MACH_TYPE "NIOS2"
+#  ifdef LINUX
+#    define OS_TYPE "LINUX"
+#    define DYNAMIC_LOADING
+     extern int _end[];
+     extern int __data_start[];
+#    define DATASTART ((ptr_t)(__data_start))
+#    define DATAEND ((ptr_t)(_end))
+#    define ALIGNMENT 4
+#    ifndef HBLKSIZE
+#      define HBLKSIZE 4096
+#    endif
+#    define LINUX_STACKBOTTOM
+#  endif /* Linux */
+# endif
+
 # ifdef SH4
 #   define MACH_TYPE "SH4"
 #   define OS_TYPE "MSWINCE"
@@ -2800,7 +2822,8 @@

 #if ((defined(UNIX_LIKE) && (defined(DARWIN) || defined(HURD) \
                              || defined(OPENBSD) || defined(ARM32) \
-                             || defined(MIPS) || defined(AVR32))) \
+                             || defined(MIPS) || defined(AVR32) \
+                             || defined(NIOS2))) \
      || (defined(LINUX) && (defined(SPARC) || defined(M68K))) \
      || ((defined(RTEMS) || defined(PLATFORM_ANDROID)) && defined(I386))) \
     && !defined(NO_GETCONTEXT)
EOF
	fi
	if test "$HOST_ARCH" = tilegx; then
		echo "patching libgc for tilegx #854174"
		drop_privs patch -p1 <<'EOF'
--- a/include/private/gcconfig.h
+++ b/include/private/gcconfig.h
@@ -460,6 +460,10 @@
 #     define  mach_type_known
 #    endif 
 # endif
+# if defined(__tilegx__) && defined(LINUX)
+#  define TILEGX
+#  define mach_type_known
+# endif
 
 /* Feel free to add more clauses here */
 
@@ -2086,6 +2097,28 @@
 #   endif
 # endif
 
+# ifdef TILEGX
+#  define CPP_WORDSZ (__SIZEOF_POINTER__ * 8)
+#  define MACH_TYPE "TILE-Gx"
+#  define ALIGNMENT __SIZEOF_POINTER__
+#  if CPP_WORDSZ < 64
+#   define ALIGN_DOUBLE /* Guarantee 64-bit alignment for allocations. */
+    /* Take advantage of 64-bit stores. */
+#   define CLEAR_DOUBLE(x) ((*(long long *)(x)) = 0)
+#  endif
+#  define PREFETCH(x) __insn_prefetch_l1(x)
+#  include <arch/chip.h>
+#  define CACHE_LINE_SIZE CHIP_L2_LINE_SIZE()
+#  define USE_GENERIC_PUSH_REGS
+#  ifdef LINUX
+#   define OS_TYPE "LINUX"
+    extern int __data_start[];
+#   define DATASTART (ptr_t)(__data_start)
+#   define LINUX_STACKBOTTOM
+#   define DYNAMIC_LOADING
+#  endif
+# endif
+
 #if defined(LINUX) && defined(USE_MMAP)
     /* The kernel may do a somewhat better job merging mappings etc.	*/
     /* with anonymous mappings.						*/
EOF
		echo "updating libgc symbols for tilegx #??????"
		sed -i -e '/^ /s/=\(!\?\)arm64 /&\1tilegx /' debian/libgc1c2.symbols
	fi
	if test "$HOST_ARCH" = sh3; then
		echo "updating libgc symbols for sh3 #851924"
		sed -i -e '/^ /s/!sh4/!sh3 &/' debian/libgc1c2.symbols
	fi
}

add_automatic libgcrypt20
buildenv_libgcrypt20() {
	export ac_cv_sys_symbol_underscore=no
}

add_automatic libgpg-error
patch_libgpg_error() {
	if test "$HOST_ARCH" = sh3 -a ! -f src/syscfg/lock-obj-pub.sh3-unknown-linux-gnu.h; then
		echo "cherry-picking libgpg-error commit 67e51f9957f875ca854f25f4a9a63aeb831c55c4"
		drop_privs cp -nv src/syscfg/lock-obj-pub.sh4-unknown-linux-gnu.h src/syscfg/lock-obj-pub.sh3-unknown-linux-gnu.h
	fi
}

add_automatic libice

patch_libidn() {
	echo "moving gcj-jdk to Build-Depends-Indep #870669"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -4,7 +4,8 @@
 Maintainer: Debian Libidn Team <help-libidn@gnu.org>
 Uploaders: Anibal Monsalve Salazar <anibal@debian.org>, Simon Josefsson <simon@josefsson.org>, Ondřej Surý <ondrej@debian.org>
 Standards-Version: 3.9.8
-Build-Depends: debhelper (>= 9), gcj-jdk [!arm !hppa !hurd-i386 !mips64el], fastjar [!arm !hppa !hurd-i386 !mips64el], dh-autoreconf, autopoint (>= 0.19.3), help2man, texinfo
+Build-Depends: debhelper (>= 9), dh-autoreconf, autopoint (>= 0.19.3), help2man, texinfo
+Build-Depends-Indep: gcj-jdk, fastjar
 Homepage: https://www.gnu.org/software/libidn/
 Vcs-Browser: https://anonscm.debian.org/cgit/collab-maint/libidn.git
 Vcs-Git: https://anonscm.debian.org/git/collab-maint/libidn.git
--- a/debian/rules
+++ b/debian/rules
@@ -4,16 +4,12 @@

 export DEB_BUILD_MAINT_OPTIONS=hardening=+all

-# Don't build libidn11-java on platforms that doesn't have gcj.
-NO_JAVA_ARCHES := arm hppa hurd-i386 mips64el or1k
-DEB_HOST_ARCH  ?= $(shell dpkg-architecture -qDEB_HOST_ARCH)
-ifneq (,$(filter stage1,$(DEB_BUILD_PROFILES)))
-  # Or when bootstrapping, because libidn is needed before gcj, see #738147.
-  export DH_OPTIONS=-Nlibidn11-java
-else ifeq (,$(filter $(DEB_HOST_ARCH),$(NO_JAVA_ARCHES)))
-  ENABLE_JAVA := --enable-java
+DOPACKAGES = $(shell dh_listpackages)
+CONFIGURE_FLAGS :=
+ifneq ($(filter libidn11-java,$(DOPACKAGES)),)
+CONFIGURE_FLAGS += --enable-java
 else
-  export DH_OPTIONS=-Nlibidn11-java
+CONFIGURE_FLAGS += --disable-java
 endif

 %:
@@ -26,7 +22,7 @@
 		--with-packager-version=$(CFG_VERS) \
 		--with-packager-bug-reports=https://bugs.debian.org/ \
 		--disable-silent-rules \
-		 $(ENABLE_JAVA)
+		$(CONFIGURE_FLAGS)

 override_dh_auto_install:
 	dh_auto_install
EOF
	echo "fixing help2man FTCBFS #875684"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -1,28 +1,39 @@
 #!/usr/bin/make -f
 
+include /usr/share/dpkg/architecture.mk
+
 export DH_VERBOSE=1
 
 export DEB_BUILD_MAINT_OPTIONS=hardening=+all
 
+CFG_VERS = `dpkg-parsechangelog | grep ^Version: | cut -d\  -f2`
+
 DOPACKAGES = $(shell dh_listpackages)
-CONFIGURE_FLAGS :=
+CONFIGURE_FLAGS := \
+	--with-packager=Debian \
+	--with-packager-version=$(CFG_VERS) \
+	--with-packager-bug-reports=https://bugs.debian.org/ \
+	--disable-silent-rules
 ifneq ($(filter libidn11-java,$(DOPACKAGES)),)
 CONFIGURE_FLAGS += --enable-java
 else
 CONFIGURE_FLAGS += --disable-java
 endif
+NATIVE = eval $$(dpkg-architecture -f -a$(DEB_BUILD_ARCH) -s);

 %:
 	dh $@ --parallel --builddirectory=build --with autoreconf

-CFG_VERS = `dpkg-parsechangelog | grep ^Version: | cut -d\  -f2`
-
 override_dh_auto_configure:
-	dh_auto_configure -- --with-packager=Debian \
-		--with-packager-version=$(CFG_VERS) \
-		--with-packager-bug-reports=https://bugs.debian.org/ \
-		--disable-silent-rules \
-		$(CONFIGURE_FLAGS)
+ifneq ($(DEB_BUILD_ARCH),$(DEB_HOST_ARCH))
+	$(NATIVE) dh_auto_configure -- $(CONFIGURE_FLAGS)
+	$(NATIVE) dh_auto_build
+	$(NATIVE) dh_auto_clean
+	test -f doc/idn.1
+	dh_auto_configure -- $(CONFIGURE_FLAGS) HELP2MAN=true
+else
+	dh_auto_configure -- $(CONFIGURE_FLAGS)
+endif

 override_dh_auto_install:
 	dh_auto_install
EOF
}

builddep_libidn2_0() {
	echo "working around gengetopt not being M-A:foreign #856908"
	assert_built libunistring
	apt_get_install debhelper dh-autoreconf pkg-config texinfo texlive help2man gengetopt "libunistring-dev:$1" libunistring-dev autoconf-archive
}
patch_libidn2_0() {
	echo "fixing architecture of libidn2-0-dev #872567"
	drop_privs sed -i -e '/^Package: libidn2-0-dev/,/^$/s/Architecture: all/Architecture: any/' debian/control
}

add_automatic libksba
add_automatic libonig
add_automatic libpipeline
add_automatic libpng1.6

patch_libprelude() {
	echo "removing the unsatisfiable g++ build dependency"
	drop_privs sed -i -e '/^\s\+g++/d' debian/control
}
buildenv_libprelude() {
	case $(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_SYSTEM) in *gnu*)
		echo "glibc does not return NULL for malloc(0)"
		export ac_cv_func_malloc_0_nonnull=yes
	;; esac
}

add_automatic libpsl
add_automatic libpthread-stubs
add_automatic libseccomp

add_automatic libsepol
add_automatic libsm
add_automatic libssh2
add_automatic libsystemd-dummy
add_automatic libtasn1-6
add_automatic libtextwrap

add_automatic libunistring
add_automatic libusb
add_automatic libusb-1.0
add_automatic libverto

add_automatic libx11
buildenv_libx11() {
	export xorg_cv_malloc0_returns_null=no
}

add_automatic libxau
add_automatic libxaw
add_automatic libxdmcp

add_automatic libxext
buildenv_libxext() {
	export xorg_cv_malloc0_returns_null=no
}

add_automatic libxmu
add_automatic libxpm

add_automatic libxrender
buildenv_libxrender() {
	export xorg_cv_malloc0_returns_null=no
}

add_automatic libxss
buildenv_libxss() {
	export xorg_cv_malloc0_returns_null=no
}

add_automatic libxt
buildenv_libxt() {
	export xorg_cv_malloc0_returns_null=no
}

add_automatic lz4

add_automatic make-dfsg
add_automatic man-db
add_automatic mawk
add_automatic mpclib3
add_automatic mpfr4
add_automatic nettle
add_automatic nghttp2
add_automatic npth

add_automatic nspr
patch_nspr() {
	echo "patching nspr for nios2 https://bugzilla.mozilla.org/show_bug.cgi?id=1244421"
	drop_privs patch -p1 <<'EOF'
--- a/nspr/pr/include/md/_linux.cfg
+++ b/nspr/pr/include/md/_linux.cfg
@@ -972,6 +972,51 @@
 #define PR_BYTES_PER_WORD_LOG2   2
 #define PR_BYTES_PER_DWORD_LOG2  3
 
+#elif defined(__nios2__)
+
+#define IS_LITTLE_ENDIAN    1
+#undef  IS_BIG_ENDIAN
+
+#define PR_BYTES_PER_BYTE   1
+#define PR_BYTES_PER_SHORT  2
+#define PR_BYTES_PER_INT    4
+#define PR_BYTES_PER_INT64  8
+#define PR_BYTES_PER_LONG   4
+#define PR_BYTES_PER_FLOAT  4
+#define PR_BYTES_PER_DOUBLE 8
+#define PR_BYTES_PER_WORD   4
+#define PR_BYTES_PER_DWORD  8
+
+#define PR_BITS_PER_BYTE    8
+#define PR_BITS_PER_SHORT   16
+#define PR_BITS_PER_INT     32
+#define PR_BITS_PER_INT64   64
+#define PR_BITS_PER_LONG    32
+#define PR_BITS_PER_FLOAT   32
+#define PR_BITS_PER_DOUBLE  64
+#define PR_BITS_PER_WORD    32
+
+#define PR_BITS_PER_BYTE_LOG2   3
+#define PR_BITS_PER_SHORT_LOG2  4
+#define PR_BITS_PER_INT_LOG2    5
+#define PR_BITS_PER_INT64_LOG2  6
+#define PR_BITS_PER_LONG_LOG2   5
+#define PR_BITS_PER_FLOAT_LOG2  5
+#define PR_BITS_PER_DOUBLE_LOG2 6
+#define PR_BITS_PER_WORD_LOG2   5
+
+#define PR_ALIGN_OF_SHORT   2
+#define PR_ALIGN_OF_INT     4
+#define PR_ALIGN_OF_LONG    4
+#define PR_ALIGN_OF_INT64   4
+#define PR_ALIGN_OF_FLOAT   4
+#define PR_ALIGN_OF_DOUBLE  4
+#define PR_ALIGN_OF_POINTER 4
+#define PR_ALIGN_OF_WORD    4
+
+#define PR_BYTES_PER_WORD_LOG2   2
+#define PR_BYTES_PER_DWORD_LOG2  3
+
 #elif defined(__or1k__)
 
 #undef  IS_LITTLE_ENDIAN
--- a/nspr/pr/include/md/_linux.h
+++ b/nspr/pr/include/md/_linux.h
@@ -55,6 +55,8 @@
 #define _PR_SI_ARCHITECTURE "avr32"
 #elif defined(__m32r__)
 #define _PR_SI_ARCHITECTURE "m32r"
+#elif defined(__nios2__)
+#define _PR_SI_ARCHITECTURE "nios2"
 #elif defined(__or1k__)
 #define _PR_SI_ARCHITECTURE "or1k"
 #else
@@ -125,6 +127,18 @@ extern PRInt32 _PR_x86_64_AtomicSet(PRInt32 *val, PRInt32 newval);
 #define _MD_ATOMIC_SET                _PR_x86_64_AtomicSet
 #endif
 
+#if defined(__nios2__)
+#if defined(__GNUC__)
+/* Use GCC built-in functions */
+#define _PR_HAVE_ATOMIC_OPS
+#define _MD_INIT_ATOMIC()
+#define _MD_ATOMIC_INCREMENT(ptr) __sync_add_and_fetch(ptr, 1)
+#define _MD_ATOMIC_DECREMENT(ptr) __sync_sub_and_fetch(ptr, 1)
+#define _MD_ATOMIC_ADD(ptr, i) __sync_add_and_fetch(ptr, i)
+#define _MD_ATOMIC_SET(ptr, nv) __sync_lock_test_and_set(ptr, nv)
+#endif
+#endif
+
 #if defined(__or1k__)
 #if defined(__GNUC__)
 /* Use GCC built-in functions */
EOF
	if test "$HOST_ARCH" = tilegx; then
		echo "patching nspr for tilegx #850496"
		drop_privs patch -p1 <<'EOF'
--- a/nspr/pr/include/md/_linux.cfg
+++ b/nspr/pr/include/md/_linux.cfg
@@ -240,7 +240,7 @@
 #define PR_BYTES_PER_WORD_LOG2  3
 #define PR_BYTES_PER_DWORD_LOG2 3
 
-#elif defined(__x86_64__)
+#elif defined(__x86_64__) || defined(__tilegx__)
 
 #define IS_LITTLE_ENDIAN 1
 #undef  IS_BIG_ENDIAN
--- a/nspr/pr/include/md/_linux.h
+++ b/nspr/pr/include/md/_linux.h
@@ -75,6 +75,8 @@
 #define _PR_SI_ARCHITECTURE "arm"
 #elif defined(__hppa__)
 #define _PR_SI_ARCHITECTURE "hppa"
+#elif defined(__tilegx__)
+#define _PR_SI_ARCHITECTURE "tilegx"
 #elif defined(__s390x__)
 #define _PR_SI_ARCHITECTURE "s390x"
 #elif defined(__s390__)
EOF
	fi
}

add_automatic nss
patch_nss() {
	echo "work around nss FTBFS with gcc-7 #853576"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -110,6 +110,7 @@
 		NSPR_LIB_DIR=/usr/lib/$(DEB_HOST_MULTIARCH) \
 		BUILD_OPT=1 \
 		NS_USE_GCC=1 \
+		NSS_ENABLE_WERROR=0 \
 		OPTIMIZER="$(CFLAGS) $(CPPFLAGS)" \
 		LDFLAGS='$(LDFLAGS) $$(ARCHFLAG) $$(ZDEFS_FLAG)' \
 		DSO_LDOPTS='-shared $$(LDFLAGS)' \
EOF
}

add_automatic openssl

add_automatic openssl1.0
patch_openssl1_0() {
	if test "$HOST_ARCH" = tilegx; then
		echo "adding tilegx support to openssl1.0 #858398"
		drop_privs patch ./Configure <<'EOF'
--- a/Configure
+++ b/Configure
@@ -400,6 +400,7 @@
 "debian-sparc-v8","gcc:-DB_ENDIAN ${debian_cflags} -mcpu=v8 -DBN_DIV2W::-D_REENTRANT::-ldl:BN_LLONG RC4_CHAR RC4_CHUNK DES_UNROLL BF_PTR:${sparcv8_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
 "debian-sparc-v9","gcc:-DB_ENDIAN ${debian_cflags} -mcpu=v9 -Wa,-Av8plus -DULTRASPARC -DBN_DIV2W::-D_REENTRANT::-ldl:BN_LLONG RC4_CHAR RC4_CHUNK DES_UNROLL BF_PTR:${sparcv9_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
 "debian-sparc64","gcc:-m64 -DB_ENDIAN ${debian_cflags} -DULTRASPARC -DBN_DIV2W::-D_REENTRANT::-ldl:BN_LLONG RC4_CHAR RC4_CHUNK DES_INT DES_PTR DES_RISC1 DES_UNROLL BF_PTR:${sparcv9_asm}:dlfcn:linux-shared:-fPIC:-m64:.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+"debian-tilegx","gcc:-DL_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:SIXTY_FOUR_BIT_LONG RC4_CHAR RC4_CHUNK DES_INT DES_UNROLL:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
 "debian-x32","gcc:-mx32 -DL_ENDIAN ${debian_cflags} -DMD32_REG_T=int::-D_REENTRANT::-ldl:SIXTY_FOUR_BIT RC4_CHUNK DES_INT DES_UNROLL:${no_asm}:dlfcn:linux-shared:-fPIC:-mx32:.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR):::x32",

 ####
EOF
	fi
}

add_automatic p11-kit
builddep_p11_kit() {
	# work around m-a:same violation in libffi-dev
	# texinfo stores its own version in the generated info docs
	apt_get_remove "libffi-dev:$(dpkg --print-architecture)"
	$APT_GET build-dep "-a$1" --arch-only p11-kit
}

add_automatic patch

add_automatic pcre3
patch_pcre3() {
	echo "work around FTBFS with gcc-7 #853606"
	# ignore symbol changes
	sed -i -e 's/\(dh_makeshlibs.*-- -c\)4$/\10/' debian/rules
}

add_automatic readline5
add_automatic rtmpdump
add_automatic sed
add_automatic slang2
add_automatic spdylay
add_automatic sqlite3

builddep_systemd() {
	# meson dependency unsatisfiable #859177
	# gcc-6 dependency unsatisfiable #871514
	apt-cache showsrc systemd | grep -q "^Build-Depends:.*gnu-efi[^,]*[[ ]$1[] ]" && apt_get_install gnu-efi
	apt-cache showsrc systemd | grep -q "^Build-Depends:.*libseccomp-dev[^,]*[[ ]$1[] ]" && apt_get_install "libseccomp-dev:$1"
	apt_get_install debhelper pkg-config xsltproc docbook-xsl docbook-xml m4 meson intltool gperf "libcap-dev:$1" "libpam0g-dev:$1" "libselinux1-dev:$1" "libacl1-dev:$1" "liblzma-dev:$1" "liblz4-dev:$1" "libgcrypt20-dev:$1" "libkmod-dev:$1" "libblkid-dev:$1" "libmount-dev:$1" python3 python3-lxml
}
patch_systemd() {
	echo "fix meson usage #859177"
	drop_privs patch -p1 <<'EOF'
--- a/debian/debcrossgen.py
+++ b/debian/debcrossgen.py
@@ -0,0 +1,48 @@
+#!/usr/bin/env python3
+
+# Copyright 2017 Jussi Pakkanen
+
+# Licensed under the Apache License, Version 2.0 (the "License");
+# you may not use this file except in compliance with the License.
+# You may obtain a copy of the License at
+
+#     http://www.apache.org/licenses/LICENSE-2.0
+
+# Unless required by applicable law or agreed to in writing, software
+# distributed under the License is distributed on an "AS IS" BASIS,
+# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+# See the License for the specific language governing permissions and
+# limitations under the License.
+
+import sys, os, subprocess
+
+def run():
+    output = subprocess.check_output(['dpkg-architecture'], universal_newlines=True)
+    data = {}
+    for line in output.split('\n'):
+        line = line.strip()
+        if line == '':
+            continue
+        k, v = line.split('=', 1)
+        data[k] = v
+    host_arch = data['DEB_HOST_GNU_TYPE']
+    host_os = data['DEB_HOST_ARCH_OS']
+    host_cpu_family = data['DEB_HOST_GNU_CPU']
+    host_cpu = data['DEB_HOST_ARCH'] # Not really correct, should be arm7hlf etc but it is not exposed.
+    host_endian = data['DEB_HOST_ARCH_ENDIAN']
+    ofile = sys.stdout
+    ofile.write('[binaries]\n')
+    ofile.write("c = '/usr/bin/%s-gcc'\n" % host_arch)
+    ofile.write("cpp = '/usr/bin/%s-g++'\n" % host_arch)
+    ofile.write("ar = '/usr/bin/%s-ar'\n" % host_arch)
+    ofile.write("strip = '/usr/bin/%s-strip'\n" % host_arch)
+    ofile.write("pkgconfig = '/usr/bin/%s-pkg-config'\n" % host_arch)
+    ofile.write('\n[properties]\n')
+    ofile.write('\n[host_machine]\n')
+    ofile.write("system = '%s'\n" % host_os)
+    ofile.write("cpu_family = '%s'\n" % host_cpu_family)
+    ofile.write("cpu = '%s'\n" % host_cpu)
+    ofile.write("endian = '%s'\n" % host_endian)
+
+if __name__ == '__main__':
+    run()
--- a/debian/rules
+++ b/debian/rules
@@ -64,6 +64,10 @@
 	-Dnobody-user=nobody \
 	-Dnobody-group=nogroup
 
+ifneq ($(DEB_BUILD_ARCH),$(DEB_HOST_ARCH))
+CONFFLAGS += --cross-file ../crossfile.txt
+endif
+
 # resolved's DNSSEC support is still not mature enough, don't enable it by
 # default on stable Debian or any Ubuntu releases
 CONFFLAGS += $(shell grep -qE 'stretch|ubuntu' /etc/os-release && echo -Ddefault-dnssec=no)
@@ -145,6 +149,9 @@
 	-Dsysusers=false
 
 override_dh_auto_configure:
+ifneq ($(DEB_BUILD_ARCH),$(DEB_HOST_ARCH))
+	python3 debian/debcrossgen.py > crossfile.txt
+endif
 	dh_auto_configure --builddirectory=build-deb \
 		-- $(CONFFLAGS) $(CONFFLAGS_deb)
 ifeq (, $(filter noudeb, $(DEB_BUILD_PROFILES)))
EOF
	echo "reverting gcc-6 switch #871514"
	drop_privs sed -i -e '/g..-6/d' debian/rules
}

add_automatic tar
buildenv_tar() {
	case $(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_SYSTEM) in *gnu*)
		echo "struct dirent contains working d_ino on glibc systems"
		export gl_cv_struct_dirent_d_ino=yes
	;; esac
	if ! dpkg-architecture "-a$HOST_ARCH" -ilinux-any; then
		echo "forcing broken posix acl check to fail on non-linux #850668"
		export gl_cv_getxattr_with_posix_acls=no
	fi
}

add_automatic tcl8.6
buildenv_tcl8_6() {
	export tcl_cv_strtod_buggy=ok
}

add_automatic tcltk-defaults
add_automatic tcp-wrappers

add_automatic tk8.6
buildenv_tk8_6() {
	export tcl_cv_strtod_buggy=ok
}

patch_unbound() {
	if ! dpkg-architecture -a"$HOST_ARCH" -ilinux-any; then
		echo "fixing unbound FTBFS on !linux-any #853751"
		drop_privs patch -p1 <<'EOF'
--- a/configure.ac
+++ b/configure.ac
@@ -707,6 +707,19 @@ AC_INCLUDES_DEFAULT
 fi
 AC_SUBST(SSLLIB)
 
+# libbsd
+AC_ARG_WITH([libbsd], AC_HELP_STRING([--with-libbsd], [Use portable libbsd functions]), [
+	AC_CHECK_HEADERS([bsd/string.h bsd/stdlib.h],,, [AC_INCLUDES_DEFAULT])
+	if test "x$ac_cv_header_bsd_string_h" = xyes -a "x$ac_cv_header_bsd_stdlib_h" = xyes; then
+		for func in strlcpy strlcat arc4random arc4random_uniform reallocarray; do
+			AC_SEARCH_LIBS([$func], [bsd], [
+				AC_DEFINE(HAVE_LIBBSD, 1, [Use portable libbsd functions])
+				PC_LIBBSD_DEPENDENCY=libbsd
+				AC_SUBST(PC_LIBBSD_DEPENDENCY)
+			])
+		done
+	fi
+])
 
 AC_ARG_ENABLE(sha2, AC_HELP_STRING([--disable-sha2], [Disable SHA256 and SHA512 RRSIG support]))
 case "$enable_sha2" in
@@ -1469,6 +1482,11 @@ struct tm;
 char *strptime(const char *s, const char *format, struct tm *tm);
 #endif
 
+#ifdef HAVE_LIBBSD
+#include <bsd/string.h>
+#include <bsd/stdlib.h>
+#endif
+
 #ifdef HAVE_LIBRESSL
 #  if !HAVE_DECL_STRLCPY
 size_t strlcpy(char *dst, const char *src, size_t siz);
--- a/contrib/libunbound.pc.in
+++ b/contrib/libunbound.pc.in
@@ -8,6 +8,7 @@ Description: Library with validating, recursive, and caching DNS resolver
 URL: http://www.unbound.net
 Version: @PACKAGE_VERSION@
 Requires: libcrypto libssl @PC_LIBEVENT_DEPENDENCY@ @PC_PY_DEPENDENCY@
+Requires.private: @PC_LIBBSD_DEPENDENCY@
 Libs: -L${libdir} -lunbound
 Libs.private: @SSLLIB@ @LIBS@
 Cflags: -I${includedir} 
--- a/util/random.c
+++ b/util/random.c
@@ -78,7 +78,7 @@
  */
 #define MAX_VALUE 0x7fffffff
 
-#if defined(HAVE_SSL)
+#if defined(HAVE_SSL) || defined(HAVE_LIBBSD)
 void
 ub_systemseed(unsigned int ATTR_UNUSED(seed))
 {
@@ -208,10 +208,10 @@ long int ub_random(struct ub_randstate* s)
 	}
 	return x & MAX_VALUE;
 }
-#endif /* HAVE_SSL or HAVE_NSS or HAVE_NETTLE */
+#endif /* HAVE_SSL or HAVE_LIBBSD or HAVE_NSS or HAVE_NETTLE */
 
 
-#if defined(HAVE_NSS) || defined(HAVE_NETTLE)
+#if defined(HAVE_NSS) || defined(HAVE_NETTLE) && !defined(HAVE_LIBBSD)
 long int
 ub_random_max(struct ub_randstate* state, long int x)
 {
@@ -223,7 +223,7 @@ ub_random_max(struct ub_randstate* state, long int x)
 		v = ub_random(state);
 	return (v % x);
 }
-#endif /* HAVE_NSS or HAVE_NETTLE */
+#endif /* HAVE_NSS or HAVE_NETTLE and !HAVE_LIBBSD */
 
 void 
 ub_randfree(struct ub_randstate* s)
--- a/debian/control
+++ b/debian/control
@@ -15,6 +15,7 @@ Build-Depends:
  dh-systemd <!pkg.unbound.libonly>,
  dpkg-dev (>= 1.16.1~),
  flex,
+ libbsd-dev (>= 0.8.1~) [!linux-any],
  libevent-dev,
  libexpat1-dev,
  libfstrm-dev <!pkg.unbound.libonly>,
--- a/debian/rules
+++ b/debian/rules
@@ -7,6 +7,10 @@ ifneq ($(DEB_HOST_ARCH), amd64)
 CONFIGURE_ARGS = --disable-flto
 endif
 
+ifneq ($(DEB_HOST_ARCH_OS), linux)
+CONFIGURE_ARGS = --with-libbsd
+endif
+
 LIBRARY = libunbound2
 DOPACKAGES = $(shell dh_listpackages)
 
EOF
	fi
}

add_automatic ustr
add_automatic xft
add_automatic xz-utils

$APT_GET install dose-builddebcheck dctrl-tools

call_dose_builddebcheck() {
	local package_list source_list errcode
	package_list=`mktemp packages.XXXXXXXXXX`
	source_list=`mktemp sources.XXXXXXXXXX`
	cat /var/lib/apt/lists/*_Packages - > "$package_list" <<EOF
Package: crossbuild-essential-$HOST_ARCH
Version: 0
Architecture: $HOST_ARCH
Multi-Arch: foreign
Depends: libc-dev
Description: fake crossbuild-essential package for dose-builddebcheck

EOF
	sed -i -e '/^Conflicts:.* libc[0-9][^ ]*-dev\(,\|$\)/d' "$package_list" # also make dose ignore the glibc conflict
	apt-cache show "gcc-${GCC_VER}-base=installed" libgcc1=installed libstdc++6=installed libatomic1=installed >> "$package_list" # helps when pulling gcc from experimental
	cat /var/lib/apt/lists/*_Sources > "$source_list"
	errcode=0
	dose-builddebcheck --deb-tupletable=/usr/share/dpkg/tupletable --deb-cputable=/usr/share/dpkg/cputable "--deb-native-arch=$(dpkg --print-architecture)" "--deb-host-arch=$HOST_ARCH" "$@" "$package_list" "$source_list" || errcode=$?
	if test "$errcode" -gt 1; then
		echo "dose-builddebcheck failed with error code $errcode" 1>&2
		exit 1
	fi
	rm -f "$package_list" "$source_list"
}

# determine whether a given binary package refers to an arch:all package
# $1 is a binary package name
is_arch_all() {
	grep-dctrl -P -X "$1" -a -F Architecture all -s /var/lib/apt/lists/*_Packages
}

# determine which source packages build a given binary package
# $1 is a binary package name
# prints a set of source packages
what_builds() {
	local newline pattern source
	newline='
'
	pattern=`echo "$1" | sed 's/[+.]/\\\\&/g'`
	pattern="$newline $pattern "
	# exit codes 0 and 1 signal successful operation
	source=`grep-dctrl -F Package-List -e "$pattern" -s Package -n /var/lib/apt/lists/*_Sources || test "$?" -eq 1`
	set_create "$source"
}

# determine a set of source package names which are essential to some
# architecture
discover_essential() {
	set_create "$(grep-dctrl -F Package-List -e '\bessential=yes\b' -s Package -n /var/lib/apt/lists/*_Sources)"
}

need_packages=
add_need() { need_packages=`set_add "$need_packages" "$1"`; }
built_packages=
mark_built() {
	need_packages=`set_discard "$need_packages" "$1"`
	built_packages=`set_add "$built_packages" "$1"`
}

for pkg in $(discover_essential); do
	if set_contains "$automatic_packages" "$pkg"; then
		echo "rebootstrap-debug: automatically scheduling essential package $pkg"
		add_need "$pkg"
	else
		echo "rebootstrap-debug: not scheduling essential package $pkg"
	fi
done
add_need acl # by coreutils, systemd
add_need attr # by coreutils, libcap-ng
add_need autogen # by gcc-VER, gnutls28
add_need bzip2 # by perl
add_need cloog # by gcc-VER
add_need db-defaults # by perl, python2.7, python3.5
add_need file # by gcc-6, for debhelper
add_need flex # by libsemanage, pam
dpkg-architecture "-a$HOST_ARCH" -ikfreebsd-any && add_need freebsd-glue # by freebsd-libs
add_need fuse # by e2fsprogs
add_need gdbm # by perl, python2.7
add_need gnupg2 # for apt
add_need gnutls28 # by libprelude, openldap
test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux && add_need gpm # by ncurses
add_need groff # for man-db
test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux && add_need kmod # by systemd
add_need icu # by libxml2
add_need krb5 # by audit
add_need libatomic-ops # by gcc-VER
add_need libbsd # by bsdmainutils, expat [kfreebsd-any]
dpkg-architecture "-a$HOST_ARCH" -ilinux-any && add_need libcap2 # by systemd
add_need libdebian-installer # by cdebconf
add_need libevent # by unbound
add_need libgcrypt20 # by libprelude, cryptsetup
add_need libpthread-stubs # by libxcb
if apt-cache showsrc systemd | grep -q "^Build-Depends:.*libseccomp-dev[^,]*[[ ]$HOST_ARCH[] ]"; then
	add_need libseccomp # by systemd
fi
dpkg-architecture "-a$HOST_ARCH" -ilinux-any && add_need libsepol # by libselinux
if dpkg-architecture "-a$HOST_ARCH" -ihurd-any || dpkg-architecture "-a$HOST_ARCH" -ikfreebsd-any; then
	add_need libsystemd-dummy # by nghttp2
fi
add_need libtextwrap # by cdebconf
add_need libunistring # by libidn2-0
add_need libx11 # by dbus
add_need libxau # by libxcb
add_need libxdmcp # by libxcb
add_need libxrender # by cairo
add_need lz4 # by systemd
add_need make-dfsg # for build-essential
add_need man-db # for debhelper
add_need mawk # for base-files (alternatively: gawk)
add_need mpclib3 # by gcc-VER
add_need mpfr4 # by gcc-VER
add_need nettle # by unbound
add_need openssl # by cyrus-sasl2
add_need patch # for dpkg-dev
add_need pcre3 # by libselinux
add_need readline5 # by lvm2
add_need slang2 # by cdebconf, newt
add_need sqlite3 # by python2.7
add_need tcl8.6 # by newt
add_need tcltk-defaults # by python2.7
dpkg-architecture "-a$HOST_ARCH" -ilinux-any && add_need tcp-wrappers # by audit
add_need tk8.6 # by blt
add_need xz-utils # by libxml2

automatically_cross_build_packages() {
	local need_packages_comma_sep dosetmp profiles buildable new_needed line pkg missing source
	while test -n "$need_packages"; do
		echo "checking packages with dose-builddebcheck: $need_packages"
		need_packages_comma_sep=`echo $need_packages | sed 's/ /,/g'`
		dosetmp=`mktemp -t doseoutput.XXXXXXXXXX`
		profiles="$DEFAULT_PROFILES"
		if test "$ENABLE_MULTILIB" = no; then
			profiles=$(set_add "$profiles" nobiarch)
		fi
		profiles=$(echo "$profiles" | tr ' ' ,)
		call_dose_builddebcheck --successes --failures --explain --latest=1 --deb-drop-b-d-indep "--deb-profiles=$profiles" "--checkonly=$need_packages_comma_sep" >"$dosetmp"
		buildable=
		new_needed=
		while IFS= read -r line; do
			case "$line" in
				"  package: "*)
					pkg=${line#  package: }
					pkg=${pkg#src:} # dose3 << 4.1
				;;
				"  status: ok")
					buildable=`set_add "$buildable" "$pkg"`
				;;
				"      unsat-dependency: "*)
					missing=${line#*: }
					missing=${missing%% | *} # drop alternatives
					missing=${missing% (* *)} # drop version constraint
					missing=${missing%:$HOST_ARCH} # skip architecture
					if is_arch_all "$missing"; then
						echo "rebootstrap-warning: $pkg misses dependency $missing which is arch:all"
					else
						source=`what_builds "$missing"`
						case "$source" in
							"")
								echo "rebootstrap-warning: $pkg transitively build-depends on $missing, but no source package could be determined"
							;;
							*" "*)
								echo "rebootstrap-warning: $pkg transitively build-depends on $missing, but it is build from multiple source packages: $source"
							;;
							*)
								if set_contains "$built_packages" "$source"; then
									echo "rebootstrap-warning: $pkg transitively build-depends on $missing, which is built from $source, which is supposedly already built"
								elif set_contains "$need_packages" "$source"; then
									echo "rebootstrap-debug: $pkg transitively build-depends on $missing, which is built from $source and already scheduled for building"
								elif set_contains "$automatic_packages" "$source"; then
									new_needed=`set_add "$new_needed" "$source"`
								else
									echo "rebootstrap-warning: $pkg transitively build-depends on $missing, which is built from $source but not automatic"
								fi
							;;
						esac
					fi
				;;
			esac
		done < "$dosetmp"
		rm "$dosetmp"
		echo "buildable packages: $buildable"
		echo "new packages needed: $new_needed"
		test -z "$buildable" -a -z "$new_needed" && break
		for pkg in $buildable; do
			echo "cross building $pkg"
			cross_build "$pkg"
			mark_built "$pkg"
		done
		need_packages=`set_union "$need_packages" "$new_needed"`
	done
	echo "done automatically cross building packages. left: $need_packages"
}

assert_built() {
	local missing_pkgs missing_pkgs_comma_sep profiles
	missing_pkgs=`set_difference "$1" "$built_packages"`
	test -z "$missing_pkgs" && return 0
	echo "rebootstrap-error: missing asserted packages: $missing_pkgs"
	missing_pkgs=`set_union "$missing_pkgs" "$need_packages"`
	missing_pkgs_comma_sep=`echo $missing_pkgs | sed 's/ /,/g'`
	profiles="$DEFAULT_PROFILES"
	if test "$ENABLE_MULTILIB" = no; then
		profiles=$(set_add "$profiles" nobiarch)
	fi
	profiles=$(echo "$profiles" | tr ' ' ,)
	call_dose_builddebcheck --failures --explain --latest=1 --deb-drop-b-d-indep "--deb-profiles=$profiles" "--checkonly=$missing_pkgs_comma_sep"
	return 1
}

automatically_cross_build_packages

builddep_zlib() {
	# gcc-multilib dependency unsatisfiable
	$APT_GET install debhelper binutils dpkg-dev
}
cross_build zlib "$(if test "$ENABLE_MULTILIB" != yes; then echo stage1; fi)"
mark_built zlib
# needed by dpkg, file, gnutls28, libpng1.6, libtool, libxml2, perl, slang2, tcl8.6, util-linux

automatically_cross_build_packages

builddep_libtool() {
	assert_built "zlib"
	test "$1" = "$HOST_ARCH"
	# gfortran dependency needs cross-translation
	# gnulib dependency lacks M-A:foreign
	apt_get_install debhelper file "gfortran-$GCC_VER$HOST_ARCH_SUFFIX" automake autoconf autotools-dev help2man texinfo "zlib1g-dev:$HOST_ARCH" gnulib
}
cross_build libtool
mark_built libtool
# needed by guile-2.0, libffi

automatically_cross_build_packages

builddep_ncurses() {
	if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
		assert_built gpm
		$APT_GET install "libgpm-dev:$1"
	fi
	# g++-multilib dependency unsatisfiable
	apt_get_install debhelper dpkg-dev pkg-config autotools-dev
	case "$ENABLE_MULTILIB:$HOST_ARCH" in
		yes:amd64|yes:i386|yes:powerpc|yes:ppc64|yes:s390|yes:sparc)
			test "$1" = "$HOST_ARCH"
			$APT_GET install "g++-$GCC_VER-multilib$HOST_ARCH_SUFFIX"
			# the unversioned gcc-multilib$HOST_ARCH_SUFFIX should contain the following link
			ln -sf "`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH`/asm" /usr/include/asm
		;;
	esac
}
cross_build ncurses
mark_built ncurses
# needed by bash, bsdmainutils, dpkg, guile-2.0, readline, slang2

automatically_cross_build_packages

patch_readline() {
	echo "patching readline to support nobiarch profile #737955"
	drop_privs patch -p1 <<EOF
--- a/debian/control
+++ b/debian/control
@@ -4,11 +4,11 @@
 Maintainer: Matthias Klose <doko@debian.org>
 Standards-Version: 3.9.8
 Build-Depends: debhelper (>= 9),
-  libtinfo-dev, lib32tinfo-dev [amd64 ppc64],
+  libtinfo-dev, lib32tinfo-dev [amd64 ppc64] <!nobiarch>,
   libncursesw5-dev (>= 5.6),
-  lib32ncursesw5-dev [amd64 ppc64], lib64ncurses5-dev [i386 powerpc sparc s390],
+  lib32ncursesw5-dev [amd64 ppc64] <!nobiarch>, lib64ncurses5-dev [i386 powerpc sparc s390] <!nobiarch>,
   mawk | awk, texinfo, autotools-dev,
-  gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc]
+  gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc] <!nobiarch>
 
 Package: libreadline7
 Architecture: any
@@ -30,6 +30,7 @@
 Depends: readline-common, \${shlibs:Depends}, \${misc:Depends}
 Section: libs
 Priority: optional
+Build-Profiles: <!nobiarch>
 Description: GNU readline and history libraries, run-time libraries (64-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
@@ -96,6 +97,7 @@
 Conflicts: lib64readline-dev, lib64readline-gplv2-dev
 Section: libdevel
 Priority: optional
+Build-Profiles: <!nobiarch>
 Description: GNU readline and history libraries, development files (64-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
@@ -139,6 +141,7 @@
 Depends: readline-common, \${shlibs:Depends}, \${misc:Depends}
 Section: libs
 Priority: optional
+Build-Profiles: <!nobiarch>
 Description: GNU readline and history libraries, run-time libraries (32-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
@@ -154,6 +157,7 @@
 Conflicts: lib32readline-dev, lib32readline-gplv2-dev
 Section: libdevel
 Priority: optional
+Build-Profiles: <!nobiarch>
 Description: GNU readline and history libraries, development files (32-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
--- a/debian/rules
+++ b/debian/rules
@@ -57,6 +57,11 @@
   endif
 endif
 
+ifneq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+build32 =
+build64 =
+endif
+
 CFLAGS := \$(shell dpkg-buildflags --get CFLAGS)
 CPPFLAGS := \$(shell dpkg-buildflags --get CPPFLAGS)
 LDFLAGS := \$(shell dpkg-buildflags --get LDFLAGS)
EOF
}
builddep_readline() {
	assert_built "ncurses"
	# gcc-multilib dependency unsatisfiable
	$APT_GET install debhelper "libtinfo-dev:$1" "libncursesw5-dev:$1" mawk texinfo autotools-dev
	case "$ENABLE_MULTILIB:$HOST_ARCH" in
		yes:amd64|yes:ppc64)
			test "$1" = "$HOST_ARCH"
			$APT_GET install "gcc-$GCC_VER-multilib$HOST_ARCH_SUFFIX" "lib32tinfo-dev:$1" "lib32ncursesw5-dev:$1"
			# the unversioned gcc-multilib$HOST_ARCH_SUFFIX should contain the following link
			ln -sf "`dpkg-architecture -a$1 -qDEB_HOST_MULTIARCH`/asm" /usr/include/asm
		;;
		yes:i386|yes:powerpc|yes:sparc|yes:s390)
			test "$1" = "$HOST_ARCH"
			$APT_GET install "gcc-$GCC_VER-multilib$HOST_ARCH_SUFFIX" "lib64ncurses5-dev:$1"
			# the unversioned gcc-multilib$HOST_ARCH_SUFFIX should contain the following link
			ln -sf "`dpkg-architecture -a$1 -qDEB_HOST_MULTIARCH`/asm" /usr/include/asm
		;;
	esac
}
cross_build readline
mark_built readline
# needed by gnupg2, guile-2.0, libxml2

automatically_cross_build_packages

if dpkg-architecture "-a$HOST_ARCH" -ilinux-any; then
if test -f "$REPODIR/stamps/libselinux_1"; then
	echo "skipping rebuild of libselinux stage1"
else
	cross_build_setup libselinux libselinux1
	assert_built "libsepol pcre3"
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -P nopython,noruby ./
	check_binNMU
	drop_privs dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -Pnopython,noruby
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libselinux_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libselinux1
fi
progress_mark "libselinux stage1 cross build"
mark_built libselinux
# needed by coreutils, dpkg, findutils, glibc, sed, tar, util-linux

automatically_cross_build_packages
fi # $HOST_ARCH matches linux-any

builddep_util_linux() {
	dpkg-architecture "-a$1" -ilinux-any && assert_built libselinux
	assert_built "ncurses slang2 zlib"
	$APT_GET build-dep "-a$1" --arch-only -P "$2" util-linux
}
if test -f "$REPODIR/stamps/util-linux_1"; then
	echo "skipping rebuild of util-linux stage1"
else
	builddep_util_linux "$HOST_ARCH" stage1
	cross_build_setup util-linux util-linux_1
	check_binNMU
	drop_privs scanf_cv_type_modifier=ms dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/util-linux_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf util-linux_1
fi
progress_mark "util-linux stage1 cross build"
mark_built util-linux
# essential, needed by e2fsprogs

automatically_cross_build_packages

builddep_bsdmainutils() {
	assert_built "ncurses libbsd"
	# python-hdate dependency unsatisfiable #792867
	apt_get_install debhelper "libncurses5-dev:$1" quilt python python-hdate "libbsd-dev:$1"
}
cross_build bsdmainutils
mark_built bsdmainutils
# needed for man-db

automatically_cross_build_packages

builddep_db5_3() {
	# java stuff lacks build profile annotation
	apt_get_install debhelper autotools-dev procps
}
if test -f "$REPODIR/stamps/db5.3_1"; then
	echo "skipping stage1 rebuild of db5.3"
else
	cross_build_setup db5.3 db5.3_1
	builddep_db5_3 "$HOST_ARCH"
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_STAGE=stage1 dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/db5.3_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf db5.3_1
fi
progress_mark "db5.3 stage1 cross build"
mark_built db5.3
# needed by perl, python2.7, needed for db-defaults and thus by freebsd-glue

automatically_cross_build_packages

cross_build expat
mark_built expat
# needed by fontconfig, for freebsd-glue and thus by xz-utils

automatically_cross_build_packages

cross_build elfutils
mark_built elfutils
# needed by glib2.0, systemtap

automatically_cross_build_packages

builddep_libxcb() {
	assert_built "libxau libxdmcp libpthread-stubs"
	# check dependency lacks nocheck profile annotation
	# python dependency lacks :native annotation #788861
	$APT_GET install "libxau-dev:$1" "libxdmcp-dev:$1" xcb-proto "libpthread-stubs0-dev:$1" debhelper pkg-config xsltproc  python-xcbgen libtool automake python dctrl-tools xutils-dev
}
cross_build libxcb
mark_built libxcb
# needed by libx11

automatically_cross_build_packages

cross_build libidn
mark_built libidn
# needed by gnutls28

automatically_cross_build_packages

if test -f "$REPODIR/stamps/libxml2_1"; then
	echo "skipping rebuild of libxml2 nopython"
else
	cross_build_setup libxml2 libxml2_1
	# rename dependency unsatisfiable #872315
	apt_get_install debhelper "libicu-dev:$HOST_ARCH" "liblzma-dev:$HOST_ARCH" pkg-config rename "zlib1g-dev:$HOST_ARCH"
	check_binNMU
	drop_privs dpkg-buildpackage "-a$HOST_ARCH" -B -Pnopython -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libxml2_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libxml2_1
fi
progress_mark "libxml2 nopython cross build"
mark_built libxml2
# needed by autogen

automatically_cross_build_packages

builddep_cracklib2() {
	# python-all-dev lacks build profile annotation
	$APT_GET install autoconf automake autotools-dev chrpath debhelper docbook-utils docbook-xml dpkg-dev libtool python dh-python
	# additional B-D for cross
	$APT_GET install cracklib-runtime
}
if test -f "$REPODIR/stamps/cracklib2_1"; then
	echo "skipping stage1 rebuild of cracklib2"
else
	builddep_cracklib2 "$HOST_ARCH"
	cross_build_setup cracklib2 cracklib2_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_STAGE=stage1 dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/cracklib2_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf cracklib2_1
fi
progress_mark "cracklib2 stage1 cross build"
mark_built cracklib2
# needed by pam

automatically_cross_build_packages

cross_build build-essential
mark_built build-essential
# build-essential

automatically_cross_build_packages

builddep_pam() {
	dpkg-architecture "-a$1" -ilinux-any && assert_built libselinux
	assert_built "cracklib2 db-defaults db5.3 flex"
	dpkg-architecture "-a$1" -ilinux-any && apt_get_install "libselinux1-dev:$1"
	apt_get_install "libcrack2-dev:$1" bzip2 debhelper quilt flex "libdb-dev:$1" po-debconf dh-autoreconf autopoint pkg-config
	# flex wrongly declares M-A:foreign #761449
	apt_get_install flex "libfl-dev:$1" libfl-dev
}
if test -f "$REPODIR/stamps/pam_1"; then
	echo "skipping stage1 rebuild of pam"
else
	builddep_pam "$HOST_ARCH"
	cross_build_setup pam pam_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_BUILD_PROFILE=stage1 dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/pam_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf pam_1
fi
progress_mark "pam stage1 cross build"
mark_built pam
# needed by shadow

automatically_cross_build_packages

builddep_cyrus_sasl2() {
	assert_built "db-defaults db5.3 openssl pam"
	# many packages droppable in stage1
	$APT_GET install debhelper quilt automake autotools-dev "libdb-dev:$1" "libpam0g-dev:$1" "libssl-dev:$1" chrpath groff-base po-debconf docbook-to-man dh-autoreconf
}
patch_cyrus_sasl2() {
	echo "fixing cyrus-sasl2 compilation of build tools #792851"
	drop_privs patch -p1 <<'EOF'
diff -Nru cyrus-sasl2-2.1.26.dfsg1/debian/patches/cross.patch cyrus-sasl2-2.1.26.dfsg1/debian/patches/cross.patch
--- cyrus-sasl2-2.1.26.dfsg1/debian/patches/cross.patch
+++ cyrus-sasl2-2.1.26.dfsg1/debian/patches/cross.patch
@@ -0,0 +1,17 @@
+Description: fix cross compialtion
+Author: Helmut Grohne <helmut@subdivi.de>
+
+ * Remove SASL_DB_LIB as it expands to -ldb and make fails to find a build arch
+   -ldb.
+
+--- a/sasldb/Makefile.am
++++ b/sasldb/Makefile.am
+@@ -55,7 +55,7 @@
+ 
+ libsasldb_la_SOURCES = allockey.c sasldb.h
+ EXTRA_libsasldb_la_SOURCES = $(extra_common_sources)
+-libsasldb_la_DEPENDENCIES = $(SASL_DB_BACKEND) $(SASL_DB_LIB)
++libsasldb_la_DEPENDENCIES = $(SASL_DB_BACKEND)
+ libsasldb_la_LIBADD = $(SASL_DB_BACKEND) $(SASL_DB_LIB)
+ 
+ # Prevent make dist stupidity
diff -Nru cyrus-sasl2-2.1.26.dfsg1/debian/rules cyrus-sasl2-2.1.26.dfsg1/debian/rules
--- cyrus-sasl2-2.1.26.dfsg1/debian/rules
+++ cyrus-sasl2-2.1.26.dfsg1/debian/rules
@@ -25,4 +25,8 @@
 include /usr/share/dpkg/default.mk
 
+ifeq ($(origin CC),default)
+export CC=$(DEB_HOST_GNU_TYPE)-gcc
+endif
+
 # Save Berkeley DB used for building the package
 BDB_VERSION ?= $(shell LC_ALL=C dpkg-query -l 'libdb[45].[0-9]-dev' | grep ^ii | sed -e 's|.*\s\libdb\([45]\.[0-9]\)-dev\s.*|\1|')
diff -Nru cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile
--- cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile
+++ cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile
@@ -7,7 +7,7 @@
 all: sample-server sample-client
 
 sample-server: sample-server.c
-	gcc $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -g -o sample-server sample-server.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
+	$(CC) $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -g -o sample-server sample-server.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
 
 sample-client: sample-client.c
-	gcc $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -g -o sample-client sample-client.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
+	$(CC) $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -g -o sample-client sample-client.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
EOF
	echo cross.patch | drop_privs tee -a debian/patches/series >/dev/null
	drop_privs quilt push -a
}
if test -f "$REPODIR/stamps/cyrus-sasl2_1"; then
	echo "skipping stage1 rebuild of cyrus-sasl2"
else
	builddep_cyrus_sasl2 "$HOST_ARCH"
	cross_build_setup cyrus-sasl2 cyrus-sasl2_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS no-sql no-ldap no-gssapi" dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/cyrus-sasl2_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf cyrus-sasl2_1
fi
progress_mark "cyrus-sasl2 stage1 cross build"
mark_built cyrus-sasl2
# needed by openldap

automatically_cross_build_packages

if test -f "$REPODIR/stamps/unbound_1"; then
	echo "skipping stage1 rebuild of unbound"
else
	assert_built "libevent expat nettle"
	dpkg-architecture "-a$HOST_ARCH" -ilinux-any || assert_built libbsd
	cross_build_setup unbound unbound_1
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -P pkg.unbound.libonly ./
	check_binNMU
	drop_privs dpkg-buildpackage "-a$HOST_ARCH" -B -uc -us -Ppkg.unbound.libonly
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/unbound_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf unbound_1
fi
progress_mark "unbound stage1 cross build"
mark_built unbound
# needed by gnutls28

automatically_cross_build_packages

cross_build libidn2-0
mark_built libidn2-0
# needed by curl, gnutls28

automatically_cross_build_packages

if test -f "$REPODIR/stamps/openldap_1"; then
	echo "skipping stage1 rebuild of openldap"
else
	assert_built "gnutls28 cyrus-sasl2"
	$APT_GET build-dep "-a$HOST_ARCH" --arch-only -P stage1 openldap
	cross_build_setup openldap openldap_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1 || : # tell unmet build depends
	drop_privs ol_cv_pthread_select_yields=yes ac_cv_func_memcmp_working=yes dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/openldap_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf openldap_1
fi
progress_mark "openldap stage1 cross build"
mark_built openldap
# needed by curl

automatically_cross_build_packages

if apt-cache showsrc systemd | grep -q "^Build-Depends:.*gnu-efi[^,]*[[ ]$HOST_ARCH[] ]"; then
cross_build gnu-efi
mark_built gnu-efi
# needed by systemd

automatically_cross_build_packages
fi

if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
if test -f "$REPODIR/stamps/systemd_1"; then
	echo "skipping stage1 rebuild of systemd"
else
	cross_build_setup systemd systemd_1
	assert_built "libcap2 pam libselinux acl xz-utils libgcrypt20 kmod util-linux"
	if grep -q "^Build-Depends:.*libseccomp-dev[^,]*[[ ]$HOST_ARCH[] ]" debian/control; then
		assert_built libseccomp
	fi
	builddep_systemd "$HOST_ARCH" "nocheck noudeb stage1"
	check_binNMU
	drop_privs ac_cv_func_malloc_0_nonnull=yes dpkg-buildpackage "-a$HOST_ARCH" -B -uc -us -Pnocheck,noudeb,stage1 -d
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/systemd_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf systemd_1
fi
progress_mark "systemd stage1 cross build"
mark_built systemd
fi
# needed by util-linux

automatically_cross_build_packages

builddep_e2fsprogs() {
	assert_built "fuse attr util-linux"
	# dietlibc-dev lacks build profile annotation
	apt_get_install gettext texinfo pkg-config "libfuse-dev:$1" "libattr1-dev:$1" debhelper "libblkid-dev:$1" "uuid-dev:$1" m4
}
cross_build e2fsprogs
mark_built e2fsprogs
# essential

automatically_cross_build_packages

if dpkg-architecture "-a$HOST_ARCH" -ilinux-any; then
if test -f "$REPODIR/stamps/libcap-ng_1"; then
	echo "skipping rebuild of libcap-ng stage1"
else
	cross_build_setup libcap-ng libcap-ng_1
	assert_built attr
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -Pnopython ./
	check_binNMU
	drop_privs dpkg-buildpackage -B -uc -us -a$HOST_ARCH -Pnopython
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libcap-ng_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libcap-ng_1
fi
progress_mark "libcap-ng stage1 cross build"
mark_built libcap-ng
# needed by audit, dbus

automatically_cross_build_packages
fi # $HOST_ARCH matches linux-any

if dpkg-architecture "-a$HOST_ARCH" -ilinux-any; then
if test -f "$REPODIR/stamps/libprelude_1"; then
	echo "skipping rebuild of libprelude stage1"
else
	cross_build_setup libprelude libprelude_1
	assert_built "gnutls28 libgcrypt20 libtool"
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -Pnolua,noperl,nopython,noruby ./
	check_binNMU
	(
		buildenv_libprelude
		drop_privs_exec dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -Pnolua,noperl,nopython,noruby
	)
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libprelude_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libprelude_1
fi
progress_mark "libprelude stage1 cross build"
mark_built libprelude
# needed by audit, dbus

automatically_cross_build_packages

if test -f "$REPODIR/stamps/audit_1"; then
	echo "skipping stage1 rebuild of audit"
else
	cross_build_setup audit audit_1
	assert_built "libcap-ng krb5 openldap libprelude tcp-wrappers"
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -Pnopython ./
	check_binNMU
	drop_privs dpkg-buildpackage "-a$HOST_ARCH" -B -uc -us -Pnopython
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/audit_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf audit_1
fi
progress_mark "audit stage1 cross build"
mark_built audit
# needed by libsemanage
fi # $HOST_ARCH matches linux-any

automatically_cross_build_packages

if test -f "$REPODIR/stamps/libsemanage_1"; then
	echo "skipping stage1 rebuild of libsemanage"
else
	cross_build_setup libsemanage libsemanage_1
	assert_built "audit bzip2 libselinux libsepol"
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -Pnocheck,nopython,noruby ./
	check_binNMU
	drop_privs dpkg-buildpackage "-a$HOST_ARCH" -B -uc -us -Pnocheck,nopython,noruby
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libsemanage_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libsemanage_1
fi
progress_mark "libsemanage stage1 cross build"
mark_built libsemanage
# needed by shadow

automatically_cross_build_packages

cross_build util-linux # stageless
# essential

automatically_cross_build_packages

cross_build apt
mark_built apt
# almost essential

automatically_cross_build_packages

assert_built "$need_packages"

echo "checking installability of build-essential with dose"
# work around botch being uninstallable #871469 https://caml.inria.fr/mantis/view.php?id=7642
$APT_GET update
(
	cd /tmp
	$APT_GET download botch
	dpkg-deb -x botch_*.deb botch
)
package_list=$(mktemp -t packages.XXXXXXXXXX)
grep-dctrl --exact --field Architecture '(' "$HOST_ARCH" --or all ')' /var/lib/apt/lists/*_Packages > "$package_list"
/tmp/botch/usr/bin/botch-distcheck-more-problems "--deb-native-arch=$HOST_ARCH" --successes --failures --explain --checkonly "build-essential:$HOST_ARCH" "--bg=deb://$package_list" "--fg=deb://$package_list" || :
rm -f "$package_list"
