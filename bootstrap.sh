#!/bin/sh

set -v
set -e
set -u

export DEB_BUILD_OPTIONS="nocheck parallel=1"
export DH_VERBOSE=1
RESULT="/tmp/result"
HOST_ARCH=undefined
# select gcc version from gcc-defaults package unless set
GCC_VER=
: ${MIRROR:="http://http.debian.net/debian"}
ENABLE_MULTILIB=no
ENABLE_MULTIARCH_GCC=yes
REPODIR=/tmp/repo
APT_GET="apt-get --no-install-recommends -y -o Debug::pkgProblemResolver=true -o Debug::pkgDepCache::Marker=1 -o Debug::pkgDepCache::AutoInstall=1 -o Acquire::Languages=none"
DEFAULT_PROFILES="cross nocheck"
LIBC_NAME=glibc
DROP_PRIVS=buildd
GCC_NOLANG=ada,d,go,java,jit,objc,objc++
ENABLE_DEBBINDIFF=no

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
			if test sh4 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
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

apt_get_remove() {
	local pkg pkgs
	pkgs=""
	for pkg in "$@"; do
		dpkg-query -s "$pkg" >/dev/null 2>&1 && pkgs=`set_add "$pkgs" "$pkg"`
	done
	if test -n "$pkgs"; then
		$APT_GET remove $pkgs
	fi
}

$APT_GET update
$APT_GET install pinentry-curses # avoid installing pinentry-gtk (via reprepro)
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
fi

obtain_source_package() {
	drop_privs apt-get source "$1"
}

if test "$HOST_ARCH" = kfreebsd-armhf; then
	# add kfreebsd-armhf to dpkg #796283
	cat >>/usr/share/dpkg/ostable <<EOF
gnueabihf-kfreebsd	kfreebsd-gnueabihf	kfreebsd[^-]*-gnueabihf
EOF
	cat >>/usr/share/dpkg/triplettable <<EOF
gnueabihf-kfreebsd-arm	kfreebsd-armhf
EOF
fi

if test -z "$HOST_ARCH" || ! dpkg-architecture "-a$HOST_ARCH"; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
fi
export PKG_CONFIG_LIBDIR="/usr/lib/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH`/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
	test -f "$f" && sed -i "s/^deb \(\[.*\] \)*/deb [ arch-=$HOST_ARCH ] /" $f
done
grep -q '^deb-src ' /etc/apt/sources.list || echo "deb-src $MIRROR sid main" >> /etc/apt/sources.list

dpkg --add-architecture $HOST_ARCH
$APT_GET update

if test -z "$GCC_VER"; then
	GCC_VER=`apt-cache depends gcc | sed 's/^ *Depends: gcc-\([0-9.]*\)$/\1/;t;d'`
fi

rmdir /tmp/buildd || :
drop_privs mkdir -p /tmp/buildd
drop_privs mkdir -p "$RESULT"

HOST_ARCH_SUFFIX="-`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE | tr _ -`"

mkdir -p "$REPODIR/conf"
mkdir -p "$REPODIR/archive"
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
EOF
$APT_GET update

# removing libc*-dev conflict with each other
LIBC_DEV_PKG=$(apt-cache showpkg libc-dev | sed '1,/^Reverse Provides:/d;s/ .*//;q')
if test "$(apt-cache show "$LIBC_DEV_PKG" | sed -n 's/^Source: //;T;p;q')" = glibc; then
	cd /tmp/buildd
	apt-get download "$LIBC_DEV_PKG"
	dpkg-deb -R "./$LIBC_DEV_PKG"_*.deb x
	sed -i -e '/^Conflicts: /d' x/DEBIAN/control
	dpkg-deb -b x "./$LIBC_DEV_PKG"_*.deb
	reprepro includedeb rebootstrap-native "./$LIBC_DEV_PKG"_*.deb
	dpkg -i "./$LIBC_DEV_PKG"_*.deb
	$APT_GET update
	rm -R "./$LIBC_DEV_PKG"_*.deb x
fi

chdist_native() {
	local command
	command="$1"
	shift
	chdist --data-dir /tmp/chdist_native --arch "$HOST_ARCH" "$command" native "$@"
}

if test "$ENABLE_DEBBINDIFF" = yes; then
	$APT_GET install devscripts
	chdist_native create "$MIRROR" sid main
	if ! chdist_native apt-get update; then
		echo "rebootstrap-warning: not comparing packages to native builds"
		rm -Rf /tmp/chdist_native
		ENABLE_DEBBINDIFF=no
	fi
fi
if test "$ENABLE_DEBBINDIFF" = yes; then
	compare_native() {
		local pkg pkgname tmpdir downloadname errcode
		$APT_GET install debbindiff binutils-multiarch vim-common
		for pkg in "$@"; do
			if test "`dpkg-deb -f "$pkg" Architecture`" != "$HOST_ARCH"; then
				echo "not comparing $pkg: wrong architecture"
				continue
			fi
			pkgname=`dpkg-deb -f "$pkg" Package`
			tmpdir=`mktemp -d`
			if ! (cd "$tmpdir" && chdist_native apt-get download "$pkgname"); then
				echo "not comparing $pkg: download failed"
				rm -R "$tmpdir"
				continue
			fi
			downloadname=`dpkg-deb -W --showformat '${Package}_${Version}_${Architecture}.deb' "$pkg" | sed 's/:/%3a/'`
			if ! test -f "$tmpdir/$downloadname"; then
				echo "not comparing $pkg: downloaded different version"
				rm -R "$tmpdir"
				continue
			fi
			errcode=0
			timeout --kill-after=1m 1h debbindiff --text "$tmpdir/out" "$pkg" "$tmpdir/$downloadname" || errcode=$?
			case $errcode in
				0)
					echo "debbindiff-success: $pkg"
				;;
				1)
					if ! test -f "$tmpdir/out"; then
						echo "rebootstrap-error: no debbindiff output for $pkg"
						exit 1
					elif test "`wc -l < "$tmpdir/out"`" -gt 1000; then
						echo "truncated debbindiff output for $pkg:"
						head -n1000 "$tmpdir/out"
					else
						echo "debbindiff output for $pkg:"
						cat "$tmpdir/out"
					fi
				;;
				124)
					echo "rebootstrap-warning: debbindiff timed out"
				;;
				*)
					echo "rebootstrap-error: debbindiff terminated with abnormal exit code $errcode"
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
	if test -d "$RESULT/$pkg"; then
		echo "skipping rebuild of $pkg with profiles $profiles"
	else
		echo "building $pkg with profiles $profiles"
		installedpackages=$(record_installed_packages)
		if hook=`get_hook builddep "$pkg"`; then
			echo "installing Build-Depends for $pkg using custom function"
			"$hook" "$HOST_ARCH" "$profiles"
		else
			echo "installing Build-Depends for $pkg using apt-get build-dep"
			$APT_GET build-dep -a$HOST_ARCH --arch-only -P "$profiles" "$pkg"
		fi
		cross_build_setup "$pkg"
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
		test -d "$RESULT" && mkdir "$RESULT/$pkg"
		test -d "$RESULT" && cp ./*.deb "$RESULT/$pkg/"
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
	echo "deb [ arch=`dpkg --print-architecture` ] $MIRROR experimental main" > /etc/apt/sources.list.d/tmp-experimental.list
	$APT_GET update
	$APT_GET -t experimental install dpkg-cross
	rm /etc/apt/sources.list.d/tmp-experimental.list
	$APT_GET update
fi

if test "$ENABLE_MULTIARCH_GCC" != yes; then
	echo "adding sysroot paths to dpkg-shlibdeps"
	patch /usr/share/perl5/Dpkg/Shlibs.pm <<'EOF'
From da88b3913c504131afe06e64fb78202c71b2de7a Mon Sep 17 00:00:00 2001
From: Guillem Jover <guillem@debian.org>
Date: Fri, 22 May 2015 21:01:04 +0200
Subject: [PATCH] Revert "Dpkg::Shlibs: Do not add cross-root directories to
 default search list"

This reverts commit 93da43460d292198c02c5f0a8b0bf4929c0dd915.
---
 scripts/Dpkg/Shlibs.pm | 11 ++++++++++-
 1 file changed, 10 insertions(+), 1 deletion(-)

diff --git a/scripts/Dpkg/Shlibs.pm b/scripts/Dpkg/Shlibs.pm
index 184aa69..68e8d89 100644
--- a/scripts/Dpkg/Shlibs.pm
+++ b/scripts/Dpkg/Shlibs.pm
@@ -93,22 +93,31 @@ sub setup_library_paths {
 
     # Adjust set of directories to consider when we're in a situation of a
     # cross-build or a build of a cross-compiler.
-    my $multiarch;
+    my ($crossprefix, $multiarch);
 
     # Detect cross compiler builds.
     if ($ENV{DEB_TARGET_GNU_TYPE} and
         ($ENV{DEB_TARGET_GNU_TYPE} ne $ENV{DEB_BUILD_GNU_TYPE}))
     {
+        $crossprefix = $ENV{DEB_TARGET_GNU_TYPE};
         $multiarch = gnutriplet_to_multiarch($ENV{DEB_TARGET_GNU_TYPE});
     }
     # Host for normal cross builds.
     if (get_build_arch() ne get_host_arch()) {
+        $crossprefix = debarch_to_gnutriplet(get_host_arch());
         $multiarch = debarch_to_multiarch(get_host_arch());
     }
     # Define list of directories containing crossbuilt libraries.
     if ($multiarch) {
         push @librarypaths, "/lib/$multiarch", "/usr/lib/$multiarch";
     }
+    # XXX: Add deprecated sysroot and toolchain cross-compilation paths.
+    if ($crossprefix) {
+        push @librarypaths,
+             "/$crossprefix/lib", "/usr/$crossprefix/lib",
+             "/$crossprefix/lib32", "/usr/$crossprefix/lib32",
+             "/$crossprefix/lib64", "/usr/$crossprefix/lib64";
+    }
 
     push @librarypaths, DEFAULT_LIBRARY_PATH;
 
-- 
2.2.1.209.g41e5f3a
EOF
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
patch_gcc_musl_depends() {
	echo "patching gcc for musl dependencies"
	drop_privs patch -p1 <<'EOF'
diff -u gcc-4.9-4.9.2/debian/rules.conf gcc-4.9-4.9.2/debian/rules.conf
--- gcc-4.9-4.9.2/debian/rules.conf
+++ gcc-4.9-4.9.2/debian/rules.conf
@@ -240,6 +240,11 @@
   else
     LIBC_DEP = libc6
   endif
+  ifneq (,$(findstring musl-linux-,$(DEB_TARGET_ARCH)))
+    LIBC_DEP = musl
+    libc_ver = 0.9
+    libc_dev_ver = 0.9
+  endif
 else
   ifeq ($(DEB_TARGET_ARCH_OS),hurd)
     LIBC_DEP = libc0.3
EOF
}
patch_gcc_4_9() {
	echo "patching gcc-4.9 to build common libraries. not a bug"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.defs
+++ b/debian/rules.defs
@@ -378,8 +378,6 @@ with_common_pkgs := yes
 with_common_libs := yes
 # XXX: should with_common_libs be "yes" only if this is the default compiler
 # version on the targeted arch?
-with_common_pkgs :=
-with_common_libs :=
 
 # is this a multiarch-enabled build?
 ifeq (,$(filter $(distrelease),lenny etch squeeze dapper hardy jaunty karmic lucid maverick))
EOF
	echo "patching gcc to fix placement of biarch libs in i386 build"
	drop_privs patch -p1 <<'EOF'
diff -u gcc-4.9-4.9.2/debian/rules2 gcc-4.9-4.9.2/debian/rules2
--- gcc-4.9-4.9.2/debian/rules2
+++ gcc-4.9-4.9.2/debian/rules2
@@ -2185,6 +2185,16 @@
 	mkdir -p $(d)/$(PF)/powerpc-linux-gnu/lib64
 	cp -a $(d)/$(PF)/powerpc64-linux-gnu/lib64/* $(d)/$(PF)/powerpc-linux-gnu/lib64/
     endif
+    ifeq ($(DEB_TARGET_ARCH)-$(biarch64),i386-yes)
+	: # i386 64bit build happens to be in x86_64-linux-gnu/lib64
+	mkdir -p $(d)/$(PF)/i586-linux-gnu/lib64
+	cp -a $(d)/$(PF)/x86_64-linux-gnu/lib64/* $(d)/$(PF)/i586-linux-gnu/lib64/
+    endif
+    ifeq ($(DEB_TARGET_ARCH)-$(biarchx32),i386-yes)
+	: # i386 x32 build happens to be in x86_64-linux-gnux32/libx32
+	mkdir -p $(d)/$(PF)/i586-linux-gnu/libx32
+	cp -a $(d)/$(PF)/x86_64-linux-gnux32/libx32/* $(d)/$(PF)/i586-linux-gnu/libx32/
+    endif
   endif
 endif
 
EOF
	echo "fixing cross-biarch.diff to remap lib32 to libo32 on mips64el"
	drop_privs patch -p1 <<'EOF'
diff -u gcc-4.9-4.9.2/debian/patches/cross-biarch.diff gcc-4.9-4.9.2/debian/patches/cross-biarch.diff
--- gcc-4.9-4.9.2/debian/patches/cross-biarch.diff
+++ gcc-4.9-4.9.2/debian/patches/cross-biarch.diff
@@ -4,13 +4,18 @@
 
 --- a/src/config-ml.in
 +++ b/src/config-ml.in
-@@ -514,7 +514,12 @@ multi-do:
+@@ -514,7 +514,17 @@ multi-do:
  	    else \
  	      if [ -d ../$${dir}/$${lib} ]; then \
  		flags=`echo $$i | sed -e 's/^[^;]*;//' -e 's/@/ -/g'`; \
 -		if (cd ../$${dir}/$${lib}; $(MAKE) $(FLAGS_TO_PASS) \
 +		libsuffix_="$${dir}"; \
 +		if [ "$${dir}" = "n32" ]; then libsuffix_=32; fi; \
++EOF
++cat >>Multi.tem <<EOF
++		case "\$\${dir}:${host}" in 32:mips*) libsuffix_=o32; ;; esac; \\
++EOF
++cat >>Multi.tem <<\EOF
 +		if (cd ../$${dir}/$${lib}; $(MAKE) $(subst \
 +				-B$(build_tooldir)/lib/, \
 +				-B$(build_tooldir)/lib$${libsuffix_}/, \
EOF
	patch_gcc_os_include_dir_musl
	patch_gcc_musl_depends
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		echo "applying patches for with_deps_on_target_arch_pkgs"
		drop_privs QUILT_PATCHES="/usr/share/cross-gcc/patches/gcc-$GCC_VER" quilt push -a
	fi
}
patch_gcc_5() {
	patch_gcc_os_include_dir_musl
	patch_gcc_musl_depends
	echo "patching gcc-5 to use all of /usr/include/<triplet>"
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
	echo "patching gcc-5 to support building without binutils-multiarch"
	drop_privs patch -p1 <<'EOF'
diff -u gcc-5-5.2.1/debian/rules.d/binary-ada.mk gcc-5-5.2.1/debian/rules.d/binary-ada.mk
--- gcc-5-5.2.1/debian/rules.d/binary-ada.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-ada.mk
@@ -126,7 +126,7 @@
 		$(d_lgnat)/usr/share/lintian/overrides/$(p_lgnat)
 endif
 
-	dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnat) --dbg-package=$(p_lgnat_dbg)
 	dh_compress -p$(p_lgnat)
 	dh_fixperms -p$(p_lgnat)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_lgnat) \
@@ -174,7 +174,7 @@
 	   $(usr_lib)/libgnatvsn.so.$(GNAT_VERSION) \
 	   $(usr_lib)/libgnatvsn.so
 	debian/dh_doclink -p$(p_lgnatvsn_dev) $(p_glbase)
-	dh_strip -p$(p_lgnatvsn_dev) -X.a --keep-debug
+	$(cross_strip) dh_strip -p$(p_lgnatvsn_dev) -X.a --keep-debug
 	dh_fixperms -p$(p_lgnatvsn_dev)
 	$(cross_gencontrol) dh_gencontrol -p$(p_lgnatvsn_dev) \
 		-- -v$(DEB_VERSION) $(common_substvars)
@@ -190,7 +190,7 @@
 endif
 	$(dh_compat2) dh_movefiles -p$(p_lgnatvsn) $(usr_lib)/libgnatvsn.so.$(GNAT_VERSION)
 	debian/dh_doclink -p$(p_lgnatvsn) $(p_glbase)
-	dh_strip -p$(p_lgnatvsn) --dbg-package=$(p_lgnatvsn_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnatvsn) --dbg-package=$(p_lgnatvsn_dbg)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_lgnatvsn) \
 		-V '$(p_lgnatvsn) (>= $(DEB_VERSION))'
 	$(call cross_mangle_shlibs,$(p_lgnatvsn))
@@ -239,7 +239,7 @@
 	dh_link -p$(p_lgnatprj_dev) \
 	   $(usr_lib)/libgnatprj.so.$(GNAT_VERSION) \
 	   $(usr_lib)/libgnatprj.so
-	dh_strip -p$(p_lgnatprj_dev) -X.a --keep-debug
+	$(cross_strip) dh_strip -p$(p_lgnatprj_dev) -X.a --keep-debug
 	debian/dh_doclink -p$(p_lgnatprj_dev) $(p_glbase)
 	dh_fixperms -p$(p_lgnatprj_dev)
 	$(cross_gencontrol) dh_gencontrol -p$(p_lgnatprj_dev) \
@@ -256,7 +256,7 @@
 endif
 	$(dh_compat2) dh_movefiles -p$(p_lgnatprj) $(usr_lib)/libgnatprj.so.$(GNAT_VERSION)
 	debian/dh_doclink -p$(p_lgnatprj) $(p_glbase)
-	dh_strip -p$(p_lgnatprj) --dbg-package=$(p_lgnatprj_dbg)
+	$(cross_strip) dh_strip -p$(p_lgnatprj) --dbg-package=$(p_lgnatprj_dbg)
 	dh_fixperms -p$(p_lgnatprj)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_lgnatprj) \
 		-V '$(p_lgnatprj) (>= $(DEB_VERSION))'
@@ -398,7 +398,7 @@
 
 	debian/dh_rmemptydirs -p$(p_gnat)
 
-	dh_strip -p$(p_gnat)
+	$(cross_strip) dh_strip -p$(p_gnat)
 	dh_compress -p$(p_gnat)
 	dh_fixperms -p$(p_gnat)
 	find $(d_gnat) -name '*.ali' | xargs chmod 444
@@ -412,7 +412,7 @@
 	dh_builddeb -p$(p_gnat)
 
 ifeq ($(with_gnatsjlj),yes)
-	dh_strip -p$(p_gnatsjlj)
+	$(cross_strip) dh_strip -p$(p_gnatsjlj)
 	dh_compress -p$(p_gnatsjlj)
 	dh_fixperms -p$(p_gnatsjlj)
 	find $(d_gnatsjlj) -name '*.ali' | xargs chmod 444
diff -u gcc-5-5.2.1/debian/rules.d/binary-fortran.mk gcc-5-5.2.1/debian/rules.d/binary-fortran.mk
--- gcc-5-5.2.1/debian/rules.d/binary-fortran.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-fortran.mk
@@ -97,7 +97,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
@@ -137,7 +137,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	dh_compress -p$(p_l)
 	dh_fixperms -p$(p_l)
 	$(cross_shlibdeps) dh_shlibdeps -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libasan.mk gcc-5-5.2.1/debian/rules.d/binary-libasan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libasan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libasan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libatomic.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libcilkrts.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libgcc.mk
@@ -161,7 +161,7 @@
 	debian/dh_doclink -p$(2) $(p_lbase)
 	debian/dh_rmemptydirs -p$(2)
 
-	dh_strip -p$(2)
+	$(cross_strip) dh_strip -p$(2)
 	dh_compress -p$(2)
 	$(cross_shlibdeps) dh_shlibdeps -p$(2)
 	$(call cross_mangle_substvars,$(2))
@@ -295,7 +295,7 @@
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
 	dh_compress -p$(p_jitlib) -p$(p_jitdev) -p$(p_jitdbg)
 	dh_fixperms -p$(p_jitlib) -p$(p_jitdev) -p$(p_jitdbg)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_jitlib)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libgomp.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libitm.mk gcc-5-5.2.1/debian/rules.d/binary-libitm.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libitm.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libitm.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-liblsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libmpx.mk
@@ -37,7 +37,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libobjc.mk
@@ -65,7 +65,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l) -Xlibobjc_gc.so
diff -u gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libquadmath.mk
@@ -30,7 +30,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_doclink -p$(p_d) $(p_lbase)
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libstdcxx.mk
@@ -207,7 +207,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
+	$(cross_strip) dh_strip -p$(p_l) $(if $(filter rtlibs,$(DEB_STAGE)),,--dbg-package=$(1)-$(BASE_VERSION)-dbg$(cross_lib_arch))
 	dh_compress -p$(p_l)
 	dh_fixperms -p$(p_l)
 
@@ -244,7 +244,7 @@
 	$(if $(filter yes,$(with_lib$(2)cxx)),
 		cp -a $(d)/$(usr_lib$(2))/libstdc++.so.*[0-9] \
 			$(d_d)/$(usr_lib$(2))/.;
-		dh_strip -p$(p_d) --keep-debug;
+		$(cross_strip) dh_strip -p$(p_d) --keep-debug;
 		$(if $(filter yes,$(with_common_libs)),, # if !with_common_libs
 			# remove the debug symbols for libstdc++
 			# built by a newer version of GCC
@@ -299,7 +299,7 @@
 	debian/dh_doclink -p$(p_l) $(p_lbase)
 	debian/dh_rmemptydirs -p$(p_l)
 
-	dh_strip -p$(p_l)
+	$(cross_strip) dh_strip -p$(p_l)
 	dh_compress -p$(p_l)
 	dh_fixperms -p$(p_l)
 	dh_shlibdeps -p$(p_l) \
@@ -451,16 +451,16 @@
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
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libubsan.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk
--- gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk
+++ gcc-5-5.2.1/debian/rules.d/binary-libvtv.mk
@@ -35,7 +35,7 @@
 		cp debian/$(p_l).overrides debian/$(p_l)/usr/share/lintian/overrides/$(p_l); \
 	fi
 
-	dh_strip -p$(p_l) --dbg-package=$(p_d)
+	$(cross_strip) dh_strip -p$(p_l) --dbg-package=$(p_d)
 	dh_compress -p$(p_l) -p$(p_d)
 	dh_fixperms -p$(p_l) -p$(p_d)
 	$(cross_makeshlibs) dh_makeshlibs -p$(p_l)
diff -u gcc-5-5.2.1/debian/rules.defs gcc-5-5.2.1/debian/rules.defs
--- gcc-5-5.2.1/debian/rules.defs
+++ gcc-5-5.2.1/debian/rules.defs
@@ -212,6 +212,7 @@
   cross_gencontrol = DEB_HOST_ARCH=$(TARGET)
   cross_makeshlibs = DEB_HOST_ARCH=$(TARGET)
   cross_clean = DEB_HOST_ARCH=$(TARGET)
+  cross_strip = DEB_HOST_GNU_TYPE=$(DEB_TARGET_GNU_TYPE)
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
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		echo "applying patches for with_deps_on_target_arch_pkgs"
		drop_privs QUILT_PATCHES="/usr/share/cross-gcc/patches/gcc-$GCC_VER" quilt push -a
	fi
}
# choosing libatomic1 arbitrarily here, cause it never bumped soname
BUILD_GCC_MULTIARCH_VER=`apt-cache show --no-all-versions libatomic1 | sed 's/^Source: gcc-\([0-9.]*\)$/\1/;t;d'`
if test "$ENABLE_MULTIARCH_GCC" != yes; then
	echo "not building with_deps_on_target_arch_pkgs, version of gcc libraries does not have to match"
elif test "$GCC_VER" != "$BUILD_GCC_MULTIARCH_VER"; then
	echo "host gcc version ($GCC_VER) and build gcc version ($BUILD_GCC_MULTIARCH_VER) mismatch. need different build gcc"
if test -d "$RESULT/gcc0"; then
	echo "skipping rebuild of build gcc"
	dpkg -i $RESULT/gcc0/*.deb
else
	$APT_GET build-dep --arch-only gcc-$GCC_VER
	# dependencies for common libs no longer declared
	$APT_GET install doxygen graphviz ghostscript texlive-latex-base xsltproc docbook-xsl-ns
	cross_build_setup "gcc-$GCC_VER" gcc0
	drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,$GCC_NOLANG" dpkg-buildpackage -T control -uc -us
	drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,$GCC_NOLANG" dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	reprepro include rebootstrap-native ./*.changes
	drop_privs rm -fv ./*-plugin-dev_*.deb ./*-dbg_*.deb
	dpkg -i *.deb
	test -d "$RESULT" && mkdir "$RESULT/gcc0"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc0"
	cd ..
	drop_privs rm -Rf gcc0
fi
progress_mark "build compiler complete"
else
echo "host gcc version and build gcc version match. good for multiarch"
fi

# binutils
patch_binutils() {
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
	echo "patching binutils to allow building cross binutils again"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -432,6 +432,7 @@
 ifneq (,$(TARGET))
 	sed "s/@dpkg_dev@/$(DPKG_DEV)/;/^$$/ q" < debian/control.in > debian/control
 	sed -e "s/@target@/$$(echo -n $(TARGET) | sed s/_/-/g)/" \
+		-e "s/@host_archs@/any/" \
 		< debian/control.cross.in >> debian/control
 else
 	sed -e 's/@dpkg_dev@/$(DPKG_DEV)/' \
EOF
}
if test -f "`echo $RESULT/binutils${HOST_ARCH_SUFFIX}_*.deb`"; then
	echo "skipping rebuild of binutils-target"
else
	$APT_GET install autoconf bison flex gettext texinfo dejagnu quilt chrpath python3 file xz-utils lsb-release zlib1g-dev
	cross_build_setup binutils
	drop_privs TARGET=$HOST_ARCH dpkg-buildpackage --target=stamps/control
	drop_privs WITH_SYSROOT=/ TARGET=$HOST_ARCH dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET install binutils$HOST_ARCH_SUFFIX
	assembler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-as"
	if ! which "$assembler"; then echo "$assembler missing in binutils package"; exit 1; fi
	if ! drop_privs "$assembler" -o test.o /dev/null; then echo "binutils fail to execute"; exit 1; fi
	if ! test -f test.o; then echo "binutils fail to create object"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	test -d "$RESULT" && cp -v binutils-*.deb "$RESULT"
	cd ..
	drop_privs rm -Rf binutils
fi
progress_mark "cross binutils"

if test "$HOST_ARCH" = hppa && ! test -f "`echo $RESULT/binutils-hppa64-linux-gnu_*.deb`"; then
	$APT_GET install autoconf bison flex gettext texinfo dejagnu quilt chrpath python3 file xz-utils lsb-release zlib1g-dev
	cross_build_setup binutils binutils-hppa64
	drop_privs TARGET=hppa64-linux-gnu dpkg-buildpackage --target=stamps/control
	drop_privs WITH_SYSROOT=/ TARGET=hppa64-linux-gnu dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	pickup_additional_packages *.changes
	$APT_GET install binutils-hppa64-linux-gnu
	if ! which hppa64-linux-gnu-as; then echo "hppa64-linux-gnu-as missing in binutils package"; exit 1; fi
	if ! drop_privs hppa64-linux-gnu-as -o test.o /dev/null; then echo "binutils-hppa64 fail to execute"; exit 1; fi
	if ! test -f test.o; then echo "binutils-hppa64 fail to create object"; exit 1; fi
	check_arch test.o hppa64
	test -d "$RESULT" && cp -v binutils-hppa64-linux-gnu_*.deb "$RESULT"
	cd ..
	drop_privs rm -Rf binutils-hppa64-linux-gnu
	progress_mark "cross binutils-hppa64"
fi

# linux
patch_linux() {
	if test "$HOST_ARCH" = arm; then
		echo "patching linux for arm"
		drop_privs patch -p1 <<EOF
diff -Nru linux-3.14.7/debian/config/arm/defines linux-3.14.7/debian/config/arm/defines
--- linux-3.14.7/debian/config/arm/defines
+++ linux-3.14.7/debian/config/arm/defines
@@ -0,0 +1,4 @@
+[base]
+kernel-arch: arm
+featuresets:
+# empty; just building headers yet
diff -Nru linux-3.14.7/debian/config/defines linux-3.14.7/debian/config/defines
--- linux-3.14.7/debian/config/defines
+++ linux-3.14.7/debian/config/defines
@@ -23,6 +23,7 @@
 arches:
  alpha
  amd64
+ arm
  arm64
  armel
  armhf
EOF
		drop_privs ./debian/rules debian/rules.gen || : # intentionally exits 1 to avoid being called automatically. we are doing it wrong
	fi
	if test "$HOST_ARCH" = powerpcel; then
		echo "patching linux for powerpcel"
		drop_privs patch -p1 <<'EOF'
diff -Nru linux-*/debian/config/powerpcel/defines linux-*/debian/config/powerpcel/defines
--- linux-*/debian/config/powerpcel/defines
+++ linux-*/debian/config/powerpcel/defines
@@ -0,0 +1,4 @@
+[base]
+kernel-arch: powerpc
+featuresets:
+# empty; just building headers yet
diff -Nru linux-*/debian/config/defines linux-*/debian/config/defines
--- linux-*/debian/config/defines
+++ linux-*/debian/config/defines
@@ -22,6 +22,7 @@
  mips64el
  or1k
  powerpc
+ powerpcel
  powerpcspe
  ppc64
  ppc64el
EOF
		drop_privs ./debian/rules debian/rules.gen || : # intentionally exits 1 to avoid being called automatically. we are doing it wrong
	fi
	if test "$LIBC_NAME" = musl; then
		echo "patching linux for musl-linux-any"
		drop_privs sed -i "/^arches:/a\ $HOST_ARCH" debian/config/defines
		drop_privs mkdir -p "debian/config/$HOST_ARCH"
		drop_privs cat > "debian/config/$HOST_ARCH/defines" <<EOF
[base]
kernel-arch: `sed 's/^kernel-arch: //;t;d' < "debian/config/${HOST_ARCH#musl-linux-}/defines"`
featuresets:
# empty; $HOST_ARCH must be part of a multiarch installation with an ${HOST_ARCH#musl-linux-} kernel
EOF
		drop_privs ./debian/rules debian/rules.gen || : # intentionally exits 1 to avoid being called automatically. we are doing it wrong
	fi
}
if test "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS`" = "linux"; then
PKG=`echo $RESULT/linux-libc-dev_*.deb`
if test -f "$PKG"; then
	echo "skipping rebuild of linux-libc-dev"
else
	$APT_GET install bc cpio debhelper kernel-wedge patchutils python quilt python-six
	cross_build_setup linux
	linux_ma_skew=no
	if test "$(dpkg-architecture -qDEB_HOST_ARCH_OS)" = linux && test "$(dpkg-query -W -f '${Version}' "linux-libc-dev:$(dpkg --print-architecture)")" != "$(dpkg-parsechangelog -SVersion)"; then
		echo "rebootstrap-warning: working around linux-libc-dev m-a:same skew"
		linux_ma_skew=yes
	fi
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	if test -n "$DROP_PRIVS"; then
		test "$linux_ma_skew" = yes && drop_privs KBUILD_VERBOSE=1 fakeroot make -f debian/rules.gen "binary-libc-dev_$(dpkg --print-architecture)"
		drop_privs KBUILD_VERBOSE=1 fakeroot make -f debian/rules.gen "binary-libc-dev_$HOST_ARCH"
	else
		test "$linux_ma_skew" = yes && KBUILD_VERBOSE=1 make -f debian/rules.gen "binary-libc-dev_$(dpkg --print-architecture)"
		KBUILD_VERBOSE=1 make -f debian/rules.gen "binary-libc-dev_$HOST_ARCH"
	fi
	cd ..
	ls -l
	if test "$ENABLE_MULTIARCH_GCC" != yes; then
		drop_privs dpkg-cross -M -a "$HOST_ARCH" -b ./*"_$HOST_ARCH.deb"
	fi
	pickup_packages *.deb
	test -d "$RESULT" && cp -v linux-libc-dev_*.deb "$RESULT"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf linux
fi
progress_mark "linux-libc-dev cross build"
fi

# gnumach
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -d "$RESULT/gnumach_1"; then
	echo "skipping rebuild of gnumach stage1"
else
	$APT_GET install debhelper sharutils autoconf automake texinfo
	cross_build_setup gnumach gnumach_1
	drop_privs dpkg-buildpackage -B "-a$HOST_ARCH" -Pstage1 -uc -us
	cd ..
	pickup_packages ./*.deb
	test -d "$RESULT" && mkdir "$RESULT/gnumach_1"
	test -d "$RESULT" && cp -v ./*.deb "$RESULT/gnumach_1"
	cd ..
	drop_privs rm -Rf gnumach_1
fi
progress_mark "gnumach stage1 cross build"
fi

patch_kfreebsd_kernel_headers() {
	echo "patching kfreebsd-kernel-headers to implement nocheck #796903"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -11,7 +11,7 @@
  debhelper (>= 7),
  quilt,
  kfreebsd-source-10.1 (>> 10.1~svn273304~),
- libc0.1-dev (>= 2.18-2~),
+ libc0.1-dev (>= 2.18-2~) <!nocheck>,
 Vcs-Browser: http://anonscm.debian.org/viewvc/glibc-bsd/trunk/kfreebsd-kernel-headers/
 Vcs-Svn: svn://anonscm.debian.org/glibc-bsd/trunk/kfreebsd-kernel-headers/
 Standards-Version: 3.9.4
--- a/debian/rules
+++ b/debian/rules
@@ -128,8 +128,10 @@
 		&& find . -type f -name "*.h" -exec cp --parents {} $(HEADERS_PACKAGE)/usr/include/x86 \;
 endif

+ifeq ($(filter nocheck,$(DEB_BUILD_OPTIONS)),)
 	# headers must be tested after they're installed
	$(MAKE) -C test
+endif

 install: install-indep install-arch

EOF
}
builddep_kfreebsd_kernel_headers() {
	# libc0.1-dev needs <!nocheck> profile
	$APT_GET install debhelper quilt kfreebsd-source-10.1
}
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = kfreebsd; then
cross_build kfreebsd-kernel-headers
fi

# gcc
if test -d "$RESULT/gcc1"; then
	echo "skipping rebuild of gcc stage1"
	apt_get_remove gcc-multilib
	dpkg -i $RESULT/gcc1/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev "binutils$HOST_ARCH_SUFFIX"
	if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
		$APT_GET install "linux-libc-dev:$HOST_ARCH"
	fi
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	cross_build_setup "gcc-$GCC_VER" gcc1
	dpkg-checkbuilddeps || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	if test "$ENABLE_MULTILIB" = yes; then
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	else
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
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
	test -d "$RESULT" && mkdir "$RESULT/gcc1"
	test -d "$RESULT" && cp cpp-$GCC_VER-*.deb gcc-$GCC_VER-*.deb "$RESULT/gcc1"
	cd ..
	drop_privs rm -Rf gcc1
fi
progress_mark "cross gcc stage1 build"

# replacement for cross-gcc-defaults
for prog in c++ cpp g++ gcc gcc-ar gcc-ranlib gfortran; do
	ln -vs "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-$prog-$GCC_VER" "/usr/bin/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-$prog"
done
ln -s "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER" "/usr/bin/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-cc"

# hurd
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -d "$RESULT/hurd_1"; then
	echo "skipping rebuild of hurd stage1"
else
	$APT_GET install texinfo debhelper dh-exec autoconf dh-autoreconf gawk flex bison autotools-dev
	cross_build_setup hurd hurd_1
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1
	drop_privs dpkg-buildpackage -B "-a$HOST_ARCH" -Pstage1 -uc -us
	cd ..
	pickup_packages ./*.changes
	test -d "$RESULT" && mkdir "$RESULT/hurd_1" && cp -v ./*.deb "$RESULT/hurd_1"
	cd ..
	drop_privs rm -Rf hurd_1
fi
progress_mark "hurd stage1 cross build"
fi

# mig
if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -d "$RESULT/mig_1"; then
	echo "skipping rebuild of mig cross"
else
	$APT_GET build-dep "-a$HOST_ARCH" --arch-only mig # this is correct by luck
	cross_build_setup mig mig_1
	drop_privs dpkg-buildpackage -d -B "--target-arch=$HOST_ARCH" -uc -us
	cd ..
	pickup_packages ./*.changes
	test -d "$RESULT" && mkdir "$RESULT/mig_1" && cp -v ./*.deb "$RESULT/mig_1"
	cd ..
	drop_privs rm -Rf mig_1
fi
progress_mark "cross mig build"
fi

# libc
patch_glibc() {
	echo "patching eglibc to include a libc6.so and place crt*.o in correct directory"
	drop_privs patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/rules.d/build.mk eglibc-2.18/debian/rules.d/build.mk
--- eglibc-2.18/debian/rules.d/build.mk
+++ eglibc-2.18/debian/rules.d/build.mk
@@ -163,10 +163,11 @@
 	    cross-compiling=yes install_root=\$(CURDIR)/debian/tmp-\$(curpass)	\\
 	    install-bootstrap-headers=yes install-headers )
 
-	install -d \$(CURDIR)/debian/tmp-\$(curpass)/lib
-	install -m 644 \$(DEB_BUILDDIR)/csu/crt[01in].o \$(CURDIR)/debian/tmp-\$(curpass)/lib
+	install -d \$(CURDIR)/debian/tmp-\$(curpass)/\$(call xx,libdir)
+	install -m 644 \$(DEB_BUILDDIR)/csu/crt[01in].o \\
+		\$(CURDIR)/debian/tmp-\$(curpass)/\$(call xx,libdir)
-	\${CC} -nostdlib -nostartfiles -shared -x c /dev/null \\
+	\$(call xx,CC) -nostdlib -nostartfiles -shared -x c /dev/null \\
-	        -o \$(CURDIR)/debian/tmp-\$(curpass)/lib/libc.so
+	        -o \$(CURDIR)/debian/tmp-\$(curpass)/\$(call xx,libdir)/libc.so
 else
 	: # FIXME: why just needed for ARM multilib?
 	case "\$(curpass)" in \\
diff -Nru glibc-2.19/debian/rules.d/debhelper.mk glibc-2.19/debian/rules.d/debhelper.mk
--- glibc-2.19/debian/rules.d/debhelper.mk
+++ glibc-2.19/debian/rules.d/debhelper.mk
@@ -197,7 +197,18 @@
 	curpass=\$(curpass) ; \\
 	templates="libc-dev" ;\\
-	pass="" ; \\
-	suffix="" ;\\
+	case "\$\$curpass:\$\$slibdir" in \\
+	  libc:*) \\
+	    pass="" \\
+	    suffix="" \\
+	    ;; \\
+	  *:/lib32 | *:/lib64 | *:/libo32 | *:/libx32 | *:/lib/arm-linux-gnueabi*) \\
+	    pass="-alt" \\
+	    suffix=-"\$(curpass)" \\
+	    ;; \\
+	  *:* ) \\
+           templates="" \\
+	    ;; \\
+	esac ; \\
 	for t in \$\$templates ; do \\
 	  for s in debian/\$\$t\$\$pass.* ; do \\
 	    t=\`echo \$\$s | sed -e "s#libc\\(.*\\)\$\$pass#\$(libc)\\1\$\$suffix#"\` ; \\
@@ -207,10 +215,10 @@
 	    sed -e "s#TMPDIR#debian/tmp-\$\$curpass#g" -i \$\$t; \\
 	    sed -e "s#RTLDDIR#\$\$rtlddir#g" -i \$\$t; \\
 	    sed -e "s#SLIBDIR#\$\$slibdir#g" -i \$\$t; \\
+	    sed -e "/LIBDIR.*\\.a /d" -i \$\$t; \\
+	    sed -e "s#LIBDIR#\$\$libdir#g" -i \$\$t; \\
 	  done ; \\
 	done
-
-	sed -e "/LIBDIR.*.a /d" -e "s#LIBDIR#lib#g" -i debian/\$(libc)-dev.install
 else
 \$(patsubst %,debhelper_%,\$(GLIBC_PASSES)) :: debhelper_% : \$(stamp)debhelper_%
 \$(stamp)debhelper_%: \$(stamp)debhelper-common \$(stamp)install_%
EOF
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
	echo "patching glibc to use multi-arch paths for headers in stage1"
	drop_privs patch -p1 <<'EOF'
diff -Nru glibc-2.19/debian/rules.d/build.mk glibc-2.19/debian/rules.d/build.mk
--- glibc-2.19/debian/rules.d/build.mk
+++ glibc-2.19/debian/rules.d/build.mk
@@ -207,6 +207,7 @@
 	  $(MAKE) -f debian/generate-supported.mk IN=localedata/SUPPORTED \
 	    OUT=debian/tmp-$(curpass)/usr/share/i18n/SUPPORTED; \
 	fi
+endif
 
 	# Create the multiarch directories, and the configuration file in /etc/ld.so.conf.d
 	if [ $(curpass) = libc ]; then \
@@ -251,6 +252,7 @@
 	  echo "$(call xx,libdir)" >> $$conffile; \
 	esac
 
+ifeq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
 	# ARM: add dynamic linker name for the non-default multilib in ldd
 	if [ $(curpass) = libc ]; then \
 	  case $(DEB_HOST_ARCH) in \
EOF
	echo "patching eglibc to avoid dependency on libc6 from libc6-dev in stage1"
	drop_privs patch -p1 <<'EOF'
diff -Nru glibc-2.19/debian/control.in/amd64 glibc-2.19/debian/control.in/amd64
--- glibc-2.19/debian/control.in/amd64
+++ glibc-2.19/debian/control.in/amd64
@@ -14,7 +14,7 @@
 Architecture: i386 x32
 Section: libdevel
 Priority: optional
-Depends: libc6-amd64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-amd64 (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: amd64-libs-dev (<= 1.2), libc6-dev (<< 2.13-11)
diff -Nru glibc-2.19/debian/control.in/armel glibc-2.19/debian/control.in/armel
--- glibc-2.19/debian/control.in/armel
+++ glibc-2.19/debian/control.in/armel
@@ -13,7 +13,7 @@
 Architecture: armhf
 Section: libdevel
 Priority: optional
-Depends: libc6-armel (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-armel (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: ARM softfp development libraries for armhf
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/armhf glibc-2.19/debian/control.in/armhf
--- glibc-2.19/debian/control.in/armhf
+++ glibc-2.19/debian/control.in/armhf
@@ -13,7 +13,7 @@
 Architecture: armel
 Section: libdevel
 Priority: optional
-Depends: libc6-armhf (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-armhf (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: ARM hard float development libraries for armel
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/i386 glibc-2.19/debian/control.in/i386
--- glibc-2.19/debian/control.in/i386
+++ glibc-2.19/debian/control.in/i386
@@ -18,7 +18,7 @@
 Provides: lib32c-dev
 Conflicts: libc6-i386 (<= 2.9-18), libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-i386 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-i386 (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 32-bit development libraries for AMD64
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/kfreebsd-i386 glibc-2.19/debian/control.in/kfreebsd-i386
--- glibc-2.19/debian/control.in/kfreebsd-i386
+++ glibc-2.19/debian/control.in/kfreebsd-i386
@@ -16,7 +16,7 @@
 Provides: lib32c-dev
 Conflicts: libc0.1-dev (<< 2.13-14)
 Replaces: libc0.1-dev (<< 2.13-11)
-Depends: libc0.1-i386 (= ${binary:Version}), libc0.1-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc0.1-i386 (= ${binary:Version}) <!stage1>, libc0.1-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 32bit development libraries for AMD64
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/libc glibc-2.19/debian/control.in/libc
--- glibc-2.19/debian/control.in/libc
+++ glibc-2.19/debian/control.in/libc
@@ -32,7 +32,7 @@
 Section: libdevel
 Priority: optional
 Multi-Arch: same
-Depends: @libc@ (= ${binary:Version}), libc-dev-bin (= ${binary:Version}), ${misc:Depends}, linux-libc-dev [linux-any], kfreebsd-kernel-headers (>= 0.11) [kfreebsd-any], gnumach-dev [hurd-i386], hurd-dev (>= 20080607-3) [hurd-i386]
+Depends: @libc@ (= ${binary:Version}) <!stage1>, libc-dev-bin (= ${binary:Version}), ${misc:Depends}, linux-libc-dev [linux-any], kfreebsd-kernel-headers (>= 0.11) [kfreebsd-any], gnumach-dev [hurd-i386], hurd-dev (>= 20080607-3) [hurd-i386]
 Replaces: hurd-dev (<< 20120408-3) [hurd-i386]
 Recommends: gcc | c-compiler
 Suggests: glibc-doc, manpages-dev
diff -Nru glibc-2.19/debian/control.in/mips32 glibc-2.19/debian/control.in/mips32
--- glibc-2.19/debian/control.in/mips32
+++ glibc-2.19/debian/control.in/mips32
@@ -16,7 +16,7 @@
 Provides: lib32c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-dev (= ${binary:Version}), libc6-mips32 (= ${binary:Version}),
+Depends: libc6-dev (= ${binary:Version}), libc6-mips32 (= ${binary:Version}) <!stage1>,
    libc6-dev-mipsn32 (= ${binary:Version}) [mips64 mips64el],
    libc6-dev-mips64 (= ${binary:Version}) [mipsn32 mipsn32el],
    ${misc:Depends}
diff -Nru glibc-2.19/debian/control.in/mips64 glibc-2.19/debian/control.in/mips64
--- glibc-2.19/debian/control.in/mips64
+++ glibc-2.19/debian/control.in/mips64
@@ -16,7 +16,7 @@
 Provides: lib64c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-mips64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-mips64 (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 64bit Development Libraries for MIPS64
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/mipsn32 glibc-2.19/debian/control.in/mipsn32
--- glibc-2.19/debian/control.in/mipsn32
+++ glibc-2.19/debian/control.in/mipsn32
@@ -16,7 +16,7 @@
 Provides: libn32c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-mipsn32 (= ${binary:Version}), libc6-dev-mips64 (= ${binary:Version}) [mips mipsel], libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-mipsn32 (= ${binary:Version}) <!stage1>, libc6-dev-mips64 (= ${binary:Version}) [mips mipsel] <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: n32 Development Libraries for MIPS64
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/powerpc glibc-2.19/debian/control.in/powerpc
--- glibc-2.19/debian/control.in/powerpc
+++ glibc-2.19/debian/control.in/powerpc
@@ -16,7 +16,7 @@
 Provides: lib32c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-powerpc (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-powerpc (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 32bit powerpc development libraries for ppc64
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/ppc64 glibc-2.19/debian/control.in/ppc64
--- glibc-2.19/debian/control.in/ppc64
+++ glibc-2.19/debian/control.in/ppc64
@@ -16,7 +16,7 @@
 Provides: lib64c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-ppc64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-ppc64 (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 64bit Development Libraries for PowerPC64
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/s390 glibc-2.19/debian/control.in/s390
--- glibc-2.19/debian/control.in/s390
+++ glibc-2.19/debian/control.in/s390
@@ -16,7 +16,7 @@
 Provides: lib32c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-s390 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-s390 (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 32bit Development Libraries for IBM zSeries
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/sparc glibc-2.19/debian/control.in/sparc
--- glibc-2.19/debian/control.in/sparc
+++ glibc-2.19/debian/control.in/sparc
@@ -16,7 +16,7 @@
 Provides: lib32c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-sparc (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-sparc (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 32bit Development Libraries for SPARC
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/sparc64 glibc-2.19/debian/control.in/sparc64
--- glibc-2.19/debian/control.in/sparc64
+++ glibc-2.19/debian/control.in/sparc64
@@ -16,7 +16,7 @@
 Provides: lib64c-dev
 Conflicts: libc6-dev (<< 2.13-14)
 Replaces: libc6-dev (<< 2.13-11)
-Depends: libc6-sparc64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-sparc64 (= ${binary:Version}) <!stage1>, libc6-dev (= ${binary:Version}), ${misc:Depends}
 Recommends: gcc-multilib
 Description: GNU C Library: 64bit Development Libraries for UltraSPARC
  Contains the symlinks and object files needed to compile and link programs
diff -Nru glibc-2.19/debian/control.in/x32 glibc-2.19/debian/control.in/x32
--- glibc-2.19/debian/control.in/x32
+++ glibc-2.19/debian/control.in/x32
@@ -13,8 +13,8 @@
 Architecture: amd64 i386
 Section: libdevel
 Priority: optional
-Depends: libc6-x32 (= ${binary:Version}), libc6-dev-i386 (= ${binary:Version}) [amd64], libc6-dev-amd64 (= ${binary:Version}) [i386], libc6-dev (= ${binary:Version}), ${misc:Depends}
+Depends: libc6-x32 (= ${binary:Version}) <!stage1>, libc6-dev-i386 (= ${binary:Version}) [amd64], libc6-dev-amd64 (= ${binary:Version}) [i386], libc6-dev (= ${binary:Version}), ${misc:Depends}
 Build-Profiles: <!nobiarch>
 Description: GNU C Library: X32 ABI Development Libraries for AMD64
  Contains the symlinks and object files needed to compile and link programs
  which use the standard C library. This is the X32 ABI version of the
EOF
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
	if test "$HOST_ARCH" = powerpcel; then
		echo "patching glibc for powerpcel"
		drop_privs patch -p1 <<'EOF'
diff -Nru glibc-2.19/debian/rules.d/control.mk glibc-2.19/debian/rules.d/control.mk
--- glibc-2.19/debian/rules.d/control.mk
+++ glibc-2.19/debian/rules.d/control.mk
@@ -1,7 +1,7 @@
 libc_packages := libc6 libc6.1 libc0.1 libc0.3
 libc0_1_archs := kfreebsd-amd64 kfreebsd-i386
 libc0_3_archs := hurd-i386
-libc6_archs   := amd64 arm arm64 armel armhf hppa i386 m68k mips mipsel mipsn32 mipsn32el mips64 mips64el powerpc powerpcspe ppc64 ppc64el sparc sparc64 s390x sh4 x32
+libc6_archs   := amd64 arm arm64 armel armhf hppa i386 m68k mips mipsel mipsn32 mipsn32el mips64 mips64el powerpc powerpcel powerpcspe ppc64 ppc64el sparc sparc64 s390x sh4 x32
 libc6_1_archs := alpha
 
 control_deps := $(wildcard debian/control.in/*) $(addprefix debian/control.in/, $(libc_packages))
EOF
		drop_privs ./debian/rules debian/control
	fi
	echo "patching glibc to drop dev package conflict"
	drop_privs patch -p1 <<'EOF'
diff -Nru glibc-2.19/debian/control.in/libc glibc-2.19/debian/control.in/libc
--- glibc-2.19/debian/control.in/libc
+++ glibc-2.19/debian/control.in/libc
@@ -37,7 +37,6 @@
 Suggests: glibc-doc, manpages-dev
 Provides: libc-dev, libc6-dev [alpha hurd-i386 kfreebsd-i386 kfreebsd-amd64]
 Breaks: binutils (<< 2.20.1-1), binutils-gold (<< 2.20.1-11), cmake (<< 2.8.4+dfsg.1-5), gcc-4.4 (<< 4.4.6-4), gcc-4.5 (<< 4.5.3-2), gcc-4.6 (<< 4.6.0-12), make (<< 3.81-8.1), pkg-config (<< 0.26-1), libjna-java (<< 3.2.7-4), liblouis-dev (<< 2.3.0-2), liblouisxml-dev (<< 2.4.0-2), libhwloc-dev (<< 1.2-3), check (<< 0.9.10-6.1+b1) [s390x]
-Conflicts: @libc-dev-conflict@
 Description: GNU C Library: Development Libraries and Header Files
  Contains the symlinks, headers, and object files needed to compile
  and link programs which use the standard C library.
EOF
	echo "patching glibc to move all headers to multiarch locations #798955"
	drop_privs patch -p1 <<'EOF'
--- a/debian/rules.d/build.mk
+++ b/debian/rules.d/build.mk
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
EOF
}
if test -d "$RESULT/${LIBC_NAME}1"; then
	echo "skipping rebuild of $LIBC_NAME stage1"
	apt_get_remove libc6-dev-i386
	dpkg -i "$RESULT/${LIBC_NAME}1/"*.deb
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
				$APT_GET install "gnumach-dev:$HOST_ARCH" "hurd-dev:$HOST_ARCH" "mig$HOST_ARCH_SUFFIX"
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
	test -d "$RESULT" && mkdir "$RESULT/${LIBC_NAME}1"
	if test "$LIBC_NAME" = musl; then
		test -d "$RESULT" && cp -v musl*.deb "$RESULT/${LIBC_NAME}1"
	else
		test -d "$RESULT" && cp -v libc*-dev_*.deb "$RESULT/${LIBC_NAME}1"
	fi
	cd ..
	drop_privs rm -Rf "${LIBC_NAME}1"
fi
progress_mark "$LIBC_NAME stage1 cross build"

# dpkg happily breaks depends when upgrading build arch multilibs to host arch multilibs
apt_get_remove $(dpkg-query -W "lib*gcc*:$(dpkg --print-architecture)" | sed "s/\\s.*//;/:$(dpkg --print-architecture)/d")

if test "$LIBC_NAME" != musl; then

if test -d "$RESULT/gcc2"; then
	echo "skipping rebuild of gcc stage2"
	dpkg -i "$RESULT"/gcc2/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev "libc-dev:$HOST_ARCH" "binutils$HOST_ARCH_SUFFIX"
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	cross_build_setup "gcc-$GCC_VER" gcc2
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		export with_deps_on_target_arch_pkgs=yes
	fi
	export gcc_cv_libc_provides_ssp=yes
	if test "$ENABLE_MULTILIB" = yes; then
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	else
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	fi
	unset with_deps_on_target_arch_pkgs
	unset gcc_cv_libc_provides_ssp
	cd ..
	ls -l
	pickup_packages *.changes
	drop_privs rm -vf ./*multilib*.deb
	dpkg -i *.deb
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage2 gcc package"; exit 1; fi
	if ! drop_privs "$compiler" -x c -c /dev/null -o test.o; then echo "stage2 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage2 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	test -d "$RESULT" && mkdir "$RESULT/gcc2"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc2"
	cd ..
	drop_privs rm -Rf gcc2
fi
progress_mark "cross gcc stage2 build"

if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = hurd; then
if test -d "$RESULT/hurd_2"; then
	echo "skipping rebuild of hurd stage2"
else
	$APT_GET install texinfo debhelper dh-exec autoconf dh-autoreconf gawk flex bison autotools-dev "libc-dev:$HOST_ARCH"
	cross_build_setup hurd hurd_2
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage2
	drop_privs dpkg-buildpackage -B "-a$HOST_ARCH" -Pstage2 -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/hurd_2" && cp -v ./*.deb "$RESULT/hurd_2"
	cd ..
	drop_privs rm -Rf hurd_2
fi
progress_mark "hurd stage2 cross build"
fi

# several undeclared file conflicts such as #745552 or #784015
apt_get_remove $(dpkg-query -W "libc[0-9]*:$(dpkg --print-architecture)" | sed "s/\\s.*//;/:$(dpkg --print-architecture)/d")

if test -d "$RESULT/${LIBC_NAME}2"; then
	echo "skipping rebuild of $LIBC_NAME stage2"
	dpkg -i "$RESULT/${LIBC_NAME}2/"*.deb
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
			$APT_GET install "gnumach-dev:$HOST_ARCH" "hurd-dev:$HOST_ARCH" "mig$HOST_ARCH_SUFFIX"
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
	test -d "$RESULT" && mkdir "$RESULT/${LIBC_NAME}2"
	test -d "$RESULT" && cp libc*-dev_*.deb libc*[0-9]_*_*.deb "$RESULT/${LIBC_NAME}2"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf "${LIBC_NAME}2"
fi
progress_mark "$LIBC_NAME stage2 cross build"

fi # $LIBC_NAME != musl

if test -d "$RESULT/gcc3"; then
	echo "skipping rebuild of gcc stage3"
	dpkg -i "$RESULT"/gcc3/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen systemtap-sdt-dev "binutils$HOST_ARCH_SUFFIX" "libc-dev:$HOST_ARCH"
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	cross_build_setup "gcc-$GCC_VER" gcc3
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		export with_deps_on_target_arch_pkgs=yes
	else
		export WITH_SYSROOT=/
	fi
	export gcc_cv_libc_provides_ssp=yes
	if test "$ENABLE_MULTILIB" = yes; then
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	else
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		drop_privs DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=$GCC_NOLANG" DEB_CROSS_NO_BIARCH=yes dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	fi
	unset with_deps_on_target_arch_pkgs
	unset WITH_SYSROOT
	unset gcc_cv_libc_provides_ssp
	cd ..
	ls -l
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
	touch /usr/include/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH`/include_path_test_header.h
	preproc="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-cpp-$GCC_VER"
	if ! echo '#include "include_path_test_header.h"' | drop_privs "$preproc" -E -; then echo "stage3 gcc fails to search /usr/include/<triplet>"; exit 1; fi
	test -d "$RESULT" && mkdir "$RESULT/gcc3"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc3"
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		compare_native ./*.deb
	fi
	cd ..
	drop_privs rm -Rf gcc3
fi
progress_mark "cross gcc stage3 build"

apt_get_remove libc6-i386 # breaks cross builds

automatic_packages=
add_automatic() { automatic_packages=`set_add "$automatic_packages" "$1"`; }

add_automatic acl

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

add_automatic base-files
add_automatic bash

builddep_build_essential() {
	# g++ dependency needs cross translation
	$APT_GET install debhelper python3
}

add_automatic bzip2

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
   libisl-dev (>= 0.14), libgmp-dev,
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
patch_dash() {
	echo "patching dash to invoke the host arch prefixed strip #665965"
	drop_privs patch -p1 <<'EOF'
diff -u dash-0.5.7/debian/rules dash-0.5.7/debian/rules
--- dash-0.5.7/debian/rules
+++ dash-0.5.7/debian/rules
@@ -8,6 +8,7 @@
 DEB_BUILD_GNU_TYPE =$(shell dpkg-architecture -qDEB_BUILD_GNU_TYPE)
 ifneq ($(DEB_HOST_GNU_TYPE),$(DEB_BUILD_GNU_TYPE))
   CC =$(DEB_HOST_GNU_TYPE)-gcc
+  STRIP =$(DEB_HOST_GNU_TYPE)-strip
 endif

 ifneq (,$(findstring diet,$(DEB_BUILD_OPTIONS)))
EOF
}

add_automatic datefudge
add_automatic db-defaults
add_automatic debianutils
add_automatic dpkg
add_automatic findutils
add_automatic freetype
add_automatic gdbm

add_automatic gmp
patch_gmp() {
	if test "$LIBC_NAME" = musl; then
		echo "patching gmp symbols for musl arch #788411"
		sed -i -r "s/([= ])(\!)?\<(${HOST_ARCH#musl-linux-})\>/\1\2\3 \2musl-linux-\3/" debian/libgmp10.symbols
		# musl does not implement GNU obstack
		sed -i -r 's/(.*_obstack_)/(arch=!musl-linux-any !musleabihf-linux-any)\1/' debian/libgmp10.symbols
	fi
}

add_automatic gnutls28
add_automatic gpm
add_automatic grep
add_automatic groff

add_automatic gzip
buildenv_gzip() {
	if test "$LIBC_NAME" = musl; then
		# this avoids replacing fseeko with a variant that is broken
		echo gl_cv_func_fflush_stdin exported
		export gl_cv_func_fflush_stdin=yes
	fi
}

add_automatic hostname
patch_hostname() {
	echo "patching hostname for musl #787780"
	patch -p1 <<'EOF'
diff -Nru hostname-3.15/Makefile hostname-3.15+nmu1/Makefile
--- hostname-3.15/Makefile
+++ hostname-3.15+nmu1/Makefile
@@ -1,4 +1,4 @@
-CFLAGS+=-O2 -Wall
+CFLAGS+=-O2 -Wall -D_GNU_SOURCE
 
 # uncomment the following line if you want to install to a different base dir.
 #BASEDIR=/mnt/test
@@ -9,7 +9,7 @@
 OBJS=hostname.o
 
 hostname: $(OBJS)
-	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS) -lnsl
+	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS)
 	ln -fs hostname dnsdomainname
 	ln -fs hostname domainname
 	ln -fs hostname ypdomainname
diff -Nru hostname-3.15/hostname.c hostname-3.15+nmu1/hostname.c
--- hostname-3.15/hostname.c
+++ hostname-3.15+nmu1/hostname.c
@@ -37,13 +37,11 @@
 #include <stdio.h>
 #include <unistd.h>
 #include <getopt.h>
-#define __USE_GNU 1
 #include <string.h>
 #include <netdb.h>
 #include <errno.h>
 #include <ctype.h>
 #include <err.h>
-#include <rpcsvc/ypclnt.h>
 
 #define VERSION "3.15"
 
@@ -52,20 +50,19 @@
 char *progname;
 
 /*
- * Return the name of the nis default domain. This is just a wrapper for
- * yp_get_default_domain.  If something goes wrong, program exits.
+ * Return the name of the nis default domain. Same as localdomain below,
+ * but reports failure for unset domain.
  */
 char *
 localnisdomain()
 {
-	char *buf = 0;
+	/* The historical NIS limit is 1024, the limit on Linux is 64.  */
+	static char buf[1025];
 	int myerror = 0;
 
-	myerror = yp_get_default_domain(&buf);
-
-	/* yp_get_default_domain failed, abort. */
-	if (myerror) {
-		printf("%s: %s\n", progname, yperr_string(myerror));
+	myerror = getdomainname(buf, sizeof buf);
+	if (myerror || strcmp(buf, "(none)") == 0) {
+		printf("%s: Local domain name not set\n", progname);
 		exit (1);
 	}
 
EOF
}

builddep_icu() {
	# g++ dependency needs cross translation
	$APT_GET install cdbs debhelper dpkg-dev autotools-dev
}
patch_icu() {
	echo "patching icu to drop gcc-5 dependencies without cross translation"
	sed -i -e '/^[^:]*Depends:/s/\(,\s*g++[^,]*5[^,]*\)\+\(,\|$\)/\2/g' debian/control
}

add_automatic isl

add_automatic keyutils
patch_keyutils() {
	if test "$LIBC_NAME" = musl; then
		echo "patching keyutils to avoid build failure with musl #798157"
		drop_privs tee -a debian/patches/fix-musl-build.patch >/dev/null <<'EOF'
--- a/key.dns_resolver.c
+++ b/key.dns_resolver.c
@@ -56,6 +56,7 @@
 #include <stdlib.h>
 #include <unistd.h>
 #include <time.h>
+#include <limits.h>

 static const char *DNS_PARSE_VERSION = "1.0";
 static const char prog[] = "key.dns_resolver";
EOF
		echo fix-musl-build.patch >> debian/patches/series
		drop_privs quilt push -a
	fi
}

add_automatic kmod

add_automatic krb5
buildenv_krb5() {
	export krb5_cv_attr_constructor_destructor=yes,yes
	export ac_cv_func_regcomp=yes
	export ac_cv_printf_positional=yes
}

add_automatic libatomic-ops
add_automatic libcap2

builddep_libdebian_installer() {
	# check dependency lacks <!nocheck> #787044
	$APT_GET install dpkg-dev debhelper dh-autoreconf doxygen pkg-config
}
patch_libdebian_installer() {
	echo "patching libdebian-installer to support nocheck profile"
	drop_privs patch -p1 <<'EOF'
diff -Nru libdebian-installer-0.101/Makefile.am libdebian-installer-0.101+nmu1/Makefile.am
--- libdebian-installer-0.101/Makefile.am
+++ libdebian-installer-0.101+nmu1/Makefile.am
@@ -1,6 +1,9 @@
 AUTOMAKE_OPTIONS = foreign
 
-SUBDIRS = doc include src test
+SUBDIRS = doc include src
+if ENABLE_CHECK
+SUBDIRS += test
+endif
 
 pkgconfigdir = ${libdir}/pkgconfig
 pkgconfig_DATA = \
diff -Nru libdebian-installer-0.101/configure.ac libdebian-installer-0.101+nmu1/configure.ac
--- libdebian-installer-0.101/configure.ac
+++ libdebian-installer-0.101+nmu1/configure.ac
@@ -7,9 +7,14 @@
 
 AC_CHECK_FUNCS(memrchr)
 
+AC_ARG_ENABLE([check],AS_HELP_STRING([--disable-check],[Disable running the test suite]))
+
 AC_CHECK_PROGS(DOXYGEN, doxygen, true)
 
-PKG_CHECK_MODULES([CHECK], [check >= 0.9.4])
+AS_IF([test "x$enable_check" != xno],[
+	PKG_CHECK_MODULES([CHECK], [check >= 0.9.4])
+])
+AM_CONDITIONAL([ENABLE_CHECK],[test "x$enable_check" != xno])
 
 LIBRARY_VERSION_MAJOR=4
 LIBRARY_VERSION_MINOR=0
diff -Nru libdebian-installer-0.101/debian/control libdebian-installer-0.101+nmu1/debian/control
--- libdebian-installer-0.101/debian/control
+++ libdebian-installer-0.101+nmu1/debian/control
@@ -3,7 +3,7 @@
 Priority: optional
 Maintainer: Debian Install System Team <debian-boot@lists.debian.org>
 Uploaders: Bastian Blank <waldi@debian.org>, Colin Watson <cjwatson@debian.org>, Christian Perrier <bubulle@debian.org>, Steve McIntyre <93sam@debian.org>
-Build-Depends: dpkg-dev (>= 1.13.5), debhelper (>= 9), dh-autoreconf, doxygen, pkg-config, check
+Build-Depends: dpkg-dev (>= 1.13.5), debhelper (>= 9), dh-autoreconf, doxygen, pkg-config, check <!nocheck>
 Standards-Version: 3.9.6
 Vcs-Browser: http://anonscm.debian.org/gitweb/?p=d-i/libdebian-installer.git
 Vcs-Git: git://anonscm.debian.org/d-i/libdebian-installer.git
diff -Nru libdebian-installer-0.101/debian/rules libdebian-installer-0.101+nmu1/debian/rules
--- libdebian-installer-0.101/debian/rules
+++ libdebian-installer-0.101+nmu1/debian/rules
@@ -16,6 +16,11 @@
 
 export CFLAGS
 
+ifneq ($(filter nocheck,$(DEB_BUILD_OPTIONS)),)
+override_dh_auto_configure:
+	dh_auto_configure -- --disable-check
+endif
+
 override_dh_auto_build:
 	dh_auto_build
 	$(MAKE) -C build/doc doc
EOF
}

add_automatic libelf
builddep_libelf() {
	$APT_GET build-dep "-a$1" --arch-only libelf
	$APT_GET install autotools-dev
}
patch_libelf() {
	echo "patching libelf to update config.guess to fix the musl build #799005"
	drop_privs patch -p1 <<'EOF'
--- a/debian/control
+++ b/debian/control
@@ -2,7 +2,7 @@
 Section: devel
 Priority: optional
 Maintainer: Alex Pennace <alex@pennace.org>
-Build-Depends: gettext, debhelper (>= 5), dpkg-dev (>= 1.16)
+Build-Depends: gettext, debhelper (>= 5), dpkg-dev (>= 1.16), autotools-dev
 Standards-Version: 3.6.2.2

 Package: libelfg0
--- a/debian/rules
+++ b/debian/rules
@@ -18,6 +18,7 @@
 build: build-stamp
 build-stamp: 
 	dh_testdir
+	dh_autotools-dev_updateconfig
 	mv po/de.gmo po/de.gmo.orig
 	cp po/de.gmo.orig po/de.gmo
 	# --enable-compat per bug 477025
@@ -39,6 +39,7 @@
 	-make distclean
 # distclean misses w32/Makefile; kludge around it.
 	-rm -f w32/Makefile
+	dh_autotools-dev_restoreconfig
 	dh_clean build-stamp debian/libelfg0-dev.links

 debian/%.links: debian/%.links.in
EOF
}
buildenv_libelf() {
	# gettext.m4 is broken. same as #786885
	if test "$LIBC_NAME" = musl; then
		export mr_cv_gnu_gettext=yes && echo mr_cv_gnu_gettext exported
	fi
}

add_automatic libev
add_automatic libgc

add_automatic libgcrypt20
buildenv_libgcrypt20() {
	export ac_cv_sys_symbol_underscore=no
}

add_automatic libgpg-error
add_automatic libice
add_automatic libonig
add_automatic libpipeline
add_automatic libpng
add_automatic libpthread-stubs
add_automatic libseccomp
add_automatic libsepol
add_automatic libsm
add_automatic libssh2
add_automatic libtasn1-6
add_automatic libtextwrap
add_automatic libunistring
add_automatic libverto

add_automatic libx11
buildenv_libx11() {
	export xorg_cv_malloc0_returns_null=no
}

add_automatic libxau
add_automatic libxaw

add_automatic libxdmcp
buildenv_libxdmcp() {
	# xdmcp.txt.gz is LC_CTYPE dependent and the latest amd64 build happens to use C #783223
	export LC_ALL=C
}

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

add_automatic make-dfsg
add_automatic man-db
add_automatic mawk
add_automatic mpclib3
add_automatic mpfr4
add_automatic nettle
add_automatic nspr

add_automatic nss
patch_nss() {
	if test "$HOST_ARCH" = x32; then
		echo "fixing nss FTBFS on x32 #699217"
		drop_privs patch -p1 <<'EOF'
diff -Nru nss-3.17/debian/rules nss-3.17/debian/rules
--- nss-3.17/debian/rules
+++ nss-3.17/debian/rules
@@ -63,6 +63,7 @@
 	DIST=$(DISTDIR) \
 	OBJDIR_NAME=OBJS \
 	$(and $(filter 64,$(shell dpkg-architecture -qDEB_HOST_ARCH_BITS)),USE_64=1) \
+	$(and $(filter x32,$(DEB_HOST_ARCH)),USE_X32=1) \
 	$(NULL)

 NSS_TOOLS := \
EOF
	fi
}

add_automatic openssl
patch_openssl() {
	echo "fixing cross compilation of openssl for mips* architectures #782492"
	drop_privs patch -p1 <<'EOF'
diff -Nru openssl-1.0.1k/debian/patches/mips-cross.patch openssl-1.0.1k/debian/patches/mips-cross.patch
--- openssl-1.0.1k/debian/patches/mips-cross.patch
+++ openssl-1.0.1k/debian/patches/mips-cross.patch
@@ -0,0 +1,26 @@
+From: Helmut Grohne <helmut@subdivi.de>
+Subject: fix cross compilation for mips architectures
+Last-Update: 2015-04-08
+
+openssl prepends $CROSS_COMPILE to the compiler, so it ends up calling
+"$triplet-$triplet-gcc". Thus drop one triplet.
+
+Index: openssl-1.0.1k/Configure
+===================================================================
+--- openssl-1.0.1k.orig/Configure
++++ openssl-1.0.1k/Configure
+@@ -365,10 +365,10 @@
+ "debian-m68k","gcc:-DB_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG MD2_CHAR RC4_INDEX:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+ "debian-mips",   "gcc:-DB_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+ "debian-mipsel",   "gcc:-DL_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+-"debian-mipsn32",   "mips64-linux-gnuabin32-gcc:-DB_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+-"debian-mipsn32el",   "mips64el-linux-gnuabin32-gcc:-DL_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+-"debian-mips64",   "mips64-linux-gnuabi64-gcc:-DB_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+-"debian-mips64el",   "mips64el-linux-gnuabi64-gcc:-DL_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
++"debian-mipsn32",   "gcc:-DB_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
++"debian-mipsn32el",   "gcc:-DL_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
++"debian-mips64",   "gcc:-DB_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
++"debian-mips64el",   "gcc:-DL_ENDIAN ${debian_cflags}::-D_REENTRANT::-ldl:BN_LLONG RC2_CHAR RC4_INDEX DES_INT DES_UNROLL DES_RISC2:${no_asm}:dlfcn:linux-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+ "debian-netbsd-i386",	"gcc:-DL_ENDIAN ${debian_cflags} -m486::(unknown):::BN_LLONG ${x86_gcc_des} ${x86_gcc_opts}:${no_asm}:dlfcn:bsd-gcc-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+ "debian-netbsd-m68k",	"gcc:-DB_ENDIAN ${debian_cflags}::(unknown):::BN_LLONG MD2_CHAR RC4_INDEX DES_UNROLL:${no_asm}:dlfcn:bsd-gcc-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
+ "debian-netbsd-sparc",	"gcc:-DB_ENDIAN ${debian_cflags} -mv8::(unknown):::BN_LLONG MD2_CHAR RC4_INDEX DES_UNROLL:${no_asm}:dlfcn:bsd-gcc-shared:-fPIC::.so.\$(SHLIB_MAJOR).\$(SHLIB_MINOR)",
EOF
	echo mips-cross.patch >> debian/patches/series
	drop_privs quilt push -a
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
add_automatic readline5
add_automatic rtmpdump
add_automatic sed
add_automatic slang2
add_automatic sqlite3
add_automatic tar

add_automatic tcl8.6
buildenv_tcl8_6() {
	export tcl_cv_strtod_buggy=ok
}

add_automatic tcltk-defaults

add_automatic tk8.6
buildenv_tk8_6() {
	export tcl_cv_strtod_buggy=ok
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
	cat /var/lib/apt/lists/*_Sources > "$source_list"
	errcode=0
	dose-builddebcheck "--deb-native-arch=`dpkg --print-architecture`" "--deb-host-arch=$HOST_ARCH" "$@" "$package_list" "$source_list" || errcode=$?
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

need_packages=
add_need() { need_packages=`set_add "$need_packages" "$1"`; }
built_packages=
mark_built() {
	need_packages=`set_discard "$need_packages" "$1"`
	built_packages=`set_add "$built_packages" "$1"`
}

add_need acl # by coreutils, systemd
add_need attr # by coreutils, libcap-ng, libcap2
add_need base-files # essential
add_need bash # essential
add_need bzip2 # by dpkg, perl
add_need cloog # by gcc-4.9
add_need dash # essential
add_need db-defaults # by apt, perl, python2.7
add_need debianutils # essential
add_need diffutils # essential
add_need dpkg # essential
add_need findutils # essential
add_need freetype # by fontconfig
add_need gdbm # by perl, python2.7
add_need gmp # by guile-2.0
add_need gnutls28 # by curl
add_need gpm # by ncurses
add_need grep # essential
add_need groff # for man-db
add_need gzip # essential
add_need hostname # essential
test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux && add_need kmod # by systemd
add_need krb5 # by curl
add_need libatomic-ops # by gcc-4.9
add_need libcap2 # by systemd
add_need libelf # by systemtap, glib2.0
add_need libgc # by guile-2.0
add_need libgcrypt20 # by libprelude, cryptsetup
add_need libpng # by slang2
add_need libpthread-stubs # by libxcb
if apt-cache showsrc libseccomp | sed 's/^Architecture:\(.*\)/\1 /;t;d' | grep -q " $HOST_ARCH "; then
	add_need libseccomp # by systemd
fi
test "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS`" = linux && add_need libsepol # by libselinux
add_need libssh2 # by curl
add_need libtextwrap # by cdebconf
add_need libunistring # by guile-2.0
add_need libx11 # by dbus
add_need libxau # by libxcb
add_need libxdmcp # by libxcb
add_need libxrender # by cairo
add_need make-dfsg # for build-essential
add_need man-db # for debhelper
add_need mawk # for base-files (alternatively: gawk)
add_need mpclib3 # by gcc-4.9
add_need mpfr4 # by gcc-4.9
add_need nss # by curl
add_need openssl # by curl
add_need patch # for dpkg-dev
add_need pcre3 # by libselinux
add_need readline5 # by lvm2
add_need rtmpdump # by curl
add_need sed # essential
add_need slang2 # by cdebconf, newt
add_need sqlite3 # by python2.7
add_need tar # essential
add_need tcl8.6 # by newt
add_need tcltk-defaults # by python2.7
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
		call_dose_builddebcheck --successes --failures --explain --latest --deb-drop-b-d-indep "--deb-profiles=$profiles" "--checkonly=$need_packages_comma_sep" >"$dosetmp"
		buildable=
		new_needed=
		while IFS= read -r line; do
			case "$line" in
				"  package: src:"*)
					pkg=${line#*src:}
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
	local missing_pkgs missing_pkgs_comma_sep
	missing_pkgs=`set_difference "$1" "$built_packages"`
	test -z "$missing_pkgs" && return 0
	echo "rebootstrap-error: missing asserted packages: $missing_pkgs"
	missing_pkgs=`set_union "$missing_pkgs" "$need_packages"`
	missing_pkgs_comma_sep=`echo $missing_pkgs | sed 's/ /,/g'`
	call_dose_builddebcheck --failures --explain --latest --deb-drop-b-d-indep "--checkonly=$missing_pkgs_comma_sep"
	return 1
}

automatically_cross_build_packages

patch_zlib() {
	echo "patching zlib to support nobiarch build profile #709623"
	drop_privs patch -p1 <<EOF
diff -Nru zlib-1.2.8.dfsg/debian/control zlib-1.2.8.dfsg/debian/control
--- zlib-1.2.8.dfsg/debian/control
+++ zlib-1.2.8.dfsg/debian/control
@@ -4,7 +4,7 @@
 Maintainer: Mark Brown <broonie@debian.org>
 Standards-Version: 3.9.4
 Homepage: http://zlib.net/
-Build-Depends: debhelper (>= 8.1.3~), binutils (>= 2.18.1~cvs20080103-2) [mips mipsel], gcc-multilib [amd64 i386 kfreebsd-amd64 mips mipsel powerpc ppc64 s390 sparc s390x], dpkg-dev (>= 1.16.1)
+Build-Depends: debhelper (>= 8.1.3~), binutils (>= 2.18.1~cvs20080103-2) [mips mipsel], gcc-multilib [amd64 i386 kfreebsd-amd64 mips mipsel powerpc ppc64 s390 sparc s390x] <!nobiarch>, dpkg-dev (>= 1.16.1)
 
 Package: zlib1g
 Architecture: any
@@ -65,6 +65,7 @@
 Architecture: sparc s390 i386 powerpc mips mipsel
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: amd64-libs (<< 1.4)
+Build-Profiles: <!nobiarch>
 Description: compression library - 64 bit runtime
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes a 64 bit version of the
@@ -76,6 +77,7 @@
 Depends: lib64z1 (= \${binary:Version}), zlib1g-dev (= \${binary:Version}), lib64c-dev, \${misc:Depends}
 Replaces: amd64-libs-dev (<< 1.4)
 Provides: lib64z-dev
+Build-Profiles: <!nobiarch>
 Description: compression library - 64 bit development
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes the development support
@@ -86,6 +88,7 @@
 Conflicts: libc6-i386 (<= 2.9-18)
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: ia32-libs (<< 1.5)
+Build-Profiles: <!nobiarch>
 Description: compression library - 32 bit runtime
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes a 32 bit version of the
@@ -98,6 +101,7 @@
 Depends: lib32z1 (= \${binary:Version}), zlib1g-dev (= \${binary:Version}), lib32c-dev, \${misc:Depends}
 Provides: lib32z-dev
 Replaces: ia32-libs-dev (<< 1.5)
+Build-Profiles: <!nobiarch>
 Description: compression library - 32 bit development
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes the development support
@@ -106,6 +110,7 @@
 Package: libn32z1
 Architecture: mips mipsel
 Depends: \${shlibs:Depends}, \${misc:Depends}
+Build-Profiles: <!nobiarch>
 Description: compression library - n32 runtime
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes a n32 version of the shared
@@ -116,6 +121,7 @@
 Architecture: mips mipsel
 Depends: libn32z1 (= \${binary:Version}), zlib1g-dev (= \${binary:Version}), libn32c-dev, \${misc:Depends}
 Provides: libn32z-dev
+Build-Profiles: <!nobiarch>
 Description: compression library - n32 development
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes the development support
diff -Nru zlib-1.2.8.dfsg/debian/rules zlib-1.2.8.dfsg/debian/rules
--- zlib-1.2.8.dfsg/debian/rules
+++ zlib-1.2.8.dfsg/debian/rules
@@ -69,6 +69,11 @@
 mn32=-mabi=n32
 endif
 
+ifneq (,\$(findstring nobiarch,\$(DEB_BUILD_PROFILES)))
+override EXTRA_BUILD=
+override EXTRA_INSTALL=
+endif
+
 UNALIGNED_ARCHS=i386 amd64 kfreebsd-i386 kfreebsd-amd64 hurd-i386 lpia
 ifneq (,\$(findstring \$(DEB_HOST_ARCH), \$(UNALIGNED_ARCHS)))
 CFLAGS+=-DUNALIGNED_OK
EOF
}
builddep_zlib() {
	# gcc-multilib dependency unsatisfiable
	$APT_GET install debhelper binutils dpkg-dev
}
cross_build zlib
mark_built zlib
# needed by dpkg, file, gnutls28, libpng, libtool, libxml2, perl, slang2, tcl8.6, util-linux

automatically_cross_build_packages

builddep_libtool() {
	assert_built "zlib"
	test "$1" = "$HOST_ARCH"
	# gfortran dependency needs cross-translation
	$APT_GET install debhelper texi2html texinfo file "gfortran-$GCC_VER$HOST_ARCH_SUFFIX" automake autoconf autotools-dev help2man "zlib1g-dev:$HOST_ARCH"
}
cross_build libtool
mark_built libtool
# needed by guile-2.0

automatically_cross_build_packages

builddep_ncurses() {
	assert_built gpm
	# g++-multilib dependency unsatisfiable
	$APT_GET install debhelper dpkg-dev "libgpm-dev:$1" pkg-config
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
# needed by bash, bsdmainutils, dpkg, guile-2.0, readline6, slang2

automatically_cross_build_packages

patch_readline6() {
	echo "patching readline6 to support nobiarch profile #737955"
	drop_privs patch -p1 <<EOF
diff -Nru readline6-6.3/debian/control readline6-6.3/debian/control
--- readline6-6.3/debian/control
+++ readline6-6.3/debian/control
@@ -4,11 +4,11 @@
 Maintainer: Matthias Klose <doko@debian.org>
 Standards-Version: 3.9.5
 Build-Depends: debhelper (>= 8.1.3),
-  libtinfo-dev, lib32tinfo-dev [amd64 ppc64],
+  libtinfo-dev, lib32tinfo-dev [amd64 ppc64] <!nobiarch>,
   libncursesw5-dev (>= 5.6),
-  lib32ncursesw5-dev [amd64 ppc64], lib64ncurses5-dev [i386 powerpc sparc s390],
+  lib32ncursesw5-dev [amd64 ppc64] <!nobiarch>, lib64ncurses5-dev [i386 powerpc sparc s390] <!nobiarch>,
   mawk | awk, texinfo, autotools-dev,
-  gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc]
+  gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc] <!nobiarch>
 
 Package: libreadline6
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
diff -Nru readline6-6.3/debian/rules readline6-6.3/debian/rules
--- readline6-6.3/debian/rules	2014-03-19 17:05:34.000000000 +0100
+++ readline6-6.3/debian/rules	2014-05-04 14:46:45.000000000 +0200
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
builddep_readline6() {
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
cross_build readline6
mark_built readline6
# needed by gnupg, guile-2.0, libxml2

automatically_cross_build_packages

builddep_libselinux() {
	assert_built "libsepol pcre3"
	# gem2deb dependency lacks profile annotation
	$APT_GET install debhelper file "libsepol1-dev:$1" "libpcre3-dev:$1" pkg-config
}
if test -d "$RESULT/libselinux1"; then
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
	test -d "$RESULT" && mkdir "$RESULT/libselinux1"
	test -d "$RESULT" && cp *.deb "$RESULT/libselinux1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libselinux1
fi
progress_mark "libselinux stage1 cross build"
mark_built libselinux
# needed by coreutils, dpkg, findutils, glibc, sed, tar, util-linux

automatically_cross_build_packages

builddep_util_linux() {
	assert_built "libselinux ncurses slang2 zlib"
	$APT_GET build-dep "-a$1" --arch-only -P "$2" util-linux
}
if test -d "$RESULT/util-linux_1"; then
	echo "skipping rebuild of util-linux stage1"
else
	builddep_util_linux "$HOST_ARCH" stage1
	cross_build_setup util-linux util-linux_1
	drop_privs scanf_cv_type_modifier=ms dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/util-linux_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/util-linux_1"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf util-linux_1
fi
progress_mark "util-linux stage1 cross build"
mark_built util-linux
# essential, needed by e2fsprogs

automatically_cross_build_packages

builddep_file() {
	assert_built "zlib"
	# python-all lacks build profile annotation #709623
	$APT_GET install debhelper dh-autoreconf "zlib1g-dev:$HOST_ARCH"
}
if test -d "$RESULT/file_1"; then
	echo "skipping stage1 rebuild of file"
else
	builddep_file
	cross_build_setup file file_1
	dpkg-checkbuilddeps "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/file_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/file_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf file_1
fi
progress_mark "file stage1 cross build"
mark_built file
# needed by gcc-4.9, needed for debhelper

automatically_cross_build_packages

builddep_bsdmainutils() {
	assert_built "ncurses"
	# python-hdate dependency unsatisfiable #792867
	$APT_GET install debhelper "libncurses5-dev:$HOST_ARCH" quilt python python-hdate
}
cross_build bsdmainutils
mark_built bsdmainutils
# needed for man-db

automatically_cross_build_packages

builddep_libffi() {
	assert_built "libtool"
	# g++-multilib dependency unsatisfiable
	$APT_GET install debhelper dejagnu lsb-release texinfo dpkg-dev dh-autoreconf "libltdl-dev:$HOST_ARCH"
}
patch_libffi() {
	echo "fixing libffi to run autoreconf for ppc64el"
	drop_privs patch -p1 <<'EOF'
diff -Nru libffi-3.2.1/debian/control libffi-3.2.1/debian/control
--- libffi-3.2.1/debian/control
+++ libffi-3.2.1/debian/control
@@ -5,7 +5,8 @@
 Build-Depends: debhelper (>= 5),
   g++-multilib [amd64 i386 mips mipsel powerpc ppc64 s390 sparc kfreebsd-amd64],
   dejagnu, lsb-release, texinfo,
-  dpkg-dev (>= 1.16.0~ubuntu4)
+  dpkg-dev (>= 1.16.0~ubuntu4),
+  dh-autoreconf, libltdl-dev
 Standards-Version: 3.9.6
 Section: libs
 
diff -Nru libffi-3.2.1/debian/rules libffi-3.2.1/debian/rules
--- libffi-3.2.1/debian/rules
+++ libffi-3.2.1/debian/rules
@@ -39,6 +39,7 @@
 	dh_testdir
 	rm -rf build
 	mkdir -p build
+	dh_autoreconf
 	cd build && ../configure \
 		--host=$(DEB_HOST_GNU_TYPE) \
 		--build=$(DEB_BUILD_GNU_TYPE) \
@@ -75,6 +76,7 @@
 	rm -f stamp-*
 	rm -rf build*
 	rm -f doc/libffi.info
+	dh_autoreconf_clean
 	dh_clean 
 
 install: build
EOF
}
cross_build libffi
mark_built libffi
# needed by guile-2.0, p11-kit

automatically_cross_build_packages

builddep_guile_2_0() {
	assert_built "gmp libffi libgc libtool libunistring ncurses readline6"
	$APT_GET build-dep --arch-only "-a$1" guile-2.0
	$APT_GET install guile-2.0 # needs Build-Depends: guile-2.0 <cross>
}
cross_build guile-2.0
mark_built guile-2.0
# needed by gnutls28, make-dfsg, autogen

automatically_cross_build_packages

builddep_flex() {
	$APT_GET build-dep "-a$1" --arch-only flex
	$APT_GET install flex # needs Build-Depends: flex <profile.cross>
}
patch_flex() {
	echo "patching flex to not run host arch executables #762180"
	drop_privs patch -p1 <<'EOF'
diff -Nru flex-2.5.39/debian/patches/help2man-cross.patch flex-2.5.39/debian/patches/help2man-cross.patch
--- flex-2.5.39/debian/patches/help2man-cross.patch
+++ flex-2.5.39/debian/patches/help2man-cross.patch
@@ -0,0 +1,32 @@
+From: Helmut Grohne <helmut@subdivi.de>
+Subject: Run help2man on the system copy of flex when cross building
+Last-Modified: 2014-09-18
+
+Index: flex-2.5.39/configure.ac
+===================================================================
+--- flex-2.5.39.orig/configure.ac
++++ flex-2.5.39/configure.ac
+@@ -50,6 +50,12 @@
+ 
+ AC_PATH_PROG(BISON, bison,bison)
+ AC_PATH_PROG(HELP2MAN, help2man, help2man)
++if test "$cross_compiling" = yes; then
++FLEXexe='flex$(EXEEXT)'
++else
++FLEXexe='$(top_builddir)/flex$(EXEEXT)'
++fi
++AC_SUBST(FLEXexe)
+ 
+ # Check for a m4 that supports -P
+ 
+Index: flex-2.5.39/doc/Makefile.am
+===================================================================
+--- flex-2.5.39.orig/doc/Makefile.am
++++ flex-2.5.39/doc/Makefile.am
+@@ -27,5 +27,5 @@
+ 	for i in $(dist_man_MANS) ; do \
+ 	$(help2man) --name='$(PACKAGE_NAME)' \
+ 	--section=`echo $$i | sed -e 's/.*\.\([^.]*\)$$/\1/'` \
+-	 ../flex$(EXEEXT) > $$i || rm -f $$i ; \
++	 $(FLEXexe) > $$i || rm -f $$i ; \
+ 	done
diff -Nru flex-2.5.39/debian/patches/series flex-2.5.39/debian/patches/series
--- flex-2.5.39/debian/patches/series
+++ flex-2.5.39/debian/patches/series
@@ -4,3 +4,4 @@
 0003-ia64-buffer-fix-Some-more-fixes-for-the-ia64-buffer-.patch
 0004-bison-test-fixes-Do-not-use-obsolete-bison-construct.patch
 0005-fix-off-by-one-error-generatred-line-numbers-are-off.patch
+help2man-cross.patch
EOF
}
cross_build flex
mark_built flex
# needed by pam

automatically_cross_build_packages

builddep_glib2_0() {
	assert_built "libelf libffi libselinux pcre3 zlib" # also linux-libc-dev
	# python-dbus dependency unsatisifable
	$APT_GET install debhelper cdbs dh-autoreconf pkg-config gettext autotools-dev gnome-pkg-tools dpkg-dev "libelfg0-dev:$1" "libpcre3-dev:$1" desktop-file-utils gtk-doc-tools "libselinux1-dev:$1" "linux-libc-dev:$1" "zlib1g-dev:$1" dbus dbus-x11 shared-mime-info xterm python python-dbus python-gi libxml2-utils "libffi-dev:$1"
}
buildenv_glib2_0() {
	export glib_cv_stack_grows=no
	export glib_cv_uscore=no
	export ac_cv_func_posix_getgrgid_r=yes
	export ac_cv_func_posix_getpwuid_r=yes
}
patch_glib2_0() {
	echo "patching glib2.0 to fix cross compilation"
	drop_privs patch -p1 <<'EOF'
--- a/gio/tests/Makefile.am
+++ b/gio/tests/Makefile.am
@@ -71,9 +71,12 @@
 	$(NULL)

 test_data = \
-	test.gresource				\
 	$(NULL)

+if !CROSS_COMPILING
+test_data += test.gresource
+endif
+
 uninstalled_test_extra_programs = \
 	gio-du					\
 
EOF
}
cross_build glib2.0
mark_built glib2.0
# needed by pkg-config, dbus, systemd, libxt

automatically_cross_build_packages

builddep_libxcb() {
	assert_built "libxau libxdmcp libpthread-stubs"
	# check dependency lacks nocheck profile annotation
	# python dependency lacks :native annotation #788861
	$APT_GET install "libxau-dev:$1" "libxdmcp-dev:$1" xcb-proto "libpthread-stubs0-dev:$1" debhelper pkg-config xsltproc  python-xcbgen libtool automake python dctrl-tools
}
cross_build libxcb
mark_built libxcb
# needed by libx11

automatically_cross_build_packages

patch_expat() {
	echo "patching expat to add nobiarch build profile #779459"
	drop_privs patch -p1 <<'EOF'
diff -Nru expat-2.1.0/debian/control expat-2.1.0/debian/control
--- expat-2.1.0/debian/control
+++ expat-2.1.0/debian/control
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
diff -Nru expat-2.1.0/debian/rules expat-2.1.0/debian/rules
--- expat-2.1.0/debian/rules
+++ expat-2.1.0/debian/rules
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
diff -Nru expat-2.1.0/debian/rules expat-2.1.0/debian/rules
--- expat-2.1.0/debian/rules
+++ expat-2.1.0/debian/rules
@@ -32,6 +32,10 @@
 	HOST64FLAG = --host=s390x-linux-gnu
 endif
 
+ifeq ($(origin CC),default)
+CC = $(DEB_HOST_GNU_TYPE)-cc
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
	# gcc-multilib lacks nobiarch profile
	$APT_GET install debhelper docbook-to-man dh-autoreconf dpkg-dev
}
cross_build expat
mark_built expat
# needed by fontconfig

automatically_cross_build_packages

builddep_fontconfig() {
	assert_built "expat freetype"
	# versioned dependency on binutils needs cross-translation #779460
	$APT_GET install cdbs dh-autoreconf debhelper "libfreetype6-dev:$1" "libexpat1-dev:$1" pkg-config gperf po-debconf
}
patch_fontconfig() {
	echo "patching fontconfig to use the build compiler #779461"
	drop_privs patch -p1 <<'EOF'
diff -Nru fontconfig-2.11.0/debian/patches/06_cross.patch fontconfig-2.11.0/debian/patches/06_cross.patch
--- fontconfig-2.11.0/debian/patches/06_cross.patch
+++ fontconfig-2.11.0/debian/patches/06_cross.patch
@@ -0,0 +1,16 @@
+Index: fontconfig-2.11.0/doc/Makefile.am
+===================================================================
+--- fontconfig-2.11.0.orig/doc/Makefile.am
++++ fontconfig-2.11.0/doc/Makefile.am
+@@ -121,7 +121,10 @@
+ edit_sgml_SOURCES =	\
+ 	edit-sgml.c	\
+ 	$(NULL)
+-edit_sgml_CC = $(CC_FOR_BUILD)
++$(edit_sgml_OBJECTS) : CC=$(CC_FOR_BUILD)
++$(edit_sgml_OBJECTS) : CFLAGS=$(CFLAGS_FOR_BUILD)
++$(edit_sgml_OBJECTS) : CPPFLAGS=$(CPPFLAGS_FOR_BUILD)
++edit_sgml_LINK = $(CC_FOR_BUILD) -o $@
+ #
+ check_SCRIPTS =			\
+ 	check-missing-doc	\
diff -Nru fontconfig-2.11.0/debian/patches/series fontconfig-2.11.0/debian/patches/series
--- fontconfig-2.11.0/debian/patches/series
+++ fontconfig-2.11.0/debian/patches/series
@@ -3,3 +3,4 @@
 03_locale_c.utf8.patch
 04_mgopen_fonts.patch
 05_doc_files.patch
+06_cross.patch
EOF
	drop_privs quilt push -a
}
cross_build fontconfig
mark_built fontconfig
# needed by cairo, xft

automatically_cross_build_packages

builddep_db5_3() {
	# java stuff lacks build profile annotation
	$APT_GET install debhelper autotools-dev procps
}
if test -d "$RESULT/db5.3_1"; then
	echo "skipping stage1 rebuild of db5.3"
else
	builddep_db5_3 "$HOST_ARCH"
	cross_build_setup db5.3 db5.3_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" || : # tell unmet build depends
	drop_privs DEB_STAGE=stage1 dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/db5.3_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/db5.3_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf db5.3_1
fi
progress_mark "db5.3 stage1 cross build"
mark_built db5.3
# needed by perl, python2.7, needed for db-defaults

automatically_cross_build_packages

builddep_libidn() {
	# gcj-jdk dependency lacks build profile annotation
	$APT_GET install debhelper
}
if test -d "$RESULT/libidn_1"; then
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
	test -d "$RESULT" && mkdir "$RESULT/libidn_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/libidn_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libidn_1
fi
progress_mark "libidn stage1 cross build"
mark_built libidn
# needed by gnutls28

automatically_cross_build_packages

cross_build icu
mark_built icu
# needed by libxml2

automatically_cross_build_packages

builddep_libxml2() {
	assert_built "icu readline6 xz-utils zlib"
	# python-all-dev dependency lacks profile annotation
	# icu-dev-tools wrongly declared m-a:foreign #776821
	$APT_GET install debhelper perl dh-autoreconf autotools-dev "zlib1g-dev:$1" "liblzma-dev:$1" "libreadline6-dev:$1" "libicu-dev:$1" "icu-devtools:$1"
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
if test -d "$RESULT/libxml2_1"; then
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
	test -d "$RESULT" && mkdir "$RESULT/libxml2_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/libxml2_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf libxml2_1
fi
progress_mark "libxml2 stage1 cross build"
mark_built libxml2
# needed by autogen

automatically_cross_build_packages

builddep_autogen() {
	assert_built "guile-2.0 libxml2"
	$APT_GET build-dep "-a$1" --arch-only autogen
	$APT_GET install autogen # needs Build-Depends: autogen <cross>
}
buildenv_autogen() {
	export libopts_cv_with_libregex=yes
}
cross_build autogen
mark_built autogen
# needed by gnutls28, gcc-4.9

automatically_cross_build_packages

builddep_cracklib2() {
	# python-all-dev lacks build profile annotation
	$APT_GET install autoconf automake autotools-dev chrpath debhelper docbook-utils docbook-xml dpkg-dev libtool python dh-python
	# additional B-D for cross
	$APT_GET install cracklib-runtime
}
patch_cracklib2() {
	echo "patching cracklib2 to use build arch cracklib-packer #792860"
	drop_privs patch -p1 <<'EOF'
diff -Nru cracklib2-2.9.2/debian/control cracklib2-2.9.2/debian/control
--- cracklib2-2.9.2/debian/control
+++ cracklib2-2.9.2/debian/control
@@ -8,6 +8,7 @@
                automake (>= 1.10),
                autotools-dev,
                chrpath,
+               cracklib-runtime:native <cross>,
                debhelper (>= 9),
                docbook-utils,
                docbook-xml,
diff -Nru cracklib2-2.9.2/debian/rules cracklib2-2.9.2/debian/rules
--- cracklib2-2.9.2/debian/rules
+++ cracklib2-2.9.2/debian/rules
@@ -17,6 +17,12 @@
 NOPYTHON_OPTIONS = -Npython-cracklib -Npython3-cracklib
 endif
 
+ifeq ($(DEB_HOST_GNU_TYPE),$(DEB_BUILD_GNU_TYPE))
+CRACKLIB_PACKER=$(CURDIR)/debian/buildtmp/base/util/cracklib-packer
+else
+CRACKLIB_PACKER=/usr/sbin/cracklib-packer
+endif
+
 override_dh_auto_configure:
 	aclocal && libtoolize && automake --add-missing && autoreconf
 	mkdir -p $(CURDIR)/debian/buildtmp/base
@@ -57,7 +63,7 @@
 override_dh_auto_test:
 	mkdir $(CURDIR)/debian/tmp
 ifneq ($(DEB_STAGE),stage1)
-	$(CURDIR)/debian/buildtmp/base/util/cracklib-packer $(CURDIR)/debian/tmp/cracklib_dict < \
+	$(CRACKLIB_PACKER) $(CURDIR)/debian/tmp/cracklib_dict < \
 	 $(CURDIR)/dicts/cracklib-small
 	for i in $(PYVERS) $(PY3VERS); do \
 		cd $(CURDIR)/debian/buildtmp/python$$i/python/$(call py_builddir_sh,$$i); \
@@ -91,7 +97,7 @@
 	      $(CURDIR)/debian/libcrack2-udeb/usr/lib/$(DEB_HOST_MULTIARCH)
 	cp -r $(CURDIR)/debian/libcrack2/usr/share/locale/* \
 	      $(CURDIR)/debian/libcrack2-udeb/usr/share/locale
-	$(CURDIR)/debian/buildtmp/base/util/cracklib-packer $(CURDIR)/debian/libcrack2-udeb/var/cache/cracklib/cracklib_dict < \
+	$(CRACKLIB_PACKER) $(CURDIR)/debian/libcrack2-udeb/var/cache/cracklib/cracklib_dict < \
 	    $(CURDIR)/dicts/cracklib-small
 	# move files to libcrack2-dev
 	mkdir -p $(CURDIR)/debian/libcrack2-dev/usr/lib/$(DEB_HOST_MULTIARCH)
EOF
}
if test -d "$RESULT/cracklib2_1"; then
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
	test -d "$RESULT" && mkdir "$RESULT/cracklib2_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/cracklib2_1/"
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
	assert_built "cracklib2 db-defaults db5.3 flex libselinux"
	$APT_GET install "libcrack2-dev:$1" bzip2 debhelper quilt flex "libdb-dev:$1" "libselinux1-dev:$1" po-debconf dh-autoreconf autopoint pkg-config
	# flex wrongly declares M-A:foreign #761449
	$APT_GET install flex "libfl-dev:$1"
}
if test -d "$RESULT/pam_1"; then
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
	test -d "$RESULT" && mkdir "$RESULT/pam_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/pam_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf pam_1
fi
progress_mark "pam stage1 cross build"
mark_built pam
# needed by shadow

automatically_cross_build_packages

cross_build libdebian-installer
mark_built libdebian-installer
# needed by cdebconf

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
@@ -0,0 +1,37 @@
+Description: fix cross compialtion
+Author: Helmut Grohne <helmut@subdivi.de>
+
+ * makemd5 needs to be built with the build arch compiler, because it is run
+   during build and not installed.
+ * Remove SASL_DB_LIB as it expands to -ldb and make fails to find a build arch
+   -ldb.
+
+Index: cyrus-sasl2-2.1.26.dfsg1/include/Makefile.am
+===================================================================
+--- cyrus-sasl2-2.1.26.dfsg1.orig/include/Makefile.am
++++ cyrus-sasl2-2.1.26.dfsg1/include/Makefile.am
+@@ -51,6 +51,11 @@
+ 
+ makemd5_SOURCES = makemd5.c
+ 
++$(makemd5_OBJECTS): CC=cc
++$(makemd5_OBJECTS): CFLAGS=$(CFLAGS_FOR_BUILD)
++$(makemd5_OBJECTS): CPPFLAGS=$(CPPFLAGS_FOR_BUILD)
++makemd5_LINK = cc -o $@
++
+ md5global.h: makemd5
+ 	-rm -f md5global.h
+ 	./makemd5 md5global.h
+Index: cyrus-sasl2-2.1.26.dfsg1/sasldb/Makefile.am
+===================================================================
+--- cyrus-sasl2-2.1.26.dfsg1.orig/sasldb/Makefile.am
++++ cyrus-sasl2-2.1.26.dfsg1/sasldb/Makefile.am
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
@@ -25,6 +25,10 @@
 include /usr/share/dpkg/buildflags.mk
 
 DEB_HOST_MULTIARCH ?= $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)
+DEB_HOST_GNU_TYPE ?= $(shell dpkg-architecture -qDEB_HOST_GNU_TYPE)
+ifeq ($(origin CC),default)
+export CC=$(DEB_HOST_GNU_TYPE)-gcc
+endif
 
 # Save Berkeley DB used for building the package
 BDB_VERSION ?= $(shell LC_ALL=C dpkg-query -l 'libdb[45].[0-9]-dev' | grep ^ii | sed -e 's|.*\s\libdb\([45]\.[0-9]\)-dev\s.*|\1|')
diff -Nru cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile
--- cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile
+++ cyrus-sasl2-2.1.26.dfsg1/debian/sample/Makefile
@@ -7,7 +7,7 @@
 all: sample-server sample-client
 
 sample-server: sample-server.c
-	gcc -g -o sample-server sample-server.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
+	$(CC) -g -o sample-server sample-server.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
 
 sample-client: sample-client.c
-	gcc -g -o sample-client sample-client.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
+	$(CC) -g -o sample-client sample-client.c -I. -I$(T) -I$(INCDIR1) -I$(INCDIR2) -L$(LIBDIR) -lsasl2
EOF
	echo cross.patch | drop_privs tee -a debian/patches/series >/dev/null
	drop_privs quilt push -a
}
if test -d "$RESULT/cyrus-sasl2_1"; then
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
	test -d "$RESULT" && mkdir "$RESULT/cyrus-sasl2_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/cyrus-sasl2_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf cyrus-sasl2_1
fi
progress_mark "cyrus-sasl2 stage1 cross build"
mark_built cyrus-sasl2
# needed by openldap

automatically_cross_build_packages

if test -d "$RESULT/openldap_1"; then
	echo "skipping stage1 rebuild of openldap"
else
	$APT_GET build-dep "-a$HOST_ARCH" --arch-only -P stage1 openldap
	cross_build_setup openldap openldap_1
	check_binNMU
	dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1 || : # tell unmet build depends
	drop_privs ol_cv_pthread_select_yields=yes ac_cv_func_memcmp_working=yes dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/openldap_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/openldap_1/"
	compare_native ./*.deb
	cd ..
	drop_privs rm -Rf openldap_1
fi
progress_mark "openldap stage1 cross build"
mark_built openldap
# needed by curl

automatically_cross_build_packages

if test "$(dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS)" = linux; then
if test -d "$RESULT/systemd_1"; then
	echo "skipping stage1 rebuild of systemd"
else
	$APT_GET build-dep "-a$HOST_ARCH" --arch-only -P nocheck,noudeb,stage1 systemd
	cross_build_setup systemd systemd_1
	check_binNMU
	drop_privs ac_cv_func_malloc_0_nonnull=yes dpkg-buildpackage "-a$HOST_ARCH" -B -uc -us -Pnocheck,noudeb,stage1
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/systemd_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/systemd_1/"
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
	assert_built "util-linux"
	# dietlibc-dev lacks build profile annotation
	$APT_GET install gettext texinfo pkg-config debhelper "libblkid-dev:$1" "uuid-dev:$1" m4
}
cross_build e2fsprogs
mark_built e2fsprogs
# essential

automatically_cross_build_packages

builddep_libusb() {
	# docbook dependency unsatisfiable
	$APT_GET install debhelper dh-autoreconf pkg-config docbook docbook-dsssl
}
cross_build libusb
mark_built libusb
# needed by gnupg

automatically_cross_build_packages

assert_built "$need_packages"
