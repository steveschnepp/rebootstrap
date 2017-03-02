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
			if test linux != "$(dpkg-architecture "-a$2" -qDEB_HOST_ARCH_OS)"; then
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

echo "adding arm64ilp32 to dpkg's cputable #824742"
cat <<EOF >> /usr/share/dpkg/cputable
arm64be       	aarch64_be	aarch64_be		64	big
arm64ilp32	aarch64		aarch64_ilp32		32	little
arm64ilp32be	aarch64_be	aarch64_be_ilp32       	32	big
EOF

if test -z "$HOST_ARCH" || ! dpkg-architecture "-a$HOST_ARCH"; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
fi
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
	test -f "$f" && sed -i "s/^deb \(\[.*\] \)*/deb [ arch-=$HOST_ARCH ] /" $f
done
grep -q '^deb-src ' /etc/apt/sources.list || echo "deb-src $MIRROR sid main" >> /etc/apt/sources.list

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
echo "deb [ arch=`dpkg --print-architecture`,$HOST_ARCH trusted=yes ] file://$REPODIR rebootstrap main" >/etc/apt/sources.list.d/rebootstrap.list
echo "deb [ arch=`dpkg --print-architecture` trusted=yes ] file://$REPODIR rebootstrap-native main" >/etc/apt/sources.list.d/rebootstrap-native.list
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

if test "$HOST_ARCH" = nios2; then
	echo "fixing libtool's nios2 misdetection as os2 #851253"
	apt_get_install libtool
	sed -i -e 's/\*os2\*/*-os2*/' /usr/share/libtool/build-aux/ltmain.sh
fi

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
			sed -i -e '/^ .* .* .*_.*_.*\.buildinfo/d' "$f" # work around #843402
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
patch_gcc_os_include_dir_musl() {
	echo "cherry picking gcc-trunk 219388 for musl"
	drop_privs patch -p1 <<'EOF'
diff -u gcc-4.9-4.9.2/debian/rules.patch gcc-4.9-4.9.2/debian/rules.patch
--- gcc-4.9-4.9.2/debian/rules.patch
+++ gcc-4.9-4.9.2/debian/rules.patch
@@ -216,6 +216,10 @@
   debian_patches += fix-powerpcspe
 endif
 
+ifneq (,$(findstring musl-linux-,$(DEB_TARGET_ARCH)))
+  debian_patches += musl
+endif
+
 #debian_patches += link-libs
 
 # all patches below this line are applied for gcc-snapshot builds as well
--- gcc-4.9-4.9.2.orig/debian/patches/musl.diff
+++ gcc-4.9-4.9.2/debian/patches/musl.diff
@@ -0,0 +1,13 @@
+gcc svn revision 219388
+--- a/src/libstdc++-v3/configure.host
++++ b/src/libstdc++-v3/configure.host
+@@ -271,6 +271,9 @@
+   freebsd*)
+     os_include_dir="os/bsd/freebsd"
+     ;;
++  linux-musl*)
++    os_include_dir="os/generic"
++    ;;
+   gnu* | linux* | kfreebsd*-gnu | knetbsd*-gnu)
+     if [ "$uclibc" = "yes" ]; then
+       os_include_dir="os/uclibc"
EOF
}
patch_gcc_musl_arm() {
	echo "patching gcc to correctly detect arm architectures"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -376,7 +376,7 @@
 endif

 # check if we're building for armel or armhf
-ifeq ($(DEB_TARGET_ARCH),armhf)
+ifneq (,$(filter %eabihf,$(DEB_TARGET_GNU_SYSTEM)))
   float_abi := hard
 else ifneq (,$(filter $(distribution)-$(DEB_TARGET_ARCH), Ubuntu-armel))
   ifneq (,$(filter $(distrelease),lucid maverick natty oneiric precise))
--- a/debian/rules2
+++ b/debian/rules2
@@ -483,7 +483,7 @@
   CONFARGS += --disable-sjlj-exceptions
   # FIXME: libjava is not ported for thumb, this hack only works for
   # separate gcj builds
-  ifneq (,$(filter armhf,$(DEB_TARGET_ARCH)))
+  ifneq (,$(filter %armhf,$(DEB_TARGET_ARCH)))
     ifeq ($(distribution),Raspbian)
       with_arm_arch = armv6
       with_arm_fpu = vfp
EOF
}
patch_gcc_rtlibs_base_dep() {
	test "$ENABLE_MULTIARCH_GCC" != yes || return 0
	echo "patching gcc rtlibs to emit deps on gcc-VER-base"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control.m4
+++ b/debian/control.m4
@@ -123,8 +123,8 @@
 define(`SOFTBASEDEP', `gcc`'PV`'TS-base (>= ${gcc:SoftVersion})')
 
 ifdef(`TARGET',`
-define(`BASELDEP', `gcc`'PV-cross-base`'GCC_PORTS_BUILD (= ${gcc:Version})')
-define(`SOFTBASELDEP', `gcc`'PV-cross-base`'GCC_PORTS_BUILD (>= ${gcc:SoftVersion})')
+define(`BASELDEP', `gcc`'PV`'ifelse(CROSS_ARCH,`all',`-cross')-base`'GCC_PORTS_BUILD (= ${gcc:Version})')
+define(`SOFTBASELDEP', `gcc`'PV`'ifelse(CROSS_ARCH, `all',`-cross')-base`'GCC_PORTS_BUILD (>= ${gcc:SoftVersion})')
 ',`dnl
 define(`BASELDEP', `BASEDEP')
 define(`SOFTBASELDEP', `SOFTBASEDEP')
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
patch_gcc_tilegx_multiarch() {
	test "$HOST_ARCH" = tilegx || return 0
	echo "patching gcc to consider multiarch paths for tilegx #827578"
	drop_privs tee -a debian/patches/gcc-multiarch.diff >/dev/null <<'EOF'
--- a/src/gcc/config/tilegx/t-tilegx
+++ a/src/gcc/config/tilegx/t-tilegx
@@ -1,6 +1,7 @@
 MULTILIB_OPTIONS = m64/m32
 MULTILIB_DIRNAMES = 64 32
-MULTILIB_OSDIRNAMES = ../lib ../lib32
+MULTILIB_OSDIRNAMES = ../lib$(call if_multiarch,:tilegx-linux-gnu) ../lib32$(call if_multiarch,:tilegx32-linux-gnu)
+MULTIARCH_DIRNAME = $(call if_multiarch,tilegx-linux-gnu)

 LIBGCC = stmp-multilib
 INSTALL_LIBGCC = install-multilib
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
		echo "fixing multilib libc dependencies"
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
patch_gcc_nobrig() {
	case "$HOST_ARCH" in amd64|i386|x32)
		echo "allow disabling brig in gcc #856452"
		drop_privs patch -p1 <<'EOF'
--- a/debian/rules.defs
+++ a/debian/rules.defs
@@ -843,6 +843,7 @@
   with_brigdev := yes
   with_libhsailrt := yes
 endif
+with_brig := $(call envfilt, brig, , , $(with_brig))

 ifeq ($(with_brig),yes)
   enabled_languages += brig
EOF
	;; esac
}
patch_gcc_wdotap() {
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		echo "applying patches for with_deps_on_target_arch_pkgs"
		drop_privs QUILT_PATCHES="/usr/share/cross-gcc/patches/gcc-$GCC_VER" quilt push -a
		drop_privs rm -Rf .pc
	fi
}
patch_gcc_5() {
	patch_gcc_os_include_dir_musl
	patch_gcc_musl_arm
	patch_gcc_include_multiarch
	echo "patching gcc-5 to support building without binutils-multiarch #804190"
	drop_privs patch -p1 <<'EOF'
diff -u gcc-5-5.2.1/debian/rules.d/binary-ada.mk gcc-5-5.2.1/debian/rules.d/binary-ada.mk
--- gcc-5-5.2.1/debian/rules.d/binary-ada.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-ada.mk
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
diff -u gcc-5-5.2.1/debian/rules.d/binary-fortran.mk gcc-5-5.2.1/debian/rules.d/binary-fortran.mk
--- gcc-5-5.2.1/debian/rules.d/binary-fortran.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-fortran.mk
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
diff -u gcc-5-5.2.1/debian/rules.d/binary-go.mk gcc-5-5.2.1/debian/rules.d/binary-go.mk
--- gcc-5-5.2.1/debian/rules.d/binary-go.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-go.mk
@@ -120,7 +120,7 @@
 	  >> debian/$(p_l)/usr/share/lintian/overrides/$(p_l)
 
 	: # don't strip: https://gcc.gnu.org/ml/gcc-patches/2015-02/msg01722.html
-	: # dh_strip -p$(p_l) --dbg-package=$(p_d)
+	: # $(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.d/binary-libasan.mk gcc-5-5.2.1/debian/rules.d/binary-libasan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libasan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libasan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libatomic.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
diff -u gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libcilkrts.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
diff -u gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk
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
diff -u gcc-5-5.2.1/debian/rules.d/binary-libgccjit.mk gcc-5-5.2.1/debian/rules.d/binary-libgccjit.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libgccjit.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libgccjit.mk
@@ -42,7 +42,7 @@
 	debian/dh_doclink -p$(p_jitdev) $(p_base)
 	debian/dh_doclink -p$(p_jitdbg) $(p_base)
 
-	dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
+	$(cross_strip) dh_strip -p$(p_jitlib) --dbg-package=$(p_jitdbg)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_jitlib)
 	$(call cross_mangle_shlibs,$(p_jitlib))
 	$(ignshld)$(cross_shlibdeps) dh_shlibdeps -p$(p_jitlib)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libgomp.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
diff -u gcc-5-5.2.1/debian/rules.d/binary-libitm.mk gcc-5-5.2.1/debian/rules.d/binary-libitm.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libitm.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libitm.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libitm.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
diff -u gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libmpx.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
diff -u gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk
@@ -65,7 +65,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l) -Xlibobjc_gc.so
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	ln -sf libquadmath.symbols debian/$(p_l).symbols
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
diff -u gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk
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
diff -u gcc-5-5.2.1/debian/rules.d/binary-libtsan.mk gcc-5-5.2.1/debian/rules.d/binary-libtsan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libtsan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libtsan.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l)
 	$(call cross_mangle_shlibs,$(p_l))
 	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
diff -u gcc-5-5.2.1/debian/rules.defs gcc-5-5.2.1/debian/rules.defs
--- gcc-5-5.2.1/debian/rules.defs
+++ gcc-5-5.2.1/debian/rules.defs
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
	echo "patching gcc to always detect the availability of glibc's limits.h even in multiarch locations"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.patch
+++ b/debian/rules.patch
@@ -91,6 +91,8 @@
 	pr67590 \
 	pr67736 \
 
+debian_patches += multiarch-limits-h
+
 # this is still needed on powerpc, e.g. firefox and insighttoolkit4 will ftbfs.
 ifneq (,$(filter $(DEB_TARGET_ARCH),powerpc))
   debian_patches += pr65913-workaround
--- /dev/null
+++ b/debian/patches/multiarch-limits-h.diff
@@ -0,0 +1,11 @@
+--- a/src/gcc/Makefile.in
++++ b/src/gcc/Makefile.in
+@@ -494,7 +494,7 @@
+ STMP_FIXINC = @STMP_FIXINC@
+ 
+ # Test to see whether <limits.h> exists in the system header files.
+-LIMITS_H_TEST = [ -f $(SYSTEM_HEADER_DIR)/limits.h ]
++LIMITS_H_TEST = :
+ 
+ # Directory for prefix to system directories, for
+ # each of $(system_prefix)/usr/include, $(system_prefix)/usr/lib, etc.
EOF
	echo "fixing gcc stage2 control file to contain libgcc4 for hppa"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.conf
+++ b/debian/rules.conf
@@ -683,7 +683,7 @@
   addons += $(if $(findstring armhf,$(biarchsfarchs)),armml)
   addons += $(if $(findstring amd64,$(biarchx32archs)),x32dev)
   ifeq ($(DEB_STAGE),stage2)
-    addons += libgcc
+    addons += libgcc lib4gcc
     ifeq ($(multilib),yes)
       addons += lib32gcc lib64gcc libn32gcc
       addons += $(if $(findstring amd64,$(biarchx32archs)),libx32gcc)
EOF
	echo "fixing gcc rtlibs to build the non-cross base"
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
	patch_gcc_rtlibs_base_dep
	patch_gcc_rtlibs_libatomic
	if test "$HOST_ARCH" = nios2; then
		echo "patching gcc for nios2 https://gcc.gnu.org/git/?p=gcc.git;a=commitdiff;h=1d67120d95c2c6e0ed4f7357d1cc62887eaba463"
		drop_privs patch -p1 <<'EOF'
diff -Naru a/debian/patches/ijmp_regs.diff b/debian/patches/ijmp_regs.diff
--- a/debian/patches/ijmp_regs.diff	1970-01-01 01:00:00.000000000 +0100
+++ b/debian/patches/ijmp_regs.diff	2016-01-12 16:16:39.000000000 +0100
@@ -0,0 +1,101 @@
+From 1d67120d95c2c6e0ed4f7357d1cc62887eaba463 Mon Sep 17 00:00:00 2001
+From: sandra <sandra@138bc75d-0d04-0410-961f-82ee72b054a4>
+Date: Tue, 12 May 2015 15:57:22 +0000
+Subject: [PATCH] 2015-05-12  Chung-Lin Tang  <cltang@codesourcery.com> 	   
+ Sandra Loosemore <sandra@codesourcery.com>
+
+	gcc/
+	* config/nios2/nios2.h (enum reg_class): Add IJMP_REGS enum
+	value.
+	(REG_CLASS_NAMES): Add "IJMP_REGS".
+	(REG_CLASS_CONTENTS): Add new entry for IJMP_REGS.
+	* config/nios2/nios2.md (indirect_jump,*tablejump): Adjust to
+	use new "c" register constraint.
+	* config/nios2/constraint.md (c): New register constraint
+	corresponding to IJMP_REGS.
+
+
+
+git-svn-id: svn+ssh://gcc.gnu.org/svn/gcc/trunk@223082 138bc75d-0d04-0410-961f-82ee72b054a4
+---
+ src/gcc/ChangeLog                   | 12 ++++++++++++
+ src/gcc/config/nios2/constraints.md |  3 +++
+ src/gcc/config/nios2/nios2.h        | 11 +++++++----
+ src/gcc/config/nios2/nios2.md       |  4 ++--
+ 4 files changed, 24 insertions(+), 6 deletions(-)
+
+diff --git a/src/gcc/config/nios2/constraints.md b/src/gcc/config/nios2/constraints.md
+index f4bd9f7..735f892 100644
+--- a/src/gcc/config/nios2/constraints.md
++++ b/src/gcc/config/nios2/constraints.md
+@@ -39,6 +39,9 @@
+ 
+ ;; Register constraints
+ 
++(define_register_constraint "c" "IJMP_REGS"
++  "A register suitable for an indirect jump.")
++
+ (define_register_constraint "j" "SIB_REGS"
+   "A register suitable for an indirect sibcall.")
+ 
+diff --git a/src/gcc/config/nios2/nios2.h b/src/gcc/config/nios2/nios2.h
+index 510ab5f..ac33978 100644
+--- a/src/gcc/config/nios2/nios2.h
++++ b/src/gcc/config/nios2/nios2.h
+@@ -173,6 +173,7 @@ enum reg_class
+ {
+   NO_REGS,
+   SIB_REGS,
++  IJMP_REGS,
+   GP_REGS,
+   ALL_REGS,
+   LIM_REG_CLASSES
+@@ -183,6 +184,7 @@ enum reg_class
+ #define REG_CLASS_NAMES   \
+   {  "NO_REGS",		  \
+      "SIB_REGS",	  \
++     "IJMP_REGS",	  \
+      "GP_REGS",           \
+      "ALL_REGS" }
+ 
+@@ -190,10 +192,11 @@ enum reg_class
+ 
+ #define REG_CLASS_CONTENTS			\
+   {						\
+-    /* NO_REGS  */ { 0, 0},			\
+-    /* SIB_REGS */ { 0xfe0c, 0},		\
+-    /* GP_REGS  */ {~0, 0},			\
+-    /* ALL_REGS */ {~0,~0}			\
++    /* NO_REGS    */ { 0, 0},			\
++    /* SIB_REGS   */ { 0xfe0c, 0},		\
++    /* IJMP_REGS  */ { 0x7fffffff, 0},		\
++    /* GP_REGS    */ {~0, 0},			\
++    /* ALL_REGS   */ {~0,~0}			\
+   }
+ 
+ 
+diff --git a/src/gcc/config/nios2/nios2.md b/src/gcc/config/nios2/nios2.md
+index 7b35d269..36ef101 100644
+--- a/src/gcc/config/nios2/nios2.md
++++ b/src/gcc/config/nios2/nios2.md
+@@ -697,7 +697,7 @@
+ ; check or adjust for overflow.
+ 
+ (define_insn "indirect_jump"
+-  [(set (pc) (match_operand:SI 0 "register_operand" "r"))]
++  [(set (pc) (match_operand:SI 0 "register_operand" "c"))]
+   ""
+   "jmp\\t%0"
+   [(set_attr "type" "control")])
+@@ -811,7 +811,7 @@
+ 
+ (define_insn "*tablejump"
+   [(set (pc)
+-        (match_operand:SI 0 "register_operand" "r"))
++        (match_operand:SI 0 "register_operand" "c"))
+    (use (label_ref (match_operand 1 "" "")))]
+   ""
+   "jmp\\t%0"
+-- 
+2.6.4
+
--- a/debian/rules.patch
+++ b/debian/rules.patch
@@ -246,6 +246,10 @@
   endif
 endif
 
+ifeq ($(DEB_TARGET_ARCH),nios2)
+  debian_patches += ijmp_regs
+endif
+
 ifeq ($(DEB_TARGET_ARCH),powerpcspe)
   debian_patches += powerpc_remove_many
   debian_patches += powerpc_nofprs
EOF
	fi
	patch_gcc_nonglibc
	patch_gcc_multilib_deps
	patch_gcc_powerpcel
	if test "$ENABLE_MULTIARCH_GCC" = yes -a "$ENABLE_MULTILIB" = yes; then
		echo "patching gcc to fix wrong shlibdeps"
		drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/binary-gcc.mk
+++ b/debian/rules.d/binary-gcc.mk
@@ -182,7 +182,7 @@
 	debian/dh_rmemptydirs -p$(p_gcc)
 	dh_strip -p$(p_gcc) \
 	  # save some disk space $(if $(unstripped_exe),-X/lto1)
-	dh_shlibdeps -p$(p_gcc)
+	dh_shlibdeps -p$(p_gcc) $(if $(filter $(DEB_HOST_ARCH),$(DEB_TARGET_ARCH)),,-l`realpath --relative-to . /lib/$(DEB_HOST_MULTIARCH)`)
 	echo $(p_gcc) >> debian/arch_binaries

 	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
EOF
	fi
	patch_gcc_tilegx_multiarch
	echo "enable building gcc libraries. not a bug"
	sed -i -e '/^#with_common_/s/#//' debian/rules.defs
	patch_gcc_wdotap
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
 	$(if $(2),
 	  ln -sf libobjc.symbols debian/$(p_l).symbols ,
 	  fgrep -v libobjc.symbols.gc debian/libobjc.symbols > debian/$(p_l).symbols
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
	if test "$ENABLE_MULTIARCH_GCC" != yes; then
		echo "fixing gcc rtlibs to build the non-cross base"
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
	fi
	patch_gcc_rtlibs_base_dep
	patch_gcc_rtlibs_libatomic
	patch_gcc_include_multiarch
	patch_gcc_powerpcel
	patch_gcc_nonglibc
	patch_gcc_multilib_deps
	patch_gcc_wdotap
}
patch_gcc_7() {
	echo "fixing cross-install-location.diff #855565"
	drop_privs patch -p1 <<'EOF'
--- a/debian/patches/cross-install-location.diff
+++ b/debian/patches/cross-install-location.diff
@@ -61,7 +61,7 @@
 @@ -255,7 +255,7 @@ with_libiberty = @with_libiberty@
  ACLOCAL_AMFLAGS = -I .. -I ../config
  AUTOMAKE_OPTIONS = no-dependencies
- gcc_version := $(shell cat $(top_srcdir)/../gcc/BASE-VER)
+ gcc_version := $(shell @get_gcc_base_ver@ $(top_srcdir)/../gcc/BASE-VER)
 -libexecsubdir := $(libexecdir)/gcc/$(real_target_noncanonical)/$(gcc_version)$(accel_dir_suffix)
 +libexecsubdir := $(libexecdir)/gcc-cross/$(real_target_noncanonical)/$(gcc_version)$(accel_dir_suffix)
  AM_CPPFLAGS = -I$(top_srcdir)/../include $(DEFS)
@@ -167,9 +167,9 @@
 -  -DSTANDARD_LIBEXEC_PREFIX=\"$(libexecdir)/gcc/\" \
 +  -DSTANDARD_EXEC_PREFIX=\"$(libdir)/gcc-cross/\" \
 +  -DSTANDARD_LIBEXEC_PREFIX=\"$(libexecdir)/gcc-cross/\" \
-   -DDEFAULT_TARGET_VERSION=\"$(BASEVER_c)\" \
-   -DDEFAULT_TARGET_FULL_VERSION=\"$(FULLVER_c)\" \
+   -DDEFAULT_TARGET_VERSION=\"$(version)\" \
    -DDEFAULT_REAL_TARGET_MACHINE=\"$(real_target_noncanonical)\" \
+   -DDEFAULT_TARGET_MACHINE=\"$(target_noncanonical)\" \
 @@ -2671,7 +2671,7 @@ PREPROCESSOR_DEFINES = \
    -DTOOL_INCLUDE_DIR=\"$(gcc_tooldir)/include\" \
    -DNATIVE_SYSTEM_HEADER_DIR=\"$(NATIVE_SYSTEM_HEADER_DIR)\" \
@@ -251,7 +251,7 @@
 @@ -68,7 +68,7 @@ GCC_DIR=$(MULTIBUILDTOP)../../$(host_sub
  
  target_noncanonical:=@target_noncanonical@
- version := $(shell cat $(srcdir)/../gcc/BASE-VER)
+ version := $(shell @get_gcc_base_ver@ $(srcdir)/../gcc/BASE-VER)
 -libsubdir := $(libdir)/gcc/$(target_noncanonical)/$(version)$(MULTISUBDIR)
 +libsubdir := $(libdir)/gcc-cross/$(target_noncanonical)/$(version)$(MULTISUBDIR)
  ADA_RTS_DIR=$(GCC_DIR)/ada/rts$(subst /,_,$(MULTISUBDIR))
@@ -265,9 +265,9 @@
  search_path = $(addprefix $(top_srcdir)/config/, $(config_path)) $(top_srcdir) \
  	      $(top_srcdir)/../include
  
--fincludedir = $(libdir)/gcc/$(target_alias)/$(gcc_version)/finclude
+-fincludedir = $(libdir)/gcc/$(target_alias)/$(gcc_version)$(MULTISUBDIR)/finclude
 -libsubincludedir = $(libdir)/gcc/$(target_alias)/$(gcc_version)/include
-+fincludedir = $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)/finclude
++fincludedir = $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)$(MULTISUBDIR)/finclude
 +libsubincludedir = $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)/include
  AM_CPPFLAGS = $(addprefix -I, $(search_path))
  AM_CFLAGS = $(XCFLAGS)
@@ -280,9 +280,9 @@
  search_path = $(addprefix $(top_srcdir)/config/, $(config_path)) $(top_srcdir) \
  	      $(top_srcdir)/../include
  
--fincludedir = $(libdir)/gcc/$(target_alias)/$(gcc_version)/finclude
+-fincludedir = $(libdir)/gcc/$(target_alias)/$(gcc_version)$(MULTISUBDIR)/finclude
 -libsubincludedir = $(libdir)/gcc/$(target_alias)/$(gcc_version)/include
-+fincludedir = $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)/finclude
++fincludedir = $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)$(MULTISUBDIR)/finclude
 +libsubincludedir = $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)/include
  
  vpath % $(strip $(search_path))
@@ -307,7 +307,7 @@
 @@ -8,6 +8,6 @@ EXTRA_DIST=ffi.h.in
  
  # Where generated headers like ffitarget.h get installed.
- gcc_version   := $(shell cat $(top_srcdir)/../gcc/BASE-VER)
+ gcc_version   := $(shell @get_gcc_base_ver@ $(top_srcdir)/../gcc/BASE-VER)
 -toollibffidir := $(libdir)/gcc/$(target_alias)/$(gcc_version)/include
 +toollibffidir := $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)/include
  
@@ -319,7 +319,7 @@
 @@ -251,7 +251,7 @@ EXTRA_DIST = ffi.h.in
  
  # Where generated headers like ffitarget.h get installed.
- gcc_version := $(shell cat $(top_srcdir)/../gcc/BASE-VER)
+ gcc_version := $(shell @get_gcc_base_ver@ $(top_srcdir)/../gcc/BASE-VER)
 -toollibffidir := $(libdir)/gcc/$(target_alias)/$(gcc_version)/include
 +toollibffidir := $(libdir)/gcc-cross/$(target_alias)/$(gcc_version)/include
  toollibffi_HEADERS = ffi.h ffitarget.h
EOF
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
 	$(if $(2),
 	  ln -sf libobjc.symbols debian/$(p_l).symbols ,
 	  fgrep -v libobjc.symbols.gc debian/libobjc.symbols > debian/$(p_l).symbols
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
	patch_gcc_nobrig
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
	drop_privs gcc_cv_libc_provides_ssp=yes DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,fortran,$GCC_NOLANG" dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	if test "$GCC_VER" = 5; then
		drop_privs changestool ./*.changes dumbremove libasan*.deb libmpx*.deb lib*"-${GCC_VER}-"*.deb
		drop_privs rm -fv libasan*.deb libmpx*.deb lib*"-${GCC_VER}-"*.deb
	fi
	sed -i -e '/^ .* .* .*_.*_.*\.buildinfo/d' ./*.changes # work around #843402
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
   arm*-*-eabi* )
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
	echo "patching binutils to benefit from the new cross method"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -816,7 +816,11 @@
   ifneq (,$(findstring static-cross,$(DEB_BUILD_OPTIONS)))
        build_stamps = stamps/build-static-cross
   else
-       build_stamps = stamps/build-cross
+       ifeq ($(TARGET),hppa64-linux-gnu)
+         build_stamps = stamps/build-hppa64
+       else
+         build_stamps = stamps/build.$(DEB_TARGET_ARCH)
+       endif
   endif
 endif
 ifeq ($(BACKPORT),true)
@@ -848,7 +848,11 @@
   ifneq (,$(findstring static-cross,$(DEB_BUILD_OPTIONS)))
         install_stamps = stamps/install-static-cross
   else
-        install_stamp = stamps/install-cross
+        ifeq ($(TARGET),hppa64-linux-gnu)
+          install_stamp = stamps/install-hppa64
+        else
+          install_stamp = stamps/install.$(DEB_TARGET_ARCH)
+        endif
   endif
 else
         install_stamp = stamps/install
EOF
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
}
if test -f "$REPODIR/stamps/cross-binutils"; then
	echo "skipping rebuild of binutils-target"
else
	cross_build_setup binutils
	check_binNMU
	apt_get_build_dep ./
	drop_privs TARGET=$HOST_ARCH dpkg-buildpackage --target=stamps/control
	drop_privs TARGET=$HOST_ARCH dpkg-buildpackage -B -uc -us
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
	apt_get_build_dep ./
	drop_privs TARGET=hppa64-linux-gnu dpkg-buildpackage --target=stamps/control
	drop_privs TARGET=hppa64-linux-gnu dpkg-buildpackage -B -uc -us
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
		arm|nios2)
			kernel_arch=$HOST_ARCH
		;;
		mipsr6|mipsr6el|mipsn32r6|mipsn32r6el|mips64r6|mips64r6el)
			kernel_arch=defines-only
		;;
		powerpcel) kernel_arch=powerpc; ;;
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
		# also built with the cross compiler
		reprepro -A "$(dpkg --print-architecture)" remove rebootstrap-native "gcc-${GCC_VER}-base"
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
	if test "$ENABLE_MULTIARCH_GCC"; then
		# also built with the cross compiler
		reprepro -A "$(dpkg --print-architecture)" remove rebootstrap-native "gcc-${GCC_VER}-base"
	fi
	pickup_packages *.changes
	# avoid file conflicts between differently staged M-A:same packages
	apt_get_remove "gcc-$GCC_VER-base:$HOST_ARCH"
	drop_privs rm -fv gcc-*-plugin-*.deb gcj-*.deb gdc-*.deb ./*objc*.deb ./*-dbg_*.deb
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		dpkg -i "gcc-${GCC_VER}-base_"*"_$(dpkg --print-architecture).deb"
	fi
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

if test "$ENABLE_MULTIARCH_GCC" != yes && dpkg --compare-versions "$GCC_VER" ge 5; then
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

add_automatic apt

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

patch_audit() {
	echo "adding nopython profile to audit #840262"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -4,7 +4,7 @@
 Build-Depends: debhelper (>= 9),
                dh-autoreconf,
                dh-systemd (>= 1.4),
-               dh-python,
+               dh-python <!nopython>,
 #               dh-golang,
                dpkg-dev (>= 1.16.1~),
                intltool,
@@ -15,8 +15,8 @@
                libldap2-dev,
                libprelude-dev,
                libwrap0-dev,
-               python-all-dev (>= 2.6.6-3~),
-               python3-all-dev,
+               python-all-dev (>= 2.6.6-3~) <!nopython>,
+               python3-all-dev <!nopython>,
                swig
 Build-Depends-Indep: golang-go
 Standards-Version: 3.9.8
@@ -109,6 +109,7 @@
 Architecture: linux-any
 Depends: ${misc:Depends}, ${python:Depends}, ${shlibs:Depends}
 Provides: ${python:Provides}
+Build-Profiles: <!nopython>
 Description: Python bindings for security auditing
  The package contains the Python bindings for libaudit and libauparse, which
  are used to monitor systems for security related events. Python can be used to
@@ -119,6 +120,7 @@
 Architecture: linux-any
 Depends: ${misc:Depends}, ${python3:Depends}, ${shlibs:Depends}
 Provides: ${python3:Provides}
+Build-Profiles: <!nopython>
 Description: Python3 bindings for security auditing
  The package contains the Python3 bindings for libaudit and libauparse, which
  are used to monitor systems for security related events. Python can be used to
--- a/debian/rules
+++ b/debian/rules
@@ -1,14 +1,15 @@
 #!/usr/bin/make -f
-include /usr/share/python/python.mk
 export DEB_BUILD_MAINT_OPTIONS = hardening=+all
 DPKG_EXPORT_BUILDFLAGS = 1
 include /usr/share/dpkg/buildflags.mk
-
-DEB_HOST_MULTIARCH ?= $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)
-DEB_HOST_ARCH := $(shell dpkg-architecture -qDEB_HOST_ARCH)
+include /usr/share/dpkg/architecture.mk
 
 LDFLAGS += -Wl,--as-needed
+DH_ADDONS = --with autoreconf --with systemd
+CONFIGURE_FLAGS =
 
+ifeq ($(filter nopython,$(DEB_BUILD_PROFILES)),)
+include /usr/share/python/python.mk
 # For building bindings/swig/ and bindings/python/ for all Python version, these directories are cloned and build in addition to the main library
 PYDEFAULTVER := $(shell pyversions --default --version)                                                                                        
 PYVERS := $(shell pyversions --requested --version debian/control)                                                                             
@@ -16,6 +17,11 @@
 PY3DEFAULTVER := $(shell py3versions --default --version)
 PY3VERS := $(shell py3versions --requested --version debian/control)
 PY3VERS := $(filter-out $(PY3DEFAULTVER), $(PY3VERS))
+CONFIGURE_FLAGS += --with-python --with-python3
+DH_ADDONS += --with python2 --with python3
+else
+CONFIGURE_FLAGS += --without-python --without-python3
+endif
 
 ifeq ($(DEB_HOST_ARCH),alpha)
   EXTRA_ARCH_TABLE := --with-alpha
@@ -25,7 +31,7 @@
 endif
 
 %:
-	dh $@ --builddirectory=debian/build --buildsystem=autoconf --with autoreconf --with python2 --with python3 --with systemd #--with golang
+	dh $@ --builddirectory=debian/build --buildsystem=autoconf $(DH_ADDONS)
 
 override_dh_auto_configure: debian/config-python-stamp $(PYVERS:%=debian/config-python%-stamp) $(PY3VERS:%=debian/config-python3-%-stamp)
 debian/config-python-stamp:
@@ -41,8 +47,7 @@
 		--with-prelude \
 		--with-libwrap \
 		--with-libcap-ng \
-		--with-python \
-		--with-python3 \
+		$(CONFIGURE_FLAGS) \
 		--with-arm --with-aarch64 ${EXTRA_ARCH_TABLE}
 	touch $@
 debian/config-python%-stamp: debian/config-python-stamp
EOF
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

add_automatic dash
add_automatic datefudge
add_automatic db-defaults
add_automatic debianutils
add_automatic diffutils
add_automatic dpkg

builddep_elfutils() {
	assert_built "bzip2 xz-utils zlib"
	# gcc-multilib dependency lacks nocheck profile
	apt_get_install debhelper autotools-dev autoconf automake bzip2 "zlib1g-dev:$1" zlib1g-dev "libbz2-dev:$1" "liblzma-dev:$1" m4 gettext gawk dpkg-dev flex libfl-dev bison
}

patch_expat() {
	echo "patching expat to add nobiarch build profile #779459"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -5,7 +5,7 @@
 Standards-Version: 3.9.5
 Build-Depends: debhelper (>= 9), docbook-to-man, dh-autoreconf,
  dpkg-dev (>= 1.16.0),
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
}

add_automatic file
add_automatic findutils

add_automatic fontconfig
builddep_fontconfig() {
	# help apt with finding a solution
	apt_get_remove "libfreetype6-dev:$(dpkg --print-architecture)"
	apt_get_build_dep "-a$1" ./
}

add_automatic freebsd-glue
add_automatic freetype
add_automatic fuse
add_automatic gdbm

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
		amd64|arm|arm64|hppa|i386|m68k|mips|s390x|sh4)
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
	echo "Patching jemalloc nios2 support #816236"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -10,7 +10,7 @@
   DEB_CPPFLAGS_MAINT_APPEND += -DLG_QUANTUM=4
 endif
 
-ifneq (,$(findstring $(DEB_HOST_ARCH),m68k or1k))
+ifneq (,$(findstring $(DEB_HOST_ARCH),m68k nios2 or1k))
   DEB_CPPFLAGS_MAINT_APPEND += -DLG_QUANTUM=3
 endif
 
EOF
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
patch_libbsd() {
	if test "$HOST_ARCH" = tilegx; then
		echo "adding tilegx support to libbsd #847560"
		drop_privs patch -p1 <<'EOF'
--- a/src/local-elf.h
+++ b/src/local-elf.h
@@ -185,6 +185,12 @@
 #endif
 #define ELF_TARG_DATA	ELFDATA2MSB

+#elif defined(__tilegx__)
+
+#define ELF_TARG_MACH	EM_TILEGX
+#define ELF_TARG_CLASS	ELFCLASS64
+#define ELF_TARG_DATA	ELFDATA2LSB
+
 #elif defined(__or1k__)

 #define ELF_TARG_MACH	EM_OPENRISC
EOF
	fi
}

patch_libcap_ng() {
	echo "patching libcap-ng for nopython profile #831362"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -3,13 +3,13 @@
 Maintainer: Pierre Chifflier <pollux@debian.org>
 Build-Depends: debhelper (>= 9),
     dh-autoreconf,
-    dh-python,
+    dh-python <!nopython>,
     autotools-dev,
     libattr1-dev,
     linux-kernel-headers,
-    swig,
-    python-all-dev,
-    python3-dev
+    swig <!nopython>,
+    python-all-dev <!nopython>,
+    python3-dev <!nopython>
 Standards-Version: 3.9.8
 Section: libs
 X-Python-Version: >= 2.6
@@ -65,6 +65,7 @@
 Section: python
 Architecture: any
 Depends: ${shlibs:Depends}, ${misc:Depends}, ${python:Depends}
+Build-Profiles: <!nopython>
 Description: Python bindings for libcap-ng
  This library implements the user-space interfaces to the POSIX
  1003.1e capabilities available in Linux kernels.  These capabilities are
@@ -81,6 +82,7 @@
 Architecture: any
 Depends: ${shlibs:Depends}, ${misc:Depends}, ${python3:Depends}
 Provides: ${python3:Provides}
+Build-Profiles: <!nopython>
 Description: Python3 bindings for libcap-ng
  This library implements the user-space interfaces to the POSIX
  1003.1e capabilities available in Linux kernels.  These capabilities are
--- a/debian/rules
+++ b/debian/rules
@@ -8,6 +8,11 @@
 
 export DEB_BUILD_HARDENING=1
 
+ifneq ($(filter nopython,$(DEB_BUILD_PROFILES)),)
+override_dh_auto_configure:
+	dh_auto_configure -- --without-python --without-python3
+endif
+
 override_dh_install:
 	mkdir -p $(CURDIR)/debian/tmp/lib/$(DEB_HOST_MULTIARCH) && \
 	mv $(CURDIR)/debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/lib*.so.0* $(CURDIR)/debian/tmp/lib/$(DEB_HOST_MULTIARCH)/; \
@@ -24,5 +29,8 @@
 	:
 
 %:
+ifeq ($(filter nopython,$(DEB_BUILD_PROFILES)),)
 	dh $@ --with=python2,python3,autoreconf
-
+else
+	dh $@ --with=autoreconf
+endif
EOF
}

add_automatic libcap2
add_automatic libdebian-installer
add_automatic libev
add_automatic libevent
add_automatic libffi

add_automatic libgc
builddep_libgc() {
	if test "$HOST_ARCH" = tilegx; then
		echo "adding tilegx support to pkg-kde-tools #854493"
		apt_get_install --reinstall pkg-kde-tools
		patch /usr/share/perl5/Debian/PkgKde/SymbolsHelper/Substs/TypeSubst.pm <<'EOF'
--- a/perllib/Debian/PkgKde/SymbolsHelper/Substs/TypeSubst.pm
+++ b/perllib/Debian/PkgKde/SymbolsHelper/Substs/TypeSubst.pm
@@ -150,6 +150,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -161,7 +162,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'm' : 'j';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'm' : 'j';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::ssize_t;
@@ -169,6 +171,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -180,7 +183,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'l' : 'i';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'l' : 'i';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::int64_t;
@@ -188,6 +192,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -199,7 +204,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'l' : 'x';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'l' : 'x';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::uint64_t;
@@ -207,6 +213,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -218,7 +225,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'm' : 'y';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'm' : 'y';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::qptrdiff;
@@ -226,6 +234,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -237,7 +246,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'x' : 'i';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'x' : 'i';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::quintptr;
@@ -245,6 +255,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -256,7 +267,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'y' : 'j';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'y' : 'j';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::intptr_t;
@@ -264,6 +276,7 @@
 use strict;
 use warnings;
 use base 'Debian::PkgKde::SymbolsHelper::Substs::TypeSubst';
+use Dpkg::Arch qw(debarch_to_cpuattrs);
 
 sub new {
     my $class = shift;
@@ -275,7 +288,8 @@
 
 sub _expand {
     my ($self, $arch) = @_;
-    return ($arch =~ /^(amd64|kfreebsd-amd64|ia64|alpha|s390x|sparc64|ppc64|ppc64el|mips64|mips64el|arm64)$/) ? 'l' : 'i';
+    my ($bits, $endian) = debarch_to_cpuattrs($arch);
+    return $bits == 64 ? 'l' : 'i';
 }
 
 package Debian::PkgKde::SymbolsHelper::Substs::TypeSubst::qreal;
EOF
	fi
	apt_get_build_dep "-a$1" --arch-only ./
}
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
add_automatic libksba
add_automatic libonig
add_automatic libpipeline
add_automatic libpng1.6

patch_libprelude() {
	echo "adding noperl and nopython profiles to libprelude #838115"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -9,12 +9,12 @@
     quilt,
     libgnutls28-dev,
     libgcrypt20-dev,
-    python-all-dev (>> 2.6.6),
-    libperl-dev,
+    python-all-dev (>> 2.6.6) <!nopython>,
+    libperl-dev <!noperl>,
     libltdl-dev,
     pkg-config,
     gawk,
-    swig
+    swig <!noperl> <!nopython>
 Standards-Version: 3.9.3
 
 Package: libprelude-dev
@@ -74,6 +74,7 @@
 Section: perl
 Architecture: any
 Depends: ${perl:Depends}, libprelude2 (= ${binary:Version}), ${shlibs:Depends}, ${misc:Depends}
+Build-Profiles: <!noperl>
 Description: Security Information Management System [ Base library ]
  Prelude is a Universal "Security Information Management" (SIM) system.
  Its goals are performance and modularity. It is divided in two main
@@ -92,6 +93,7 @@
 Architecture: any
 Depends: ${python:Depends}, libprelude2 (= ${binary:Version}), ${shlibs:Depends}, ${misc:Depends}
 Provides: ${python:Provides}
+Build-Profiles: <!nopython>
 Description: Security Information Management System [ Base library ]
  Prelude is a Universal "Security Information Management" (SIM) system.
  Its goals are performance and modularity. It is divided in two main
diff --minimal -Nru libprelude-1.0.0/debian/rules libprelude-1.0.0/debian/rules
--- a/debian/rules
+++ b/debian/rules
@@ -3,13 +3,26 @@
 
 export DEB_BUILD_MAINT_OPTIONS=hardening=+all,-pie
 
+DH_ADDONS = --with quilt --with autoreconf
+
+ifeq ($(filter nopython,$(DEB_BUILD_PROFILES)),)
 PYVERS=$(shell pyversions -vr)
+DH_ADDONS += --with python2
+else
+CONFIGURE_FLAGS += --without-python
+endif
+
+ifeq ($(filter noperl,$(DEB_BUILD_PROFILES)),)
+CONFIGURE_FLAGS += --with-perl-installdirs=vendor
+else
+CONFIGURE_FLAGS += --without-perl
+endif
 
 override_dh_auto_configure:
 	# backup files to be regenerated
 	mkdir debian/temp.backup; \
 	cp -a bindings/python/PreludeEasy.py bindings/python/_PreludeEasy.cxx debian/temp.backup/
-	dh_auto_configure -- --with-perl-installdirs=vendor
+	dh_auto_configure -- $(CONFIGURE_FLAGS)
 
 override_dh_auto_build: build-core $(PYVERS:%=build-python%)
 
@@ -32,10 +45,12 @@
 	echo "OK"
 
 override_dh_auto_install:
-	dh_auto_install; \
-	rm -rf debian/tmp/usr/lib/python*; \
-	find debian/tmp-python-libprelude/usr/lib -name "*.la" -delete; \
+	dh_auto_install
+	rm -rf debian/tmp/usr/lib/python*
+ifeq ($(filter nopython,$(DEB_BUILD_PROFILES)),)
+	find debian/tmp-python-libprelude/usr/lib -name "*.la" -delete
 	mv debian/tmp-python-libprelude/usr/lib/* debian/tmp/usr/lib/
+endif
 
 override_dh_strip:
 	dh_strip --dbg-package=libprelude2-dbg
@@ -51,4 +66,4 @@
 	[ ! -d debian/temp.backup ] || rm -rf debian/temp.backup
 
 %:
-	dh $@ --with=quilt,python2,autoreconf
+	dh $@ $(DH_ADDONS)
EOF
}
buildenv_libprelude() {
	case $(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_SYSTEM) in *gnu*)
		echo "glibc does not return NULL for malloc(0)"
		export ac_cv_func_malloc_0_nonnull=yes
	;; esac
}

add_automatic libpthread-stubs
add_automatic libseccomp
add_automatic libsepol
add_automatic libsm
add_automatic libssh2
add_automatic libtasn1-6

add_automatic libtextwrap
patch_libtextwrap() {
	echo "fixing libtextwrap bzip2 compressor ftbfs #833250"
	drop_privs sed -i -e 's/ -Zbzip2 / /' debian/rules
}

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
builddep_libxt() {
	# help apt with finding a solution
	apt_get_remove "libglib2.0-dev:$(dpkg --print-architecture)"
	apt_get_build_dep "-a$1" ./
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
	if ! dpkg-architecture "-a$HOST_ARCH" -ilinux-any; then
		echo "fixing FTCBFS for kfreebsd-any #810579"
		drop_privs quilt pop -a
		drop_privs patch -p1 <<'EOF'
--- a/debian/patches/10_linux.patch
+++ b/debian/patches/10_linux.patch
@@ -0,0 +1,239 @@
+From: Steven Chamberlain <steven@pyro.eu.org>
+Subject: use __linux__ macro instead of other variations
+Date: Tue, 12 Jan 2016 02:12:28 +0000
+
+Use the preferred, POSIX-compliant __linux__ macro instead of obsolete
+__linux, linux and LINUX.  No longer define those via CFLAGS but defer
+to the compiler toolchain to do as necessary.
+
+--- a/nss/coreconf/nsinstall/nsinstall.c
++++ b/nss/coreconf/nsinstall/nsinstall.c
+@@ -26,7 +26,7 @@
+ 
+ #define HAVE_LCHOWN
+ 
+-#if defined(AIX) || defined(BSDI) || defined(HPUX) || defined(LINUX) || defined(SUNOS4) || defined(SCO) || defined(UNIXWARE) || defined(NTO) || defined(DARWIN) || defined(BEOS) || defined(__riscos__)
++#if defined(AIX) || defined(BSDI) || defined(HPUX) || defined(__linux__) || defined(SUNOS4) || defined(SCO) || defined(UNIXWARE) || defined(NTO) || defined(DARWIN) || defined(BEOS) || defined(__riscos__)
+ #undef HAVE_LCHOWN
+ #endif
+ 
+@@ -36,7 +36,7 @@
+ #undef HAVE_FCHMOD
+ #endif
+ 
+-#ifdef LINUX
++#ifdef __linux__
+ #include <getopt.h>
+ #endif
+ 
+--- a/nss/lib/dbm/include/mcom_db.h
++++ b/nss/lib/dbm/include/mcom_db.h
+@@ -60,14 +60,14 @@
+ #include <sys/byteorder.h>
+ #endif
+ 
+-#if defined(__linux) || defined(__BEOS__)
++#if defined(__linux__) || defined(__BEOS__)
+ #include <endian.h>
+ #ifndef BYTE_ORDER
+ #define BYTE_ORDER __BYTE_ORDER
+ #define BIG_ENDIAN __BIG_ENDIAN
+ #define LITTLE_ENDIAN __LITTLE_ENDIAN
+ #endif
+-#endif /* __linux */
++#endif /* __linux__ */
+ 
+ #ifdef __sgi
+ #define BYTE_ORDER BIG_ENDIAN
+--- a/nss/lib/freebl/nsslowhash.c
++++ b/nss/lib/freebl/nsslowhash.c
+@@ -257,7 +257,7 @@
+ };
+ 
+ static int nsslow_GetFIPSEnabled(void) {
+-#ifdef LINUX
++#ifdef __linux__
+     FILE *f;
+     char d;
+     size_t size;
+--- a/nss/lib/freebl/unix_rand.c
++++ b/nss/lib/freebl/unix_rand.c
+@@ -346,7 +346,7 @@
+ }
+ #endif /* IBM R2 */
+ 
+-#if defined(LINUX)
++#if defined(__linux__)
+ #include <sys/sysinfo.h>
+ 
+ static size_t
+@@ -365,7 +365,7 @@
+     }
+ #endif
+ }
+-#endif /* LINUX */
++#endif /* __linux__ */
+ 
+ #if defined(NCR)
+ 
+@@ -914,7 +914,7 @@
+  */
+ 
+ #if defined(BSDI) || defined(FREEBSD) || defined(NETBSD) \
+-    || defined(OPENBSD) || defined(DARWIN) || defined(LINUX) \
++    || defined(OPENBSD) || defined(DARWIN) || defined(__linux__) \
+     || defined(HPUX)
+     if (bytes)
+         return;
+--- a/nss/lib/softoken/fipstokn.c
++++ b/nss/lib/softoken/fipstokn.c
+@@ -33,7 +33,7 @@
+ #include <unistd.h>
+ #endif
+ 
+-#ifdef LINUX
++#ifdef __linux__
+ #include <pthread.h>
+ #include <dlfcn.h>
+ #define LIBAUDIT_NAME "libaudit.so.0"
+@@ -85,7 +85,7 @@
+ 	audit_send_user_message_func = NULL;
+     }
+ }
+-#endif /* LINUX */
++#endif /* __linux__ */
+ 
+ 
+ /*
+@@ -289,7 +289,7 @@
+     return rv;
+ }
+ 
+-#ifdef LINUX
++#ifdef __linux__
+ 
+ int
+ sftk_mapLinuxAuditType(NSSAuditSeverity severity, NSSAuditType auditType)
+@@ -374,7 +374,7 @@
+     syslog(level | LOG_USER /* facility */,
+ 	   "NSS " SOFTOKEN_LIB_NAME "[pid=%d uid=%d]: %s",
+ 	   (int)getpid(), (int)getuid(), msg);
+-#ifdef LINUX
++#ifdef __linux__
+     if (pthread_once(&libaudit_once_control, libaudit_init) != 0) {
+ 	return;
+     }
+@@ -401,7 +401,7 @@
+ 	audit_close_func(audit_fd);
+ 	PR_smprintf_free(message);
+     }
+-#endif /* LINUX */
++#endif /* __linux__ */
+ #else
+     /* do nothing */
+ #endif
+--- a/nss/lib/softoken/softoken.h
++++ b/nss/lib/softoken/softoken.h
+@@ -184,7 +184,7 @@
+ 
+ #define CHECK_FORK_MIXED
+ 
+-#elif defined(LINUX)
++#elif defined(__linux__)
+ 
+ #define CHECK_FORK_PTHREAD
+ 
+--- a/nss/lib/ssl/sslmutex.c
++++ b/nss/lib/ssl/sslmutex.c
+@@ -56,7 +56,7 @@
+     return SECSuccess;
+ }
+ 
+-#if defined(LINUX) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
++#if defined(__linux__) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
+ 
+ #include <unistd.h>
+ #include <fcntl.h>
+@@ -119,7 +119,7 @@
+ 
+     pMutex->u.pipeStr.mPipes[2] = SSL_MUTEX_MAGIC;
+ 
+-#if defined(LINUX) && defined(i386)
++#if defined(__linux__) && defined(i386)
+     /* Pipe starts out empty */
+     return SECSuccess;
+ #else
+@@ -159,7 +159,7 @@
+     return SECSuccess;
+ }
+ 
+-#if defined(LINUX) && defined(i386)
++#if defined(__linux__) && defined(i386)
+ /* No memory barrier needed for this platform */
+ 
+ /* nWaiters includes the holder of the lock (if any) and the number
+--- a/nss/lib/ssl/sslmutex.h
++++ b/nss/lib/ssl/sslmutex.h
+@@ -50,7 +50,7 @@
+ 
+ typedef int    sslPID;
+ 
+-#elif defined(LINUX) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
++#elif defined(__linux__) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
+ 
+ #include <sys/types.h>
+ #include "prtypes.h"
+--- a/nss/lib/ssl/sslsnce.c
++++ b/nss/lib/ssl/sslsnce.c
+@@ -255,7 +255,7 @@
+ #define MAX_SSL3_TIMEOUT 86400L /* 24 hours */
+ #define MIN_SSL3_TIMEOUT 5      /* seconds  */
+ 
+-#if defined(AIX) || defined(LINUX) || defined(NETBSD) || defined(OPENBSD)
++#if defined(AIX) || defined(__linux__) || defined(NETBSD) || defined(OPENBSD)
+ #define MAX_SID_CACHE_LOCKS 8 /* two FDs per lock */
+ #elif defined(OSF1)
+ #define MAX_SID_CACHE_LOCKS 16 /* one FD per lock */
+--- a/nss/coreconf/Linux.mk
++++ b/nss/coreconf/Linux.mk
+@@ -140,7 +140,7 @@
+ OS_PTHREAD = -lpthread 
+ endif
+ 
+-OS_CFLAGS		= $(DSO_CFLAGS) $(OS_REL_CFLAGS) $(ARCHFLAG) -pipe -ffunction-sections -fdata-sections -DLINUX -Dlinux -DHAVE_STRERROR
++OS_CFLAGS		= $(DSO_CFLAGS) $(OS_REL_CFLAGS) $(ARCHFLAG) -pipe -ffunction-sections -fdata-sections -DHAVE_STRERROR
+ OS_LIBS			= $(OS_PTHREAD) -ldl -lc
+ 
+ ifdef USE_PTHREADS
+--- a/nss/coreconf/mkdepend/imakemdep.h
++++ b/nss/coreconf/mkdepend/imakemdep.h
+@@ -461,9 +461,8 @@
+ #ifdef NCR
+ 	"-DNCR",	/* NCR */
+ #endif
+-#ifdef linux
++#ifdef __linux__
+         "-traditional",
+-        "-Dlinux",
+ #endif
+ #ifdef __uxp__
+ 	"-D__uxp__",
+--- a/nss/lib/freebl/mpi/target.mk
++++ b/nss/lib/freebl/mpi/target.mk
+@@ -173,13 +173,13 @@
+ MPICMN += -DMP_ASSEMBLY_MULTIPLY -DMP_ASSEMBLY_SQUARE -DMP_ASSEMBLY_DIV_2DX1D
+ MPICMN += -DMP_MONT_USE_MP_MUL -DMP_CHAR_STORE_SLOW -DMP_IS_LITTLE_ENDIAN
+ CFLAGS= -O2 -fPIC -DLINUX1_2 -Di386 -D_XOPEN_SOURCE -DLINUX2_1 -ansi -Wall \
+- -pipe -DLINUX -Dlinux -D_POSIX_SOURCE -D_BSD_SOURCE -DHAVE_STRERROR \
++ -pipe -D_POSIX_SOURCE -D_BSD_SOURCE -DHAVE_STRERROR \
+  -DXP_UNIX -UDEBUG -DNDEBUG -D_REENTRANT $(MPICMN)
+ #CFLAGS= -g -fPIC -DLINUX1_2 -Di386 -D_XOPEN_SOURCE -DLINUX2_1 -ansi -Wall \
+- -pipe -DLINUX -Dlinux -D_POSIX_SOURCE -D_BSD_SOURCE -DHAVE_STRERROR \
++ -pipe -D_POSIX_SOURCE -D_BSD_SOURCE -DHAVE_STRERROR \
+  -DXP_UNIX -DDEBUG -UNDEBUG -D_REENTRANT $(MPICMN)
+ #CFLAGS= -g -fPIC -DLINUX1_2 -Di386 -D_XOPEN_SOURCE -DLINUX2_1 -ansi -Wall \
+- -pipe -DLINUX -Dlinux -D_POSIX_SOURCE -D_BSD_SOURCE -DHAVE_STRERROR \
++ -pipe -D_POSIX_SOURCE -D_BSD_SOURCE -DHAVE_STRERROR \
+  -DXP_UNIX -UDEBUG -DNDEBUG -D_REENTRANT $(MPICMN)
+ endif
+ 
--- a/debian/patches/38_kbsd.patch
+++ b/debian/patches/38_kbsd.patch
@@ -26,8 +24,8 @@
  
  #define CHECK_FORK_MIXED
  
--#elif defined(LINUX)
-+#elif defined(LINUX) || defined (__GLIBC__)
+-#elif defined(__linux__)
++#elif defined(__linux__) || defined (__GLIBC__)
  
  #define CHECK_FORK_PTHREAD
  
@@ -38,8 +36,8 @@
      return SECSuccess;
  }
  
--#if defined(LINUX) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
-+#if defined(LINUX) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD) || defined(__GLIBC__)
+-#if defined(__linux__) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
++#if defined(__linux__) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD) || defined(__GLIBC__)
  
  #include <unistd.h>
  #include <fcntl.h>
@@ -51,8 +49,8 @@
  
  typedef int sslPID;
  
--#elif defined(LINUX) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
-+#elif defined(LINUX) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD) || defined(__GLIBC__)
+-#elif defined(__linux__) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD)
++#elif defined(__linux__) || defined(AIX) || defined(BEOS) || defined(BSDI) || (defined(NETBSD) && __NetBSD_Version__ < 500000000) || defined(OPENBSD) || defined(__GLIBC__)
  
  #include <sys/types.h>
  #include "prtypes.h"
@@ -89,18 +77,7 @@
  	OS_REL_CFLAGS	+= -DLINUX2_0
  	MKSHLIB		= $(CC) -shared -Wl,-soname -Wl,$(@:$(OBJDIR)/%.so=%.so) $(RPATH)
  	ifdef MAPFILE
-@@ -139,14 +139,21 @@ ifeq ($(USE_PTHREADS),1)
- OS_PTHREAD = -lpthread 
- endif
- 
--OS_CFLAGS		= $(DSO_CFLAGS) $(OS_REL_CFLAGS) $(ARCHFLAG) -pipe -ffunction-sections -fdata-sections -DLINUX -Dlinux -DHAVE_STRERROR
-+OS_CFLAGS		= $(DSO_CFLAGS) $(OS_REL_CFLAGS) $(ARCHFLAG) -pipe -ffunction-sections -fdata-sections -DHAVE_STRERROR
-+ifeq ($(KERNEL),linux)
-+OS_CFLAGS		+= -DLINUX -Dlinux
-+endif
- OS_LIBS			= $(OS_PTHREAD) -ldl -lc
- 
- ifdef USE_PTHREADS
+@@ -147,7 +147,11 @@
  	DEFINES		+= -D_REENTRANT
  endif
  
--- a/debian/patches/series
+++ b/debian/patches/series
@@ -1,3 +1,4 @@
+10_linux.patch
 38_hurd.patch
 38_kbsd.patch
 80_security_tools.patch
EOF
		drop_privs quilt push -a
	fi
}

add_automatic openssl

add_automatic p11-kit
builddep_p11_kit() {
	# work around m-a:same violation in libffi-dev
	# texinfo stores its own version in the generated info docs
	apt_get_remove "libffi-dev:$(dpkg --print-architecture)"
	$APT_GET build-dep "-a$1" --arch-only p11-kit
}

add_automatic patch
add_automatic pcre3
add_automatic readline5
add_automatic rtmpdump
add_automatic sed
add_automatic slang2
add_automatic spdylay
add_automatic sqlite3

patch_systemd() {
	if test "$HOST_ARCH" = tilegx; then
		echo "adding tilegx support to systemd #856306"
		drop_privs patch -p1 <<'EOF'
--- a/src/basic/architecture.h
+++ b/src/basic/architecture.h
@@ -186,7 +186,7 @@ int uname_architecture(void);
 #  define LIB_ARCH_TUPLE "m68k-linux-gnu"
 #elif defined(__tilegx__)
 #  define native_architecture() ARCHITECTURE_TILEGX
-#  error "Missing LIB_ARCH_TUPLE for TILEGX"
+#  define LIB_ARCH_TUPLE "tilegx-linux-gnu"
 #elif defined(__cris__)
 #  define native_architecture() ARCHITECTURE_CRIS
 #  error "Missing LIB_ARCH_TUPLE for CRIS"
EOF
	fi
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
add_need apt # almost essential
add_need attr # by coreutils, libcap-ng, libcap2
add_need autogen # by gcc-5, gnutls28
add_need bzip2 # by dpkg, perl
add_need cloog # by gcc-4.9
add_need db-defaults # by apt, perl, python2.7
add_need file # by gcc-6, for debhelper
dpkg-architecture "-a$HOST_ARCH" -ikfreebsd-any && add_need freebsd-glue # by freebsd-libs
add_need fuse # by e2fsprogs
add_need gdbm # by perl, python2.7
add_need gnupg2 # for apt
add_need gnutls28 # by curl
test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux && add_need gpm # by ncurses
add_need groff # for man-db
test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux && add_need kmod # by systemd
add_need icu # by libxml2
add_need krb5 # by curl
add_need libatomic-ops # by gcc-4.9
add_need libbsd # by bsdmainutils
dpkg-architecture "-a$HOST_ARCH" -ilinux-any && add_need libcap2 # by systemd
add_need libdebian-installer # by cdebconf
add_need libevent # by unbound
add_need libgcrypt20 # by libprelude, cryptsetup
add_need libpthread-stubs # by libxcb
if apt-cache showsrc systemd | grep -q "^Build-Depends:.*libseccomp-dev[^,]*[[ ]$HOST_ARCH[] ]"; then
	add_need libseccomp # by systemd
fi
dpkg-architecture "-a$HOST_ARCH" -ilinux-any && add_need libsepol # by libselinux
add_need libssh2 # by curl
add_need libtextwrap # by cdebconf
add_need libx11 # by dbus
add_need libxau # by libxcb
add_need libxdmcp # by libxcb
add_need libxrender # by cairo
add_need lz4 # by systemd
add_need make-dfsg # for build-essential
add_need man-db # for debhelper
add_need mawk # for base-files (alternatively: gawk)
add_need mpclib3 # by gcc-4.9
add_need mpfr4 # by gcc-4.9
add_need nettle # by unbound
add_need nghttp2 # by curl
add_need nss # by curl
add_need openssl # by curl
add_need patch # for dpkg-dev
add_need pcre3 # by libselinux
add_need readline5 # by lvm2
add_need rtmpdump # by curl
add_need slang2 # by cdebconf, newt
add_need sqlite3 # by python2.7
add_need tcl8.6 # by newt
add_need tcltk-defaults # by python2.7
dpkg-architecture "-a$HOST_ARCH" -ilinux-any && add_need tcp-wrappers # by audit
add_need tk8.6 # by blt
add_need ustr # by libsemanage
add_need xz-utils # by dpkg, libxml2

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
# needed by dpkg, file, gnutls28, libpng, libtool, libxml2, perl, slang2, tcl8.6, util-linux

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
# needed by guile-2.0

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
# needed by gnupg, guile-2.0, libxml2

automatically_cross_build_packages

if dpkg-architecture "-a$HOST_ARCH" -ilinux-any; then
builddep_libselinux() {
	assert_built "libsepol pcre3"
	# gem2deb dependency lacks profile annotation
	$APT_GET install debhelper file "libsepol1-dev:$1" "libpcre3-dev:$1" pkg-config
}
if test -f "$REPODIR/stamps/libselinux_1"; then
	echo "skipping rebuild of libselinux stage1"
else
	builddep_libselinux "$HOST_ARCH"
	cross_build_setup libselinux libselinux1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us "-a$HOST_ARCH"
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

patch_flex() {
	echo "patching flex to not run tests under DEB_BUILD_OPTIONS=nocheck #812659"
	drop_privs patch -p1 <<'EOF'
--- a/Makefile.am
+++ b/Makefile.am
@@ -53,9 +53,11 @@
	doc \
	examples \
	po \
-	tests \
	tools
 
+check:
+	$(MAKE) -C tests
+
 # Create the ChangeLog, but only if we're inside a git working directory

 ChangeLog: $(srcdir)/tools/git2cl
EOF
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
	if dpkg-architecture "-a$HOST_ARCH" -ihurd-any; then
		echo "fixing flex ftbfs for hurd-any #838133"
		drop_privs patch -p1 <<'EOF'
--- a/src/main.c
+++ b/src/main.c
@@ -358,8 +358,8 @@
 			if (!path) {
 				m4 = M4;
 			} else {
+				int m4_length = strlen(m4);
 				do {
-					char m4_path[PATH_MAX];
 					int length = strlen(path);
 					struct stat sbuf;
 
@@ -367,19 +367,17 @@
 					if (!endOfDir)
 						endOfDir = path+length;
 
-					if ((endOfDir-path+2) >= sizeof(m4_path)) {
-					    path = endOfDir+1;
-						continue;
-					}
+					{
+						char m4_path[endOfDir-path + 1 + m4_length + 1];
 
-					strncpy(m4_path, path, sizeof(m4_path));
-					m4_path[endOfDir-path] = '/';
-					m4_path[endOfDir-path+1] = '\0';
-					strncat(m4_path, m4, sizeof(m4_path));
-					if (stat(m4_path, &sbuf) == 0 &&
-						(S_ISREG(sbuf.st_mode)) && sbuf.st_mode & S_IXUSR) {
-						m4 = strdup(m4_path);
-						break;
+						memcpy(m4_path, path, endOfDir-path);
+						m4_path[endOfDir-path] = '/';
+						memcpy(m4_path + (endOfDir-path) + 1, m4, m4_length + 1);
+						if (stat(m4_path, &sbuf) == 0 &&
+							(S_ISREG(sbuf.st_mode)) && sbuf.st_mode & S_IXUSR) {
+							m4 = strdup(m4_path);
+							break;
+						}
 					}
 					path = endOfDir+1;
 				} while (path[0]);
EOF
	fi
}
cross_build flex
mark_built flex
# needed by pam

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
# needed by perl, python2.7, needed for db-defaults

automatically_cross_build_packages

cross_build expat
mark_built expat
# needed by fontconfig, for freebsd-glue and thus by xz-utils

automatically_cross_build_packages

cross_build elfutils
mark_built elfutils
# needed by glib2.0, systemtap

automatically_cross_build_packages

builddep_glib2_0() {
	dpkg-architecture "-a$1" -ilinux-any && assert_built "libselinux util-linux"
	assert_built "elfutils libffi pcre3 zlib" # also linux-libc-dev
	# python3-dbus dependency unsatisifable
	dpkg-architecture "-a$1" -ilinux-any && apt_get_install "libmount-dev:$1" "libselinux1-dev:$1" "linux-libc-dev:$1"
	apt_get_install debhelper cdbs dh-autoreconf pkg-config gettext autotools-dev gnome-pkg-tools dpkg-dev "libelf-dev:$1" "libpcre3-dev:$1" desktop-file-utils gtk-doc-tools "zlib1g-dev:$1" dbus dbus-x11 shared-mime-info xterm python3 python3-dbus python3-gi libxml2-utils "libffi-dev:$1"
}
buildenv_glib2_0() {
	export glib_cv_stack_grows=no
	export glib_cv_uscore=no
	export ac_cv_func_posix_getgrgid_r=yes
	export ac_cv_func_posix_getpwuid_r=yes
}
cross_build glib2.0
mark_built glib2.0
# needed by pkg-config, dbus, systemd, libxt

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

builddep_libidn() {
	# gcj-jdk dependency lacks build profile annotation
	$APT_GET install debhelper
}
if test -f "$REPODIR/stamps/libidn_1"; then
	echo "skipping rebuild of libidn stage1"
else
	builddep_libidn "$HOST_ARCH"
	cross_build_setup libidn libidn_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libidn_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libidn_1
fi
progress_mark "libidn stage1 cross build"
mark_built libidn
# needed by gnutls28

automatically_cross_build_packages

builddep_libxml2() {
	assert_built "icu xz-utils zlib"
	# python-all-dev dependency lacks profile annotation
	apt_get_install debhelper dh-autoreconf autotools-dev pkg-config "zlib1g-dev:$1" "liblzma-dev:$1" "libicu-dev:$1"
	# autodetects python2.7
	apt_get_remove python2.7
}
patch_libxml2() {
	echo "patching libxml2 to drop python in stage1 #738080"
	drop_privs patch -p1 <<'EOF'
diff -urN libxml2-2.9.1+dfsg1.old/debian/rules libxml2-2.9.1+dfsg1/debian/rules
--- libxml2-2.9.1+dfsg1.old/debian/rules
+++ libxml2-2.9.1+dfsg1/debian/rules
@@ -28,6 +28,7 @@
 ifeq ($(DEB_BUILD_PROFILE),stage1)
 DH_OPTIONS += -Npython-libxml2 -Npython-libxml2-dbg
 export DH_OPTIONS
+TARGETS=main
 endif
 
 CONFIGURE_FLAGS := --disable-silent-rules --with-history CC="$(CC)" CFLAGS="$(CFLAGS)" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)" --cache-file="$(CURDIR)/builddir/config.cache"
EOF
}
if test -f "$REPODIR/stamps/libxml2_1"; then
	echo "skipping rebuild of libxml2 stage1"
else
	builddep_libxml2 "$HOST_ARCH"
	cross_build_setup libxml2 libxml2_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_BUILD_PROFILE=stage1 CC="`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-gcc" dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	touch "$REPODIR/stamps/libxml2_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libxml2_1
fi
progress_mark "libxml2 stage1 cross build"
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

if test -f "$REPODIR/stamps/openldap_1"; then
	echo "skipping stage1 rebuild of openldap"
else
	assert_built "gnutls28 cyrus-sasl2"
	apt_get_remove libgnutls-deb0-28 libgnutls30 # work around multiarch desync #805863
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
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -P nocheck,noudeb,stage1 ./
	check_binNMU
	drop_privs ac_cv_func_malloc_0_nonnull=yes dpkg-buildpackage "-a$HOST_ARCH" -B -uc -us -Pnocheck,noudeb,stage1
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

builddep_curl() {
	assert_built "gnutls28 libidn krb5 openldap nss rtmpdump libssh2 openssl zlib nghttp2"
	# stunnel4 and openssh-server lack <nocheck> profile annotation
	apt_get_install debhelper autoconf automake ca-certificates groff-base "libgnutls28-dev:$1" "libidn11-dev:$1" "libkrb5-dev:$1" "libldap2-dev:$1" "libnss3-dev:$1" "librtmp-dev:$1" "libssh2-1-dev:$1" "libssl-dev:$1" libtool python quilt "zlib1g-dev:$1" "libnghttp2-dev:$1" dh-exec
}
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
cross_build curl
mark_built curl
# needed by apt, gnupg

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
	apt_get_build_dep "-a$HOST_ARCH" --arch-only -Pnoperl,nopython ./
	check_binNMU
	(
		buildenv_libprelude
		drop_privs_exec dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -Pnoperl,nopython
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

builddep_libsemanage() {
	assert_built "audit bzip2 libselinux libsepol ustr"
	# stuff lacks stage1 profile
	apt_get_install bison debhelper file flex "libaudit-dev:$1" "libbz2-dev:$1" "libselinux1-dev:$1" "libsepol1-dev:$1" "libustr-dev:$1" pkg-config
}
if test -f "$REPODIR/stamps/libsemanage_1"; then
	echo "skipping stage1 rebuild of libsemanage"
else
	cross_build_setup libsemanage libsemanage_1
	builddep_libsemanage "$HOST_ARCH"
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_STAGE=stage1 CC="$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE)-gcc" dpkg-buildpackage -d "-a$HOST_ARCH" -B -uc -us
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

assert_built "$need_packages"

echo "checking installability of build-essential with dose"
$APT_GET update
apt_get_install botch
package_list=$(mktemp -t packages.XXXXXXXXXX)
grep-dctrl --exact --field Architecture '(' "$HOST_ARCH" --or all ')' /var/lib/apt/lists/*_Packages > "$package_list"
botch-distcheck-more-problems "--deb-native-arch=$HOST_ARCH" --successes --failures --explain --checkonly "build-essential:$HOST_ARCH" "--bg=deb://$package_list" "--fg=deb://$package_list" || :
rm -f "$package_list"
