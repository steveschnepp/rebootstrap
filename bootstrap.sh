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
APT_GET="apt-get --no-install-recommends -y -o Debug::pkgProblemResolver=true -o Debug::pkgDepCache::Marker=1 -o Debug::pkgDepCache::AutoInstall=1"
DEFAULT_PROFILES=cross
LIBC_NAME=glibc
DROP_PRIVS=buildd
GCC_NOLANG=d,go,java,jit,objc,objc++
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
		*" version 1 (SYSV),"*|*", version 1 (GNU/Linux), "*)
			if test linux != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_OS`; then
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
		*", MIPS, MIPS-II version "*|*", MIPS, MIPS-I version "*)
			case `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU` in
				mips|mipsel) ;;
				*)
					echo "cpu mismatch"
					echo "expected $2"
					echo "got $FILE_RES"
					return 1
				;;
			esac
		;;
		*", MIPS, MIPS-III version "*|*", MIPS, MIPS64 version "*)
			if test mips64el != "`dpkg-architecture "-a$2" -qDEB_HOST_ARCH_CPU`"; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
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
		*", PA-RISC, version "*)
			if test hppa != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
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

apt-get update
$APT_GET install pinentry-curses # avoid installing pinentry-gtk (via reprepro)
$APT_GET install build-essential debhelper reprepro

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
	$APT_GET install quilt
	if test "$GCC_VER" = 5; then
		echo "deb $MIRROR experimental main" > /etc/apt/sources.list.d/tmp-experimental.list
		apt-get update
		$APT_GET -t experimental install cross-gcc-dev
		rm /etc/apt/sources.list.d/tmp-experimental.list
		apt-get update
	else
		$APT_GET install cross-gcc-dev
	fi
fi

obtain_source_package() {
	drop_privs apt-get source "$1"
}

# work around dpkg bug #764216
sed -i 's/^\(use Dpkg::BuildProfiles qw(get_build_profiles\));$/\1 parse_build_profiles evaluate_restriction_formula);/' /usr/bin/dpkg-genchanges

if test -z "$HOST_ARCH" || ! dpkg-architecture "-a$HOST_ARCH"; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
fi
export PKG_CONFIG_LIBDIR="/usr/lib/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH`/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
	test -f "$f" && sed -i "s/^deb /deb [ arch-=$HOST_ARCH ] /" $f
done
grep -q '^deb-src ' /etc/apt/sources.list || echo "deb-src $MIRROR sid main" >> /etc/apt/sources.list

dpkg --add-architecture $HOST_ARCH
apt-get update

if test -z "$GCC_VER"; then
	GCC_VER=`apt-cache depends gcc | sed 's/^ *Depends: gcc-\([0-9.]*\)$/\1/;t;d'`
fi

rmdir /tmp/buildd || :
drop_privs mkdir -p /tmp/buildd
drop_privs mkdir -p "$RESULT"

HOST_ARCH_SUFFIX="-`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE | tr _ -`"

mkdir -p "$REPODIR/conf"
mkdir "$REPODIR/archive"
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
apt-get update

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
	$APT_GET install debbindiff binutils-multiarch vim-common
	compare_native() {
		local pkg pkgname tmpdir downloadname errcode
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
	apt-get update
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
		for f in `reprepro --list-format '${Filename}\n'  listfilter rebootstrap "Source (= $source)"`; do
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

cross_build() {
	local pkg profiles ignorebd hook
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
			if dpkg-checkbuilddeps -a$HOST_ARCH -P "$profiles"; then
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
		)
		cd ..
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
patch_gcc_4_8() {
	echo "patching gcc-4.8 to build common libraries. not a bug"
	drop_privs patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/rules.defs gcc-4.8-4.8.2/debian/rules.defs
--- gcc-4.8-4.8.2/debian/rules.defs
+++ gcc-4.8-4.8.2/debian/rules.defs
@@ -343,11 +343,6 @@
 # XXX: should with_common_libs be "yes" only if this is the default compiler
 # version on the targeted arch?
 
-ifeq (,\$(filter \$(distrelease),lenny etch squeeze wheezy dapper hardy jaunty karmic lucid maverick oneiric precise quantal raring saucy trusty))
-  with_common_pkgs :=
-  with_common_libs :=
-endif
-
 # is this a multiarch-enabled build?
 ifeq (,\$(filter \$(distrelease),lenny etch squeeze dapper hardy jaunty karmic lucid maverick))
   with_multiarch_lib := yes
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
if test -f "`echo $RESULT/binutils${HOST_ARCH_SUFFIX}_*.deb`"; then
	echo "skipping rebuild of binutils-target"
else
	$APT_GET install autoconf bison flex gettext texinfo dejagnu quilt python3 file lsb-release zlib1g-dev
	cross_build_setup binutils
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
	cross_build_setup binutils binutils-hppa64
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
	if test "$(dpkg-query -W -f '${Version}' "linux-libc-dev:$(dpkg --print-architecture)")" != "$(dpkg-parsechangelog -SVersion)"; then
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

# gcc
if test -d "$RESULT/gcc1"; then
	echo "skipping rebuild of gcc stage1"
	apt_get_remove gcc-multilib
	dpkg -i $RESULT/gcc1/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev binutils-multiarch "binutils$HOST_ARCH_SUFFIX" "linux-libc-dev:$HOST_ARCH"
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
-	install -m 644 \$(DEB_BUILDDIR)/csu/crt[1in].o \$(CURDIR)/debian/tmp-\$(curpass)/lib
+	install -d \$(CURDIR)/debian/tmp-\$(curpass)/\$(call xx,libdir)
+	install -m 644 \$(DEB_BUILDDIR)/csu/crt[1in].o \\
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
+Depends: @nobootstrap@ libc6-amd64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-armel (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-armhf (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-i386 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc0.1-i386 (= ${binary:Version}), libc0.1-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ @libc@ (= ${binary:Version}), libc-dev-bin (= ${binary:Version}), ${misc:Depends}, linux-libc-dev [linux-any], kfreebsd-kernel-headers (>= 0.11) [kfreebsd-any], gnumach-dev [hurd-i386], hurd-dev (>= 20080607-3) [hurd-i386]
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
+Depends: libc6-dev (= ${binary:Version}), @nobootstrap@ libc6-mips32 (= ${binary:Version}),
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
+Depends: @nobootstrap@ libc6-mips64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-mipsn32 (= ${binary:Version}), @nobootstrap@ libc6-dev-mips64 (= ${binary:Version}) [mips mipsel], libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-powerpc (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-ppc64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-s390 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-sparc (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-sparc64 (= ${binary:Version}), libc6-dev (= ${binary:Version}), ${misc:Depends}
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
+Depends: @nobootstrap@ libc6-x32 (= ${binary:Version}), libc6-dev-i386 (= ${binary:Version}) [amd64], libc6-dev-amd64 (= ${binary:Version}) [i386], libc6-dev (= ${binary:Version}), ${misc:Depends}
 Build-Profiles: <!nobiarch>
 Description: GNU C Library: X32 ABI Development Libraries for AMD64
  Contains the symlinks and object files needed to compile and link programs
  which use the standard C library. This is the X32 ABI version of the
diff -Nru glibc-2.19/debian/rules.d/control.mk glibc-2.19/debian/rules.d/control.mk
--- glibc-2.19/debian/rules.d/control.mk
+++ glibc-2.19/debian/rules.d/control.mk
@@ -43,6 +43,10 @@
 	cat debian/control.in/opt		>> $@T
 	cat debian/control.in/libnss-dns-udeb	>> $@T
 	cat debian/control.in/libnss-files-udeb	>> $@T
-	sed -e 's%@libc@%$(libc)%g' < $@T > debian/control
+ifneq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
+	sed -e 's%@libc@%$(libc)%g;s%@nobootstrap@[^,]*,%%g' < $@T > debian/control
+else
+	sed -e 's%@libc@%$(libc)%g;s%@nobootstrap@%%g' < $@T > debian/control
+endif
 	rm $@T
 	touch $@
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
}
if test -d "$RESULT/${LIBC_NAME}1"; then
	echo "skipping rebuild of $LIBC_NAME stage1"
	apt_get_remove libc6-dev-i386
	dpkg -i "$RESULT/${LIBC_NAME}1/"*.deb
else
	if test "$LIBC_NAME" = musl; then
		$APT_GET build-dep "-a$HOST_ARCH" --arch-only musl
	elif test "$ENABLE_MULTIARCH_GCC" = yes; then
		$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase "linux-libc-dev:$HOST_ARCH" "gcc-$GCC_VER$HOST_ARCH_SUFFIX"
	else
		$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase "linux-libc-dev-$HOST_ARCH-cross" "gcc-$GCC_VER$HOST_ARCH_SUFFIX"
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
		pickup_packages *.changes
		if test "$LIBC_NAME" = musl; then
			dpkg -i musl*.deb
		else
			dpkg -i libc*.deb
		fi
	else
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
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev "libc-dev:$HOST_ARCH" binutils-multiarch "binutils$HOST_ARCH_SUFFIX"
	if test "$HOST_ARCH" = hppa; then
		$APT_GET install binutils-hppa64-linux-gnu
	fi
	cross_build_setup "gcc-$GCC_VER" gcc2
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	echo "$HOST_ARCH" > debian/target
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		export with_deps_on_target_arch_pkgs=yes
	else
		export gcc_cv_libc_provides_ssp=yes
	fi
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

# several undeclared file conflicts such as #745552 or #784015
apt_get_remove $(dpkg-query -W "libc[0-9]*:$(dpkg --print-architecture)" | sed "s/\\s.*//;/:$(dpkg --print-architecture)/d")

if test -d "$RESULT/${LIBC_NAME}2"; then
	echo "skipping rebuild of $LIBC_NAME stage2"
	dpkg -i "$RESULT/${LIBC_NAME}2/"*.deb
else
	$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase linux-libc-dev:$HOST_ARCH
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
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen systemtap-sdt-dev binutils-multiarch "binutils$HOST_ARCH_SUFFIX" "libc-dev:$HOST_ARCH"
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
	cd ..
	ls -l
	pickup_packages *.changes
	drop_privs rm -fv gcc-*-plugin-*.deb gcj-*.deb gdc-*.deb ./*objc*.deb ./*-dbg_*.deb
	dpkg -i *.deb
	apt-get check # test for #745036
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
add_automatic build-essential
add_automatic bzip2

add_automatic check
patch_check() {
	echo "fixing check to support cross compilation"
	drop_privs patch -p1 <<'EOF'
diff -Nru check-0.9.10/debian/rules check-0.9.10/debian/rules
--- check-0.9.10/debian/rules
+++ check-0.9.10/debian/rules
@@ -6,6 +6,7 @@
 export DESTDIR=$(shell pwd)/debian/check
 
 DEB_HOST_MULTIARCH ?= $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)
+DEB_HOST_GNU_TYPE ?= $(shell dpkg-architecture -qDEB_HOST_GNU_TYPE)
 
 ifneq (,$(filter noopt,$(DEB_BUILD_OPTIONS)))
 	CFLAGS_OPT := -O0
@@ -18,6 +19,7 @@
 	dh_testdir
 	dh_autotools-dev_updateconfig
 	 CFLAGS="$(CFLAGS_OPT)" ./configure --prefix=/usr \
+		--host=$(DEB_HOST_GNU_TYPE) \
 		--libdir=\$${prefix}/lib/$(DEB_HOST_MULTIARCH) \
 		--infodir=/usr/share/info --enable-plain-docdir
 	touch configure-stamp
@@ -27,6 +29,7 @@
 	dh_testdir
 	dh_autotools-dev_updateconfig
 	CFLAGS="-fPIC $(CFLAGS_OPT)" ./configure --prefix=/usr \
+		--host=$(DEB_HOST_GNU_TYPE) \
 		--libdir=\$${prefix}/lib/$(DEB_HOST_MULTIARCH) \
 		--infodir=/usr/share/info \
 		--enable-plain-docdir
EOF
	if test "$HOST_ARCH" = s390x -a "$(dpkg-parsechangelog -SVersion)" = "0.9.10-6.1"; then
		echo "binNMUing check to avoid glibc conflict"
		add_binNMU_changelog 1 "avoid glibc conflict"
	fi
}

add_automatic cloog
add_automatic dash
add_automatic db-defaults
add_automatic debianutils
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

add_automatic icu
patch_icu() {
	echo "patching icu for cross compilation #784668"
	drop_privs patch -p1 <<'EOF'
diff -Nru icu-52.1/debian/rules icu-52.1/debian/rules
--- icu-52.1/debian/rules
+++ icu-52.1/debian/rules
@@ -26,6 +26,23 @@
 CXXFLAGS := $(filter-out -O%,$(CXXFLAGS)) -O0
 endif
 
+DEB_BUILDDIR = build
+DEB_MAKE_FLAVORS = hostarch
+ifneq ($(DEB_HOST_ARCH),$(DEB_BUILD_ARCH))
+DEB_MAKE_FLAVORS += buildarch
+DEB_CONFIGURE_FLAGS_buildarch = --host=$(DEB_BUILD_GNU_TYPE)
+DEB_CONFIGURE_FLAGS_hostarch = --with-cross-build=$(CURDIR)/build/buildarch
+debian/stamp-autotools/buildarch: DEB_CONFIGURE_CROSSBUILD_ARGS=
+# do not force a cross compiler for the native build
+debian/stamp-makefile-build/buildarch: DEB_MAKE_ENVVARS=
+# do not install the buildarch flavor
+debian/stamp-makefile-install/buildarch: DEB_MAKE_INSTALL_TARGET=
+debian/stamp-autotools/hostarch: debian/stamp-makefile-build/buildarch
+	mkdir -p build/hostarch
+	$(DEB_CONFIGURE_INVOKE) $(cdbs_configure_flags) $(DEB_CONFIGURE_EXTRA_FLAGS) $(DEB_CONFIGURE_USER_FLAGS)
+	touch $@
+endif
+
 # Include cdbs rules files.
 include /usr/share/cdbs/1/rules/debhelper.mk
 include /usr/share/cdbs/1/class/autotools.mk
@@ -44,6 +61,7 @@
 clean::
 	$(RM) *.cdbs-config_list
 	$(RM) -f source/config.log
+	$(RM) -R build
 
 # The libicudata library contains no symbols, so its debug library is
 # useless and triggers lintian warnings.  Just remove it.
EOF
}

add_automatic isl
add_automatic keyutils
add_automatic libatomic-ops
add_automatic libdebian-installer
add_automatic libelf
add_automatic libgc

add_automatic libgcrypt20
buildenv_libgcrypt20() {
	export ac_cv_sys_symbol_underscore=no
}

add_automatic libgpg-error
patch_libgpg_error() {
	echo "fixing libgpg-error FTBFS with gcc-5 #777374"
	drop_privs patch -p1 <<'EOF'
diff -Nru libgpg-error-1.17/debian/rules libgpg-error-1.17/debian/rules
--- libgpg-error-1.17/debian/rules
+++ libgpg-error-1.17/debian/rules
@@ -6,6 +6,7 @@
 export CFLAGS   := $(shell dpkg-buildflags --get CFLAGS)
 export CXXFLAGS := $(shell dpkg-buildflags --get CXXFLAGS)
 export LDFLAGS  := $(shell dpkg-buildflags --get LDFLAGS)
+export CPP	:= $(shell dpkg-architecture -qDEB_HOST_GNU_TYPE)-gcc -E -P
 
 export DEB_BUILD_MULTIARCH ?= $(shell dpkg-architecture -qDEB_BUILD_MULTIARCH)
 export DEB_HOST_MULTIARCH ?= $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)
EOF
}

add_automatic libice
add_automatic libonig
add_automatic libpng
add_automatic libpthread-stubs
add_automatic libsepol
add_automatic libsm
add_automatic libssh2
add_automatic libtasn1-6
add_automatic libtextwrap
add_automatic libunistring

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
	echo "fixing nss FTBFS on x32 #699217"
	drop_privs patch -p1 <<'EOF'
diff -Nru nss-3.17/debian/rules nss-3.17/debian/rules
--- nss-3.17/debian/rules
+++ nss-3.17/debian/rules
@@ -25,6 +25,11 @@
 else
 USE_64 :=
 endif
+ifeq (x32,$(shell dpkg-architecture -qDEB_HOST_ARCH))
+USE_X32 := USE_X32=1
+else
+USE_X32 :=
+endif
 
 # $(foreach foo,$(list),$(call cmd,some command $(foo))) expands to
 #    some command first-elem
@@ -57,7 +62,8 @@
 		NSS_ENABLE_ECC=1 \
 		CHECKLOC= \
 		$(TOOLCHAIN) \
-		$(USE_64)
+		$(USE_64) \
+		$(USE_X32)
 
 override_dh_auto_clean:
 	-$(MAKE) -C nss \
@@ -66,7 +72,8 @@
 		SOURCE_MD_DIR=$(DISTDIR) \
 		DIST=$(DISTDIR) \
 		BUILD_OPT=1 \
-		$(USE_64)
+		$(USE_64) \
+		$(USE_X32)
 
 	rm -rf $(DISTDIR) $(PREPROCESS_FILES:.in=)
 
EOF
}

add_automatic openssl
patch_openssl() {
	echo "fixing cross compilation of openssl for mips* architectures"
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
add_automatic patch
add_automatic pcre3
add_automatic readline5

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
add_need build-essential # build-essential
add_need bzip2 # by dpkg, perl
add_need cloog # by gcc-4.9
add_need dash # essential
add_need db-defaults # by apt, perl, python2.7
add_need debianutils # essential
add_need diffutils # essential
add_need freetype # by fontconfig
add_need gdbm # by perl, python2.7
add_need gmp # by gnutls28, guile-2.0, nettle
add_need grep # essential
add_need groff # for man-db
add_need gzip # essential
add_need hostname # essential
add_need icu # by libxml2
test "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS`" = linux && add_need keyutils # by krb5
add_need libatomic-ops # by gcc-4.9
add_need libdebian-installer # by cdebconf
add_need libelf # by systemtap, glib2.0
add_need libgc # by guile-2.0
add_need libgcrypt20 # by libprelude, cryptsetup
add_need libpng # by slang2
add_need libpthread-stubs # by libxcb
test "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS`" = linux && add_need libsepol # by libselinux
add_need libssh2 # by curl
add_need libtasn1-6 # by gnutls28
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
add_need nettle # by gnutls28
add_need nss # by curl
add_need openssl # by curl
add_need p11-kit # by gnutls28
add_need patch # for dpkg-dev
add_need pcre3 # by libselinux
add_need readline5 # by lvm2
add_need sed # essential
add_need slang2 # by cdebconf, newt
add_need sqlite3 # by python2.7
add_need tar # essential
add_need tcl8.6 # by newt
add_need tcltk-defaults # by python2.7
add_need tk8.6 # by blt
add_need ustr # by libsemanage

automatically_cross_build_packages() {
	local need_packages_comma_sep dosetmp buildable new_needed line pkg missing source
	while test -n "$need_packages"; do
		echo "checking packages with dose-builddebcheck: $need_packages"
		need_packages_comma_sep=`echo $need_packages | sed 's/ /,/g'`
		dosetmp=`mktemp -t doseoutput.XXXXXXXXXX`
		call_dose_builddebcheck --successes --failures --explain --latest --DropBuildIndep "--checkonly=$need_packages_comma_sep" >"$dosetmp"
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
					missing=${missing#*:} # skip architecture
					missing=${missing%% | *} # drop alternatives
					missing=${missing% (* *)} # drop version constraint
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
	call_dose_builddebcheck --failures --explain --latest --DropBuildIndep "--checkonly=$missing_pkgs_comma_sep"
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

builddep_gpm() {
	# texlive-base dependency unsatisfiable
	$APT_GET install autoconf autotools-dev quilt debhelper mawk bison texlive-base texinfo texi2html
}
cross_build gpm
mark_built gpm
# needed by ncurses

automatically_cross_build_packages

patch_ncurses() {
	echo "patching ncurses to support the nobiarch profile #737946"
	drop_privs patch -p1 <<EOF
diff -Nru ncurses-5.9+20140118/debian/control ncurses-5.9+20140118/debian/control
--- ncurses-5.9+20140118/debian/control
+++ ncurses-5.9+20140118/debian/control
@@ -5,7 +5,7 @@
 Uploaders: Sven Joachim <svenjoac@gmx.de>
 Build-Depends: debhelper (>= 8.1.3),
                dpkg-dev (>= 1.15.7),
-               g++-multilib [amd64 i386 powerpc ppc64 s390 sparc],
+               g++-multilib [amd64 i386 powerpc ppc64 s390 sparc] <!nobiarch>,
                libgpm-dev [linux-any],
                pkg-config,
 Standards-Version: 3.9.5
@@ -158,6 +158,7 @@
 Depends: lib64tinfo5 (= \${binary:Version}),
          \${shlibs:Depends}, \${misc:Depends}
 Replaces: amd64-libs (<= 1.2)
+Build-Profiles: <!nobiarch>
 Description: shared libraries for terminal handling (64-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -177,6 +178,7 @@
          libncurses5-dev (= \${binary:Version}), lib64c-dev, \${misc:Depends}
 Suggests: ncurses-doc
 Replaces: amd64-libs-dev (<= 1.2), lib64tinfo5-dev
+Build-Profiles: <!nobiarch>
 Description: developer's libraries for ncurses (64-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -193,6 +195,7 @@
 Depends: lib32tinfo5 (= \${binary:Version}),
          \${shlibs:Depends}, \${misc:Depends}
 Replaces: ia32-libs (<< 1.10)
+Build-Profiles: <!nobiarch>
 Description: shared libraries for terminal handling (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -211,6 +214,7 @@
          lib32tinfo-dev (= \${binary:Version}),
          libncurses5-dev (= \${binary:Version}), lib32c-dev, \${misc:Depends}
 Suggests: ncurses-doc
+Build-Profiles: <!nobiarch>
 Description: developer's libraries for ncurses (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -226,6 +230,7 @@
 Priority: optional
 Depends: lib32tinfo5 (= \${binary:Version}),
          \${shlibs:Depends}, \${misc:Depends}
+Build-Profiles: <!nobiarch>
 Description: shared libraries for terminal handling (wide character support) (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -244,6 +249,7 @@
          lib32tinfo-dev (= \${binary:Version}),
          libncursesw5-dev (= \${binary:Version}), lib32c-dev, \${misc:Depends}
 Suggests: ncurses-doc
+Build-Profiles: <!nobiarch>
 Description: developer's libraries for ncursesw (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -261,6 +267,7 @@
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: lib64ncurses5 (<< 5.9-3)
 Breaks: lib64ncurses5 (<< 5.9-3)
+Build-Profiles: <!nobiarch>
 Description: shared low-level terminfo library for terminal handling (64-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -275,6 +282,7 @@
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: lib32ncurses5 (<< 5.9-3)
 Breaks: lib32ncurses5 (<< 5.9-3)
+Build-Profiles: <!nobiarch>
 Description: shared low-level terminfo library for terminal handling (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -291,6 +299,7 @@
          lib32c-dev, \${misc:Depends}
 Replaces: lib32ncurses5-dev (<< 5.9-3), lib32tinfo5-dev
 Breaks: lib32ncurses5-dev (<< 5.9-3)
+Build-Profiles: <!nobiarch>
 Description: developer's library for the low-level terminfo library (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
diff -Nru ncurses-5.9+20140118/debian/rules ncurses-5.9+20140118/debian/rules
--- ncurses-5.9+20140118/debian/rules
+++ ncurses-5.9+20140118/debian/rules
@@ -97,6 +97,11 @@
 usr_lib32 = /usr/lib32
 endif
 
+ifneq (,\$(filter nobiarch,\$(DEB_BUILD_PROFILES)))
+override build_32=
+override build_64=
+endif
+
 ifeq (\$(DEB_HOST_ARCH_OS),linux)
 with_gpm = --with-gpm
 endif
EOF
}
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

builddep_xz_utils() {
	# autopoint dependency unsatisfiable
	$APT_GET install debhelper perl dpkg-dev autoconf automake libtool gettext autopoint
}
cross_build xz-utils
mark_built xz-utils
# needed by dpkg, libxml2

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
	# libsystemd-dev lacks profile annotation
	$APT_GET install dh-systemd dpkg-dev gettext "libncurses5-dev:$1" "libselinux1-dev:$1" "libslang2-dev:$1" libtool lsb-release pkg-config po-debconf "zlib1g-dev:$1"
}
patch_util_linux() {
	echo "applying ah's stage1 patch for util-linux #757147"
	drop_privs patch -p1 <<'EOF'
diff -Nru util-linux-2.25.1/debian/control util-linux-2.25.1/debian/control
--- util-linux-2.25.1/debian/control
+++ util-linux-2.25.1/debian/control
@@ -9,15 +9,15 @@
                dpkg-dev (>=1.16.0),
                gettext,
                libncurses5-dev,
-               libpam0g-dev,
+               libpam0g-dev <!stage1>,
                libselinux1-dev [linux-any],
                libslang2-dev (>=2.0.4),
-               libsystemd-dev [linux-any],
+               libsystemd-dev [linux-any] <!stage1>,
                libtool,
                lsb-release,
                pkg-config,
                po-debconf,
-               systemd [linux-any],
+               systemd [linux-any] <!stage1>,
                zlib1g-dev
 Section: base
 Priority: required
@@ -32,6 +32,7 @@
 
 Package: util-linux
 Architecture: any
+Build-Profiles: <!stage1>
 Section: utils
 Essential: yes
 Pre-Depends: ${misc:Pre-Depends}, ${shlibs:Depends}
@@ -48,6 +49,7 @@
 
 Package: util-linux-locales
 Architecture: all
+Build-Profiles: <!stage1>
 Section: localization
 Priority: optional
 Depends: util-linux (>= ${source:Upstream-Version}), ${misc:Depends}
@@ -61,6 +63,7 @@
 
 Package: mount
 Architecture: linux-any
+Build-Profiles: <!stage1>
 Essential: yes
 Section: admin
 Pre-Depends: ${misc:Pre-Depends}, ${shlibs:Depends}
@@ -73,6 +76,7 @@
 
 Package: bsdutils
 Architecture: any
+Build-Profiles: <!stage1>
 Essential: yes
 Section: utils
 Pre-Depends: ${misc:Pre-Depends}, ${shlibs:Depends}
@@ -86,6 +90,7 @@
 
 Package: fdisk-udeb
 Architecture: hurd-any linux-any
+Build-Profiles: <!stage1>
 Priority: extra
 Section: debian-installer
 Depends: ${misc:Depends}, ${shlibs:Depends}
@@ -95,6 +100,7 @@
 
 Package: cfdisk-udeb
 Architecture: hurd-any linux-any
+Build-Profiles: <!stage1>
 Priority: extra
 Section: debian-installer
 Depends: ${misc:Depends}, ${shlibs:Depends}
@@ -224,6 +230,7 @@
 
 Package: uuid-runtime
 Architecture: any
+Build-Profiles: <!stage1>
 Section: utils
 Priority: optional
 Pre-Depends: libuuid1 (>= 2.25-5~), ${misc:Pre-Depends}
@@ -275,6 +282,7 @@
 
 Package: util-linux-udeb
 Architecture: any
+Build-Profiles: <!stage1>
 Priority: optional
 Section: debian-installer
 Depends: ${misc:Depends}, ${shlibs:Depends}
diff -Nru util-linux-2.25.1/debian/rules util-linux-2.25.1/debian/rules
--- util-linux-2.25.1/debian/rules
+++ util-linux-2.25.1/debian/rules
@@ -12,7 +12,11 @@
 CONFOPTS += --enable-raw
 CONFOPTS += --with-selinux
 CONFOPTS += --enable-partx
-CONFOPTS += --with-systemd
+ifneq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
+	CONFOPTS += --without-systemd
+else
+	CONFOPTS += --with-systemd
+endif
 CONFOPTS += --enable-tunelp
 endif
 
@@ -58,6 +58,12 @@
 
 override_dh_auto_install:
 	dh_auto_install
+ifneq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
+	# dh-exec as used in util-linux.install does not support profiles
+	install -d debian/tmp/lib/systemd/system
+	install -m644 sys-utils/fstrim.service.in debian/tmp/lib/systemd/system/fstrim.service
+	install -m644 sys-utils/fstrim.timer debian/tmp/lib/systemd/system/fstrim.timer
+endif
 	#
 	# the version in bsdmainutils seems newer.
 	rm -f debian/tmp/usr/bin/look debian/tmp/usr/share/man/man1/look.1
@@ -117,7 +121,9 @@
 	dh_installman --language=C
 
 override_dh_gencontrol:
+ifeq ($(filter stage1,$(DEB_BUILD_PROFILES)),)
 	dh_gencontrol --package=bsdutils -- -v1:$(DEB_VERSION_UPSTREAM_REVISION)
+endif
 	dh_gencontrol --remaining-packages
 
 override_dh_installinit:
EOF
}
if test -d "$RESULT/util-linux_1"; then
	echo "skipping rebuild of util-linux stage1"
else
	builddep_util_linux "$HOST_ARCH"
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
	# python-all lacks build profile annotation
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

builddep_bash() {
	assert_built "ncurses"
	# time dependency unsatisfiable #751776
	$APT_GET install autoconf autotools-dev bison "libncurses5-dev:$HOST_ARCH" texinfo texi2html debhelper locales gettext sharutils time xz-utils dpkg-dev
}
cross_build bash
mark_built bash
# essential

automatically_cross_build_packages

builddep_bsdmainutils() {
	assert_built "ncurses"
	# python-hdate dependency unsatisfiable
	$APT_GET install debhelper "libncurses5-dev:$HOST_ARCH" quilt python python-hdate
}
cross_build bsdmainutils
mark_built bsdmainutils
# needed for man-db

automatically_cross_build_packages

builddep_libffi() {
	# dejagnu dependency unsatisfiable
	$APT_GET install debhelper dejagnu lsb-release texinfo dpkg-dev
}
cross_build libffi
mark_built libffi
# needed by guile-2.0, p11-kit

automatically_cross_build_packages

builddep_dpkg() {
	assert_built "bzip2 libselinux ncurses xz-utils zlib"
	# libtimedate-perl dependency unsatisfiable
	$APT_GET install debhelper pkg-config flex gettext po4a "zlib1g-dev:$1" "libbz2-dev:$1" "liblzma-dev:$1" "libselinux1-dev:$1" "libncursesw5-dev:$1" libtimedate-perl libio-string-perl
}
cross_build dpkg
mark_built dpkg
# essential

automatically_cross_build_packages

builddep_findutils() {
	assert_built "libselinux"
	# dejagnu dependency unsatisfiable
	$APT_GET install texinfo debhelper autotools-dev "libselinux1-dev:$1" bison
}
cross_build findutils
mark_built findutils
# essential

automatically_cross_build_packages

builddep_guile_2_0() {
	assert_built "gmp libffi libgc libtool libunistring ncurses readline6"
	if test "$1" = armel -o "$1" = armhf; then
		# force $GCC_VER instead of gcc-4.8
		$APT_GET install libtool debhelper autoconf automake dh-autoreconf "libncurses5-dev:$1" "libreadline6-dev:$1" "libltdl-dev:$1" "libgmp-dev:$1" texinfo flex "libunistring-dev:$1" "libgc-dev:$1" "libffi-dev:$1" pkg-config
	else
		$APT_GET build-dep --arch-only "-a$1" guile-2.0
	fi
	$APT_GET install guile-2.0 # needs Build-Depends: guile-2.0 <cross>
}
patch_guile_2_0() {
	echo "reverting gcc-4.8 CC override for arm"
	drop_privs patch -p1 <<'EOF'
diff -Nru guile-2.0-2.0.11+1/debian/rules guile-2.0-2.0.11+1/debian/rules
--- guile-2.0-2.0.11+1/debian/rules
+++ guile-2.0-2.0.11+1/debian/rules
@@ -85,11 +85,6 @@
 	INSTALL_PROGRAM += -s
 endif
 
-# When this is eventually removed, remove the guile-snarf sed below.
-ifeq (arm,$(DEB_HOST_ARCH_CPU))
-	export CC := gcc-4.8
-endif
-
 define checkdir
   dh_testdir debian/guile.postinst
 endef
@@ -203,10 +198,6 @@
 	sed -i'' '0,\|/usr/bin/guile|s||$(deb_guile_bin_path)|' \
 	  debian/$(deb_pkg_basename)-dev/usr/bin/guile-config
 
-        # Until the arm build-dependency and CC override (above) is fixed.
-	sed -i'' 's|gcc-4\.8|gcc|g' \
-	  debian/$(deb_pkg_basename)-dev/usr/bin/guile-snarf
-
 	sed -i'' '0,\|\$${exec_prefix}/bin/guile|s||$(deb_guile_bin_path)|' \
 	  debian/$(deb_pkg_basename)-dev/usr/bin/guild
 
EOF
}
cross_build guile-2.0
mark_built guile-2.0
# needed by gnutls28, make-dfsg, autogen

automatically_cross_build_packages

builddep_libpipeline() {
	# check lacks nocheck build profile annotation
	$APT_GET install dpkg-dev debhelper pkg-config dh-autoreconf automake
}
cross_build libpipeline
mark_built libpipeline
# man-db

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
	$APT_GET install libglib2.0-dev # missing B-D on libglib2.0-dev:any <profile.cross>
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

assert_built "$need_packages"
