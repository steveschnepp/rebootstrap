#!/bin/sh

set -v
set -e

export DEB_BUILD_OPTIONS="nocheck parallel=1"
export DH_VERBOSE=1
RESULT="/tmp/result"
HOST_ARCH=undefined
# select gcc version from gcc-defaults package unless set
GCC_VER=
MIRROR="http://ftp.stw-bonn.de/debian"
ENABLE_MULTILIB=no
ENABLE_MULTIARCH_GCC=yes
REPODIR=/tmp/repo
APT_GET="apt-get --no-install-recommends -y"
DEFAULT_PROFILES=cross
LIBC_NAME=glibc

# evaluate command line parameters of the form KEY=VALUE
for param in "$*"; do
	echo "bootstrap-configuration: $param"
	eval $param
done

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
			if test 64 != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_BITS`; then
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
			if test big != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_ENDIAN`; then
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
			if test powerpc != `dpkg-architecture -a$2 -qDEB_HOST_ARCH_CPU`; then
				echo "cpu mismatch"
				echo "expected $2"
				echo "got $FILE_RES"
				return 1
			fi
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

obtain_source_package() {
	apt-get source "$1"
}

apt-get update
$APT_GET install pinentry-curses # avoid installing pinentry-gtk (via reprepro)
$APT_GET install build-essential debhelper reprepro

if test "$ENABLE_MULTIARCH_GCC" = yes; then
	echo "deb $MIRROR experimental main" > /etc/apt/sources.list.d/tmp-experimental.list
	apt-get update
	$APT_GET install cross-gcc-dev
	rm /etc/apt/sources.list.d/tmp-experimental.list
	apt-get update
	$APT_GET install quilt
fi

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

mkdir -p /tmp/buildd
mkdir -p "$RESULT"

if test "$HOST_ARCH" = "i386" -a "$GCC_VER" != "4.8" ; then
	echo "fixing dpkg's cputable for i386 #751363"
	sed -i 's/i486/i586/' /usr/share/dpkg/cputable
fi
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
EOF
cat > "$REPODIR/conf/options" <<EOF
verbose
ignore wrongdistribution
EOF
export REPREPRO_BASE_DIR="$REPODIR"
reprepro export
echo "deb [ arch=`dpkg --print-architecture`,$HOST_ARCH trusted=yes ] file://$REPODIR rebootstrap main" >/etc/apt/sources.list.d/rebootstrap.list
cat >/etc/apt/preferences.d/rebootstrap.pref <<EOF
Explanation: prefer our own rebootstrap (toolchain) packages over everything
Package: *
Pin: release l=rebootstrap
Pin-Priority: 1001
EOF
apt-get update

pickup_packages() {
	local sources
	local source
	local f
	local i
	# collect source package names referenced
	for f in "$*"; do
		if test "${f%.deb}" != "$f"; then
			source=`dpkg-deb -f "$f" Source`
			test -z "$source" && source=${f%%_*}
		elif test "${f%.changes}" != "$f"; then
			source=${f%%_*}
		else
			echo "cannot pick up package $f"
			exit 1
		fi
		sources="$sources $source"
	done
	sources=`echo "$sources" | tr ' ' '\n' | sort -u`
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
	for f in "$*"; do
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

cross_build_setup() {
	local pkg mangledpkg subdir
	pkg="$1"
	subdir="$2"
	if test -z "$subdir"; then
		subdir="$pkg"
	fi
	mangledpkg=`echo "$pkg" | tr -- -. __` # - invalid in function names
	cd /tmp/buildd
	mkdir "$subdir"
	cd "$subdir"
	obtain_source_package "$pkg"
	cd "${pkg}-"*
	if type "patch_$mangledpkg" >/dev/null; then
		"patch_$mangledpkg"
	fi
}

check_binNMU() {
	local src pkg srcversion binversion maxversion
	srcversion=`dpkg-parsechangelog -SVersion`
	for pkg in `dh_listpackages`; do
		binversion=`apt-cache show "$pkg=$srcversion*" 2>/dev/null | sed -n 's/^Version: //p;T;q'`
		test -z "$binversion" && continue
		if dpkg --compare-versions "$maxversion" lt "$binversion"; then
			maxversion=$binversion
		fi
	done
	case "$maxversion" in
		"$srcversion+b"*)
			src=`dpkg-parsechangelog -SSource`
			echo "rebootstrap-warning: binNMU detected for $src $srcversion/$maxversion"
			cat - debian/changelog >debian/changelog.new <<EOF
$src ($maxversion) unstable; urgency=medium, binary-only=yes

  * Binary-only non-maintainer upload for $HOST_ARCH; no source changes.
  * Bump to binNMU version of `dpkg --print-architecture`.

 -- rebootstrap <invalid@invalid>  `date -R`
EOF
			mv debian/changelog.new debian/changelog
		;;
	esac
}

cross_build() {
	local pkg profiles mangledpkg
	pkg="$1"
	profiles="$DEFAULT_PROFILES $2"
	mangledpkg=`echo "$pkg" | tr -- -. __` # - invalid in function names
	if test "$ENABLE_MULTILIB" = "no"; then
		profiles="$profiles nobiarch"
	fi
	profiles=`echo "$profiles" | sed 's/ /,/g;s/,,*/,/g;s/^,//;s/,$//'`
	if test -d "$RESULT/$pkg"; then
		echo "skipping rebuild of $pkg with profiles $profiles"
	else
		echo "building $pkg with profiles $profiles"
		if type "builddep_$mangledpkg" >/dev/null; then
			echo "installing Build-Depends for $pkg using custom function"
			"builddep_$mangledpkg" "$HOST_ARCH" "$profiles"
		else
			echo "installing Build-Depends for $pkg using apt-get build-dep"
			$APT_GET build-dep -a$HOST_ARCH --arch-only -P "$profiles" "$pkg"
		fi
		cross_build_setup "$pkg"
		check_binNMU
		if type "builddep_$mangledpkg" >/dev/null; then
			if dpkg-checkbuilddeps -a$HOST_ARCH -P "$profiles"; then
				echo "rebootstrap-warning: Build-Depends for $pkg satisfied even though a custom builddep_  function is in use"
			fi
			dpkg-buildpackage -a$HOST_ARCH -B "-P$profiles" -d -uc -us
		else
			dpkg-buildpackage -a$HOST_ARCH -B "-P$profiles" -uc -us
		fi
		cd ..
		ls -l
		pickup_packages *.changes
		test -d "$RESULT" && mkdir "$RESULT/$pkg"
		test -d "$RESULT" && cp *.deb "$RESULT/$pkg/"
		cd ..
		rm -Rf "$pkg"
	fi
}

# gcc0
patch_gcc_4_8() {
	echo "patching gcc to honour DEB_CROSS_NO_BIARCH for hppa #745116"
	patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/rules.defs gcc-4.8-4.8.2/debian/rules.defs
--- gcc-4.8-4.8.2/debian/rules.defs
+++ gcc-4.8-4.8.2/debian/rules.defs
@@ -1138,7 +1138,11 @@
   # hppa64 build ----------------
   hppa64_no_snap := no
   ifeq (\$(DEB_TARGET_ARCH),hppa)
-    with_hppa64 := yes
+    ifdef DEB_CROSS_NO_BIARCH
+      with_hppa64 := disabled by DEB_CROSS_NO_BIARCH
+    else
+      with_hppa64 := yes
+    endif
   endif
   ifeq (\$(hppa64_no_snap)-\$(trunk_build),yes-yes)
     with_hppa64 := disabled for snapshot build
EOF
	echo "patching gcc-4.8 to build common libraries. not a bug"
	patch -p1 <<EOF
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
	if test "$ENABLE_MULTIARCH_GCC" = yes; then
		echo "applying patches for with_deps_on_target_arch_pkgs"
		QUILT_PATCHES=/usr/share/cross-gcc/patches/ quilt push -a
	fi
}
if test "$ENABLE_MULTIARCH_GCC" = yes; then
# choosing libatomic1 arbitrarily here, cause it never bumped soname
BUILD_GCC_MULTIARCH_VER=`apt-cache show --no-all-versions libatomic1 | sed 's/^Source: gcc-\([0-9.]*\)$/\1/;t;d'`
if test "$GCC_VER" != "$BUILD_GCC_MULTIARCH_VER"; then
	echo "host gcc version ($GCC_VER) and build gcc version ($BUILD_GCC_MULTIARCH_VER) mismatch. need different build gcc"
if test -d "$RESULT/gcc0"; then
	echo "skipping rebuild of build gcc"
	dpkg -i $RESULT/gcc0/*.deb
else
	$APT_GET build-dep --arch-only gcc-$GCC_VER
	# dependencies for common libs no longer declared
	$APT_GET install doxygen graphviz ghostscript texlive-latex-base xsltproc docbook-xsl-ns
	cross_build_setup "gcc-$GCC_VER" gcc0
	DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,d,go,java,objc,obj-c++" dpkg-buildpackage -T control -uc -us
	DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,d,go,java,objc,obj-c++" dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	rm -fv *-plugin-dev_*.deb *-dbg_*.deb
	dpkg -i *.deb
	test -d "$RESULT" && mkdir "$RESULT/gcc0"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc0"
	cd ..
	rm -Rf gcc0
fi
echo "progress-mark:0:build compiler complete"
else
echo "host gcc version and build gcc version match. good for multiarch"
fi
fi

# binutils
PKG=`echo $RESULT/binutils-*.deb`
if test -f "$PKG"; then
	echo "skipping rebuild of binutils-target"
else
	$APT_GET install autoconf bison flex gettext texinfo dejagnu quilt python3 file lsb-release zlib1g-dev
	cross_build_setup binutils
	WITH_SYSROOT=/ TARGET=$HOST_ARCH dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET install binutils$HOST_ARCH_SUFFIX
	assembler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-as"
	if ! which "$assembler"; then echo "$assembler missing in binutils package"; exit 1; fi
	if ! $assembler -o test.o /dev/null; then echo "binutils fail to execute"; exit 1; fi
	if ! test -f test.o; then echo "binutils fail to create object"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	test -d "$RESULT" && cp -v binutils-*.deb "$RESULT"
	cd ..
	rm -Rf binutils
fi
echo "progress-mark:1:binutils cross complete"

# linux
patch_linux() {
	if test "$HOST_ARCH" = arm; then
		echo "patching linux for arm"
		patch -p1 <<EOF
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
		./debian/rules debian/rules.gen || : # intentionally exits 1 to avoid being called automatically. we are doing it wrong
	fi
}
if test "`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_ARCH_OS`" = "linux"; then
PKG=`echo $RESULT/linux-libc-dev_*.deb`
if test -f "$PKG"; then
	echo "skipping rebuild of linux-libc-dev"
else
	$APT_GET install bc cpio debhelper kernel-wedge patchutils python quilt python-six
	cross_build_setup linux
	dpkg-checkbuilddeps -B -a$HOST_ARCH || : # tell unmet build depends
	KBUILD_VERBOSE=1 make -f debian/rules.gen binary-libc-dev_$HOST_ARCH
	cd ..
	ls -l
	pickup_packages *.deb
	test -d "$RESULT" && cp -v linux-libc-dev_*.deb "$RESULT"
	cd ..
	rm -Rf linux
fi
echo "progress-mark:2:linux-libc-dev complete"
fi

# gcc
if test -d "$RESULT/gcc1"; then
	echo "skipping rebuild of gcc stage1"
	$APT_GET remove gcc-multilib
	dpkg -i $RESULT/gcc1/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev binutils-multiarch "binutils$HOST_ARCH_SUFFIX" "linux-libc-dev:$HOST_ARCH"
	cross_build_setup "gcc-$GCC_VER" gcc1
	dpkg-checkbuilddeps || : # tell unmet build depends
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	else
		DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET remove gcc-multilib
	if test "$ENABLE_MULTILIB" = yes && ls | grep -q multilib; then
		$APT_GET install "gcc-$GCC_VER-multilib$HOST_ARCH_SUFFIX"
	else
		rm -vf ./*multilib*.deb
		$APT_GET install "gcc-$GCC_VER$HOST_ARCH_SUFFIX"
	fi
	compiler="`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage1 gcc package"; exit 1; fi
	if ! $compiler -x c -c /dev/null -o test.o; then echo "stage1 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage1 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	test -d "$RESULT" && mkdir "$RESULT/gcc1"
	test -d "$RESULT" && cp cpp-$GCC_VER-*.deb gcc-$GCC_VER-*.deb "$RESULT/gcc1"
	cd ..
	rm -Rf gcc1
fi
echo "progress-mark:3:gcc stage1 complete"

if test "$ENABLE_MULTIARCH_GCC" = yes; then
	# $LIBC_NAME looks for linux headers in /usr/<triplet>/include/linux rather than /usr/include/linux
	# later gcc looks for pthread.h and stuff in /usr/<triplet>/include rather than /usr/include
	mkdir -p "/usr/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`"
	ln -s ../include "/usr/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`/include"
	ln -s "../include/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH`" "/usr/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`/sys-include"
fi

# libc
patch_glibc() {
	echo "patching eglibc to include a libc6.so and place crt*.o in correct directory"
	patch -p1 <<EOF
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
@@ -197,7 +197,15 @@
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
	patch -p1 <<EOF
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
	patch -p1 <<'EOF'
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
	patch -p1 <<'EOF'
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
}
if test -d "$RESULT/${LIBC_NAME}1"; then
	echo "skipping rebuild of $LIBC_NAME stage1"
	$APT_GET remove libc6-dev-i386
	dpkg -i "$RESULT/${LIBC_NAME}1/"*.deb
else
	$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase linux-libc-dev:$HOST_ARCH
	cross_build_setup "$LIBC_NAME" "${LIBC_NAME}1"
	if test "$ENABLE_MULTILIB" = yes; then
		dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1 || : # tell unmet build depends
		DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -d -Pstage1
	else
		dpkg-checkbuilddeps -B "-a$HOST_ARCH" -Pstage1,nobiarch || : # tell unmet build depends
		DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -d -Pstage1,nobiarch
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET remove libc6-dev-i386
	dpkg -i libc*.deb
	test -d "$RESULT" && mkdir "$RESULT/${LIBC_NAME}1"
	test -d "$RESULT" && cp -v libc*-dev_*.deb "$RESULT/${LIBC_NAME}1"
	cd ..
	rm -Rf "${LIBC_NAME}1"
fi
echo "progress-mark:4:$LIBC_NAME stage1 complete"
if test "$ENABLE_MULTIARCH_GCC" = yes; then
	# binutils looks for libc.so in /usr/<triplet>/lib rather than /usr/lib/<triplet>
	mkdir -p "/usr/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`"
	ln -s "/usr/lib/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_MULTIARCH`" "/usr/`dpkg-architecture "-a$HOST_ARCH" -qDEB_HOST_GNU_TYPE`/lib"
fi

if test -d "$RESULT/gcc2"; then
	echo "skipping rebuild of gcc stage2"
	dpkg -i "$RESULT"/gcc2/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev autogen systemtap-sdt-dev "libc-dev:$HOST_ARCH" binutils-multiarch "binutils$HOST_ARCH_SUFFIX"
	cross_build_setup "gcc-$GCC_VER" gcc2
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		gcc_cv_libc_provides_ssp=yes DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	else
		DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		gcc_cv_libc_provides_ssp=yes DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	rm -vf *multilib*.deb
	dpkg -i *.deb
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage2 gcc package"; exit 1; fi
	if ! $compiler -x c -c /dev/null -o test.o; then echo "stage2 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage2 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	test -d "$RESULT" && mkdir "$RESULT/gcc2"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc2"
	cd ..
	rm -Rf gcc2
fi
echo "progress-mark:5:gcc stage2 complete"
# libselinux wants unversioned gcc
ln -s `dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER /usr/bin/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc
ln -s `dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-cpp-$GCC_VER /usr/bin/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-cpp
ln -s `dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-g++-$GCC_VER /usr/bin/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-g++
ln -s `dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gfortran-$GCC_VER /usr/bin/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gfortran

if test "$HOST_ARCH" = "sparc"; then
	$APT_GET remove libc6-i386 # undeclared file conflict #745552
fi
if test -d "$RESULT/${LIBC_NAME}2"; then
	echo "skipping rebuild of $LIBC_NAME stage2"
	dpkg -i "$RESULT/${LIBC_NAME}2/"*.deb
else
	$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase linux-libc-dev:$HOST_ARCH
	cross_build_setup "$LIBC_NAME" "${LIBC_NAME}2"
	if test "$ENABLE_MULTILIB" = yes; then
		dpkg-checkbuilddeps -B -a$HOST_ARCH -Pstage2 || : # tell unmet build depends
		DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d -Pstage2
	else
		dpkg-checkbuilddeps -B -a$HOST_ARCH -Pstage2,nobiarch || : # tell unmet build depends
		DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d -Pstage2,nobiarch
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	rm -f libc6-i686_*.deb
	dpkg -i libc*-dev_*.deb libc*[0-9]_*_*.deb
	test -d "$RESULT" && mkdir "$RESULT/${LIBC_NAME}2"
	test -d "$RESULT" && cp libc*-dev_*.deb libc*[0-9]_*_*.deb "$RESULT/${LIBC_NAME}2"
	cd ..
	rm -Rf "${LIBC_NAME}2"
fi
echo "progress-mark:6:$LIBC_NAME stage2 complete"

if test -d "$RESULT/gcc3"; then
	echo "skipping rebuild of gcc stage3"
	dpkg -i "$RESULT"/gcc3/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex lsb-release quilt libtool autoconf2.64 zlib1g-dev libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen systemtap-sdt-dev binutils-multiarch "binutils$HOST_ARCH_SUFFIX" "libc-dev:$HOST_ARCH"
	cross_build_setup "gcc-$GCC_VER" gcc3
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	else
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes DEB_CROSS_NO_BIARCH=yes dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -T control
		dpkg-checkbuilddeps || : # tell unmet build depends again after rewriting control
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes DEB_CROSS_NO_BIARCH=yes dpkg-buildpackage "-Rdpkg-architecture -f -A$HOST_ARCH -c ./debian/rules" -d -b -uc -us
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	rm -fv gcc-*-plugin-*.deb gcj-*.deb gdc-*.deb *objc*.deb *-dbg_*.deb
	dpkg -i *.deb
	apt-get check # test for #745036
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage3 gcc package"; exit 1; fi
	if ! $compiler -x c -c /dev/null -o test.o; then echo "stage3 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage3 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	touch /usr/include/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH`/include_path_test_header.h
	preproc="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-cpp-$GCC_VER"
	if ! echo '#include "include_path_test_header.h"' | $preproc -E -; then echo "stage3 gcc fails to search /usr/include/<triplet>"; exit 1; fi
	test -d "$RESULT" && mkdir "$RESULT/gcc3"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc3"
	cd ..
	rm -Rf gcc3
fi
echo "progress-mark:7:gcc stage3 complete"

$APT_GET remove libc6-i386 # breaks cross builds

patch_zlib() {
	echo "patching zlib to support nobiarch build profile #709623"
	patch -p1 <<EOF
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
echo "progress-mark:8:zlib cross build"
# needed by dpkg, file, gnutls28, libpng, libtool, libxml2, perl, slang2, tcl8.6, util-linux

builddep_libtool() {
	test "$1" = "$HOST_ARCH"
	# gfortran dependency needs cross-translation
	$APT_GET install debhelper texi2html texinfo file "gfortran-$GCC_VER$HOST_ARCH_SUFFIX" automake autoconf autotools-dev help2man "zlib1g-dev:$HOST_ARCH"
}
cross_build libtool
echo "progress-mark:9:libtool cross build"
# needed by guile-2.0

cross_build pcre3
echo "progress-mark:10:pcre3 cross build"
# needed by grep, libselinux, slang2

cross_build attr
echo "progress-mark:11:attr cross build"
# needed by attr, coreutils, libcap-ng, tar

builddep_acl() {
	# libtool dependency unsatisfiable
	$APT_GET install dpkg-dev debhelper autotools-dev autoconf automake gettext libtool libattr1-dev:$HOST_ARCH
}
cross_build acl
echo "progress-mark:12:acl cross build"
# needed by coreutils, tar

if test "`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_ARCH_OS`" = "linux"; then
	cross_build libsepol
	echo "progress-mark:13:libsepol cross build"
fi

cross_build gmp
echo "progress-mark:14:gmp cross build"

cross_build mpfr4
echo "progress-mark:15:mpfr4 cross build"

cross_build mpclib3
echo "progress-mark:16:mpclib3 cross build"

cross_build isl
echo "progress-mark:17:isl cross build"

cross_build cloog
echo "progress-mark:18:cloog cross build"

builddep_gpm() {
	# texlive-base dependency unsatisfiable
	$APT_GET install autoconf autotools-dev quilt debhelper mawk bison texlive-base texinfo texi2html
}
cross_build gpm
echo "progress-mark:19:gpm cross build"

patch_ncurses() {
	echo "patching ncurses to support the nobiarch profile #737946"
	patch -p1 <<EOF
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
	# g++-multilib dependency unsatisfiable
	$APT_GET install debhelper dpkg-dev libgpm-dev:$HOST_ARCH pkg-config
}
cross_build ncurses
echo "progress-mark:20:ncurses cross build"

patch_readline6() {
	echo "patching readline6 to support nobiarch profile #737955"
	patch -p1 <<EOF
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
	# gcc-multilib dependency unsatisfiable
	$APT_GET install debhelper libtinfo-dev:$HOST_ARCH libncurses5-dev:$HOST_ARCH mawk texinfo autotools-dev
}
cross_build readline6
echo "progress-mark:21:readline6 cross build"

builddep_bzip2() {
	# unused gcc-multilib dependency unsatisfiable
	$APT_GET install dpkg-dev debhelper dh-exec
}
cross_build bzip2
echo "progress-mark:22:bzip2 cross build"

builddep_xz_utils() {
	# autopoint dependency unsatisfiable
	$APT_GET install debhelper perl dpkg-dev autoconf automake libtool gettext autopoint
}
cross_build xz-utils
echo "progress-mark:23:xz-utils cross build"

cross_build libonig
echo "progress-mark:24:libonig cross build"

builddep_libpng() {
	# libtool dependency unsatisfiable
	$APT_GET install debhelper libtool automake autoconf zlib1g-dev:$HOST_ARCH mawk
}
cross_build libpng
echo "progress-mark:25:libpng cross build"

builddep_slang2() {
	# unicode-data dependency unsatisfiable #752247
	$APT_GET install debhelper autoconf autotools-dev unicode-data chrpath docbook-to-man dpkg-dev libncurses-dev:$HOST_ARCH libonig-dev:$HOST_ARCH libpcre3-dev:$HOST_ARCH libpng-dev:$HOST_ARCH zlib1g-dev:$HOST_ARCH
}
cross_build slang2
echo "progress-mark:26:slang2 cross build"

if test -d "$RESULT/libselinux1"; then
	echo "skipping rebuild of libselinux stage1"
else
	# gem2deb dependency lacks profile annotation
	$APT_GET install debhelper file libsepol1-dev:$HOST_ARCH libpcre3-dev:$HOST_ARCH pkg-config
	cross_build_setup libselinux libselinux1
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us -a$HOST_ARCH
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/libselinux1"
	test -d "$RESULT" && cp *.deb "$RESULT/libselinux1"
	cd ..
	rm -Rf libselinux1
fi
echo "progress-mark:27:libselinux cross build"

builddep_util_linux() {
	# libsystemd-dev lacks profile annotation
	$APT_GET install dh-systemd dpkg-dev gettext "libncurses5-dev:$1" "libselinux1-dev:$1" "libslang2-dev:$1" libtool lsb-release pkg-config po-debconf "zlib1g-dev:$1"
}
patch_util_linux() {
	echo "applying ah's stage1 patch for util-linux #757147"
	patch -p1 <<'EOF'
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
	scanf_cv_type_modifier=ms dpkg-buildpackage -B -uc -us "-a$HOST_ARCH" -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/util-linux_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/util-linux_1"
	cd ..
	rm -Rf util-linux_1
fi
echo "progress-mark:28:util-linux stage1 cross build"
# essential, needed by e2fsprogs

cross_build base-files
echo "progress-mark:29:base-files cross build"

cross_build dash
echo "progress-mark:30:dash cross build"

cross_build tar
echo "progress-mark:31:tar cross build"

cross_build sed
echo "progress-mark:32:sed cross build"

cross_build gzip
echo "progress-mark:33:gzip cross build"

cross_build grep
echo "progress-mark:34:grep cross build"

if test "$HOST_ARCH" = sparc64; then export lsh_cv_sys_ccpic=-fPIC; fi
cross_build nettle
echo "progress-mark:35:nettle cross build"
unset lsh_cv_sys_ccpic

cross_build db-defaults
echo "progress-mark:36:db-defaults cross build"

cross_build mawk
echo "progress-mark:37:mawk cross build"

cross_build libatomic-ops
echo "progress-mark:38:libatomic-ops cross build"

cross_build diffutils
echo "progress-mark:39:diffutils cross build"

cross_build libgc
echo "progress-mark:40:libgc cross build"

builddep_gdbm() {
	# libtool dependency unsatisfiable #682045
	$APT_GET install texinfo libtool automake autoconf autotools-dev dpkg-dev
}
cross_build gdbm
echo "progress-mark:41:gdbm cross build"

builddep_file() {
	# python-all lacks build profile annotation
	$APT_GET install debhelper dh-autoreconf "zlib1g-dev:$HOST_ARCH"
}
if test -d "$RESULT/file_1"; then
	echo "skipping stage1 rebuild of file"
else
	builddep_file
	cross_build_setup file file_1
	dpkg-checkbuilddeps "-a$HOST_ARCH" || : # tell unmet build depends
	dpkg-buildpackage "-a$HOST_ARCH" -B -d -uc -us -Pstage1
	cd ..
	ls -l
	pickup_packages *.changes
	test -d "$RESULT" && mkdir "$RESULT/file_1"
	test -d "$RESULT" && cp ./*.deb "$RESULT/file_1/"
	cd ..
	rm -Rf file_1
fi
echo "progress-mark:42:file cross build"

cross_build debianutils
echo "progress-mark:43:debianutils cross build"

cross_build libunistring
echo "progress-mark:44:libunistring cross build"

cross_build patch
echo "progress-mark:45:patch cross build"

builddep_bash() {
	# time dependency unsatisfiable #751776
	$APT_GET install autoconf autotools-dev bison "libncurses5-dev:$HOST_ARCH" texinfo texi2html debhelper locales gettext sharutils time xz-utils dpkg-dev
}
cross_build bash
echo "progress-mark:46:bash cross build"

builddep_build_essential() {
	# python3 dependency unsatisfiable #750976
	$APT_GET install debhelper python3
}
cross_build build-essential
echo "progress-mark:47:build-essential cross build"

builddep_bsdmainutils() {
	# python-hdate dependency unsatisfiable
	$APT_GET install debhelper "libncurses5-dev:$HOST_ARCH" quilt python python-hdate
}
cross_build bsdmainutils
echo "progress-mark:48:bsdmainutils cross build"

cross_build libelf
echo "progress-mark:49:libelf cross build"

builddep_libffi() {
	# dejagnu dependency unsatisfiable
	$APT_GET install debhelper dejagnu lsb-release texinfo dpkg-dev
}
cross_build libffi
echo "progress-mark:50:libffi cross build"
# needed by guile-2.0, p11-kit

cross_build libdebian-installer
echo "progress-mark:51:libdebian-installer cross build"
# needed by cdebconf

cross_build libtasn1-6
echo "progress-mark:52:libtasn1-6 cross build"
# needed by gnutls28, p11-kit

cross_build gcc-defaults
echo "progress-mark:53:gcc-defaults cross build"
# needed for build-essential

builddep_dpkg() {
	# libtimedate-perl dependency unsatisfiable
	$APT_GET install debhelper pkg-config flex gettext po4a "zlib1g-dev:$1" "libbz2-dev:$1" "liblzma-dev:$1" "libselinux1-dev:$1" "libncursesw5-dev:$1" libtimedate-perl libio-string-perl
}
cross_build dpkg
echo "progress-mark:54:dpkg cross build"
# essential

cross_build hostname
echo "progress-mark:55:hostname cross build"
# essential

builddep_findutils() {
	# dejagnu dependency unsatisfiable
	$APT_GET install texinfo debhelper autotools-dev "libselinux1-dev:$1" bison
}
cross_build findutils
echo "progress-mark:56:findutils cross build"
# essential

builddep_guile_2_0() {
	$APT_GET build-dep --arch-only "-a$1" guile-2.0
	$APT_GET install guile-2.0 # needs Build-Depends: guile-2.0 <profile.cross>
}
cross_build guile-2.0
echo "progress-mark:57:guile-2.0 cross build"
# needed by gnutls28, make-dfsg, autogen

cross_build make-dfsg
echo "progress-mark:58:make-dfsg cross build"
# needed for build-essential

builddep_libpipeline() {
	# check lacks nocheck build profile annotation
	$APT_GET install dpkg-dev debhelper pkg-config dh-autoreconf automake
}
cross_build libpipeline
echo "progress-mark:59:libpipeline cross build"
# man-db

cross_build man-db
echo "progress-mark:60:man-db cross build"
# needed for debhelper

cross_build libgpg-error
echo "progress-mark:61:libgpg-error cross build"
# needed by libgcrypt11, libgcrypt20

cross_build libtextwrap
echo "progress-mark:62:libtextwrap cross build"
# needed by cdebconf

cross_build p11-kit
echo "progress-mark:63:p11-kit cross build"
# needed by gnutls28

patch_ustr() {
	echo "patching ustr to use only compile checks #721352"
	patch -p1 <<'EOF'
From 2df8917753d227aa39c09fdc191e4a005a4e943f Mon Sep 17 00:00:00 2001
From: Peter Pentchev <roam@ringlet.net>
Date: Wed, 30 Jul 2014 00:21:20 +0300
Subject: [PATCH] Make the configuration compile-time only, no running.

---
 debian/patches/debian/config-compile.diff |  153 +++++++++++++++++++++++++++++
 debian/patches/series                     |    1 +
 2 files changed, 154 insertions(+), 0 deletions(-)
 create mode 100644 debian/patches/debian/config-compile.diff

diff --git a/debian/patches/debian/config-compile.diff b/debian/patches/debian/config-compile.diff
new file mode 100644
index 0000000..8303014
--- /dev/null
+++ b/debian/patches/debian/config-compile.diff
@@ -0,0 +1,153 @@
+Description: Keep the configuration compile-time only, no running.
+ Make the autoconfiguration stage cross-compile-friendly - do not attempt
+ to run any of the just compiled code:
+ - modify the autoconf_64b.c test a little bit to break during compilation
+   if the type's size is different
+ - modify the autoconf_vsnprintf.c test a little bit to always break during
+   compilation, since we assume a POSIX-compatible libc
+ - add a "real" test for stdint.h usability - try to compile a program that
+   includes it.
+Forwarded: not yet
+Author: Peter Pentchev <roam@ringlet.net>
+Last-Update: 2014-07-29
+
+--- ustr.orig/Makefile
++++ ustr/Makefile
+@@ -447,7 +447,7 @@
+ 
+ distclean: clean
+ 		rm -f ustr-import
+-		rm -f autoconf_64b autoconf_vsnprintf
++		rm -f autoconf_64b autoconf_stdint autoconf_vsnprintf
+ 		rm -f ustr-conf.h ustr-conf-debug.h
+ 		rm -rf lcov-output
+ 
+@@ -459,13 +459,17 @@
+ 		$(HIDE)chmod 755 $@
+ 
+ # Use CFLAGS so that CFLAGS="... -m32" does the right thing
+-autoconf_64b: autoconf_64b.c
+-		$(HIDE)echo Compiling: auto configuration test:  64bit
+-		$(HIDE)$(CC) $(CFLAGS) -o $@ $<
+-
+-autoconf_vsnprintf: autoconf_vsnprintf.c
+-		$(HIDE)echo Compiling: auto configuration test:  vsnprintf
+-		$(HIDE)$(CC) -o $@ $<
++autoconf_64b: autoconf_64b.c check_compile.sh
++		$(HIDE)echo Running: auto configuration test:  64bit
++		$(HIDE)CC="$(CC)" CFLAGS="$(CFLAGS) -DCHECK_TYPE=size_t -DCHECK_SIZE=8" sh check_compile.sh $@ $@.c
++
++autoconf_stdint: autoconf_stdint.c check_compile.sh
++		$(HIDE)echo Running: auto configuration test:  stdint.h
++		$(HIDE)CC="$(CC)" CFLAGS="$(CFLAGS)" sh check_compile.sh $@ $@.c
++
++autoconf_vsnprintf: autoconf_vsnprintf.c check_compile.sh
++		$(HIDE)echo Running: auto configuration test:  vsnprintf
++		$(HIDE)CC="$(CC)" CFLAGS="$(CFLAGS)" sh check_compile.sh $@ $@.c
+ 
+ # Use LDFLAGS for LDFLAGS="-m32"
+ $(OPT_LIB_SHARED): $(LIB_SHARED_OPT)
+@@ -485,22 +489,18 @@
+ 		$(HIDE)$(AR) ru $@ $^
+ 		$(HIDE)$(RANLIB) $@
+ 
+-ustr-conf.h: ustr-conf.h.in autoconf_64b autoconf_vsnprintf
++ustr-conf.h: ustr-conf.h.in autoconf_64b autoconf_stdint autoconf_vsnprintf
+ 		$(HIDE)echo Creating $@
+-		$(HIDE)have_stdint_h=0; dbg1=0; dbg2=0; \
++		$(HIDE)dbg1=0; dbg2=0; \
+                 sz64=`./autoconf_64b`; vsnp=`./autoconf_vsnprintf`; \
+-                if test -f "/usr/include/stdint.h"; then have_stdint_h=1; fi; \
+-                if test -f "$(prefix)/include/stdint.h"; then have_stdint_h=1; fi; \
+-                if test -f "$(includedir)/stdint.h"; then have_stdint_h=1; fi; \
++		have_stdint_h=`./autoconf_stdint`; \
+ 		sed -e "s,@HAVE_STDINT_H@,$$have_stdint_h,g" -e "s,@USE_ASSERT@,$$dbg1,g" -e "s,@USE_EOS_MARK@,$$dbg2,g" -e "s,@HAVE_64bit_SIZE_MAX@,$$sz64,g" -e "s,@HAVE_RETARDED_VSNPRINTF@,$$vsnp,g" < $< > $@
+ 
+ ustr-conf-debug.h: ustr-conf.h.in autoconf_64b autoconf_vsnprintf
+ 		$(HIDE)echo Creating $@
+-		$(HIDE)have_stdint_h=0; dbg1=1; dbg2=1; \
++		$(HIDE)dbg1=1; dbg2=1; \
+                 sz64=`./autoconf_64b`; vsnp=`./autoconf_vsnprintf`; \
+-                if test -f "/usr/include/stdint.h"; then have_stdint_h=1; fi; \
+-                if test -f "$(prefix)/include/stdint.h"; then have_stdint_h=1; fi; \
+-                if test -f "$(includedir)/stdint.h"; then have_stdint_h=1; fi; \
++		have_stdint_h=`./autoconf_stdint`; \
+ 		sed -e "s,@HAVE_STDINT_H@,$$have_stdint_h,g" -e "s,@USE_ASSERT@,$$dbg1,g" -e "s,@USE_EOS_MARK@,$$dbg2,g" -e "s,@HAVE_64bit_SIZE_MAX@,$$sz64,g" -e "s,@HAVE_RETARDED_VSNPRINTF@,$$vsnp,g" < $< > $@
+ 
+ 
+--- ustr.orig/autoconf_64b.c
++++ ustr/autoconf_64b.c
+@@ -1,11 +1,17 @@
+ #include <stdlib.h>
+-#include <stdio.h>
+ 
+-int main(void)
+-{ /* output a "1" is it's a 64 bit platform. Major hack. */
+-	size_t val = -1;
++struct check_lower {
++	int arr[sizeof(CHECK_TYPE) - CHECK_SIZE];
++};
++
++struct check_higher {
++	int arr[CHECK_SIZE - sizeof(CHECK_TYPE)];
++};
+ 
+-	puts((val == 0xFFFFFFFF) ? "0" : "1");
++int main(void)
++{
++	struct check_lower lower;
++	struct check_higher higher;
+ 
+-	return 0;
++	return sizeof(lower) + sizeof(higher);
+ }
+--- /dev/null
++++ ustr/autoconf_stdint.c
+@@ -0,0 +1,7 @@
++#include <stdint.h>
++
++int
++main(void)
++{
++	return sizeof(intmax_t) - sizeof(uintmax_t) + SIZE_MAX;
++}
+--- ustr.orig/autoconf_vsnprintf.c
++++ ustr/autoconf_vsnprintf.c
+@@ -6,6 +6,10 @@
+ 
+ #define USE_FMT_1_3 0
+ 
++All right, I know this test will always "return" false, but let's
++actually assume that Debian's libc will follow POSIX at least
++inasmuch as the standard I/O library, okay?
++
+ static int my_autoconf(const char *fmt, ...)
+ {
+   va_list ap;
+--- /dev/null
++++ ustr/check_compile.sh
+@@ -0,0 +1,24 @@
++#!/bin/sh
++
++set -e
++
++tgtscript=$1
++source=$2
++
++conftmp=`mktemp conftmp.o.XXXXXX`
++trap "rm -f '$conftmp'" EXIT QUIT TERM INT HUP
++
++if $CC -c $CFLAGS -o "$conftmp" "$source" > /dev/null 2>&1; then
++	res=1
++else
++	res=0
++fi
++rm -f "$conftmp"
++
++cat > "$tgtscript" <<EOF
++#!/bin/sh
++
++echo '$res'
++EOF
++
++chmod +x "$tgtscript"
diff --git a/debian/patches/series b/debian/patches/series
index dab589a..ab05311 100644
--- a/debian/patches/series
+++ b/debian/patches/series
@@ -3,3 +3,4 @@ debian/reentrant.diff -p1
 fixes/man-cleanup.diff -p1
 fixes/man-spelling.diff -p1
 fixes/nonlinux.diff -p1
+debian/config-compile.diff -p1
-- 
1.7.1
EOF
	echo "patching ustr to use cross tools #721352"
	patch -p1 << 'EOF'
From c64fb406e8497898a33214f5afc2a6d8b12eb808 Mon Sep 17 00:00:00 2001
From: Peter Pentchev <roam@ringlet.net>
Date: Wed, 30 Jul 2014 19:30:25 +0300
Subject: [PATCH] Use the proper build tools when cross-building.

---
 debian/patches/debian/cross-build.diff |   34 ++++++++++++++++++++++++++++++++
 debian/patches/series                  |    1 +
 2 files changed, 35 insertions(+), 0 deletions(-)
 create mode 100644 debian/patches/debian/cross-build.diff

diff --git a/debian/patches/debian/cross-build.diff b/debian/patches/debian/cross-build.diff
new file mode 100644
index 0000000..fa2ba5d
--- /dev/null
+++ b/debian/patches/debian/cross-build.diff
@@ -0,0 +1,34 @@
+Description: Use the proper tools for cross-building.
+ Mostly based on a Ubuntu patch by Matthias Klose <doko@ubuntu.com>, but
+ rebased onto the Debian compile-config patch that obviates the need for
+ preseeding the results of the 64-bit, vsprintf, and stdint.h checks.
+Forwarded: not yet
+Author: Peter Pentchev <roam@ringlet.net>
+Last-Update: 2014-07-30
+
+Index: ustr-1.0.4/Makefile
+===================================================================
+--- ustr-1.0.4.orig/Makefile
++++ ustr-1.0.4/Makefile
+@@ -28,10 +28,20 @@ MBINDIR=$(libexecdir)/ustr-$(VERS_FULL)
+ ###############################################################################
+ HIDE=@
+ 
+-CC = cc
++DEB_HOST_GNU_TYPE := $(shell dpkg-architecture -qDEB_HOST_GNU_TYPE)
++DEB_HOST_MULTIARCH := $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)
++DEB_HOST_ARCH := $(shell dpkg-architecture -qDEB_HOST_ARCH)
++DEB_BUILD_ARCH := $(shell dpkg-architecture -qDEB_BUILD_ARCH)
++CC = $(DEB_HOST_GNU_TYPE)-gcc
++ifneq ($(DEB_BUILD_ARCH),$(DEB_HOST_ARCH))
++AR = $(DEB_HOST_GNU_TYPE)-ar
++RANLIB = $(DEB_HOST_GNU_TYPE)-ranlib
++LDCONFIG = true
++else
+ AR = ar
+ RANLIB = ranlib
+ LDCONFIG = /sbin/ldconfig
++endif
+ 
+ CFLAGS  = -O2 -g
+ 
diff --git a/debian/patches/series b/debian/patches/series
index ab05311..57d0d0a 100644
--- a/debian/patches/series
+++ b/debian/patches/series
@@ -4,3 +4,4 @@ fixes/man-cleanup.diff -p1
 fixes/man-spelling.diff -p1
 fixes/nonlinux.diff -p1
 debian/config-compile.diff -p1
+debian/cross-build.diff -p1
-- 
1.7.1
EOF
}
cross_build ustr
echo "progress-mark:64:ustr cross build"
# needed by libsemanage

builddep_flex() {
	$APT_GET build-dep "-a$1" --arch-only flex
	$APT_GET install flex # needs Build-Depends: flex <profile.cross>
}
patch_flex() {
	echo "patching flex to not run host arch executables #762180"
	patch -p1 <<'EOF'
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
echo "progress-mark:65:flex cross build"
# needed by pam

builddep_glib2_0() {
	# python-dbus dependency unsatisifable
	$APT_GET install debhelper cdbs dh-autoreconf pkg-config gettext autotools-dev gnome-pkg-tools dpkg-dev "libelfg0-dev:$1" "libpcre3-dev:$1" desktop-file-utils gtk-doc-tools "libselinux1-dev:$1" "linux-libc-dev:$1" "zlib1g-dev:$1" dbus dbus-x11 shared-mime-info xterm python python-dbus python-gi libxml2-utils "libffi-dev:$1"
	$APT_GET install libglib2.0-dev # missing B-D on libglib2.0-dev:any <profile.cross>
}
export glib_cv_stack_grows=no
export glib_cv_uscore=no
export ac_cv_func_posix_getgrgid_r=yes
export ac_cv_func_posix_getpwuid_r=yes
cross_build glib2.0
unset glib_cv_stack_grows
unset glib_cv_uscore
unset ac_cv_func_posix_getpwuid_r
unset ac_cv_func_posix_getgrgid_r
echo "progress-mark:66:glib2.0 cross build"
# needed by pkg-config, dbus, systemd, libxt

cross_build libxau
echo "progress-mark:67:libxau cross build"
# needed by libxcb

patch_libxdmcp() {
	echo "patching libxdmcp to work around #761628"
	patch -p1 <<'EOF'
--- libxdmcp-1.1.1.orig/doc/xdmcp.xml
+++ libxdmcp-1.1.1/doc/xdmcp.xml
@@ -23,7 +23,7 @@
 <bookinfo>
    <title>X Display Manager Control Protocol</title>
    <subtitle>X.Org Standard</subtitle>
-   <releaseinfo>X Version 11, Release &fullrelvers;</releaseinfo>
+   <releaseinfo>X Version 11, Release 7.6</releaseinfo>
    <releaseinfo>Version 1.1</releaseinfo>
    <authorgroup>
    <author>
EOF
}
cross_build libxdmcp
echo "progress-mark:68:libxdmcp cross build"
# needed by libxcb

cross_build libpthread-stubs
echo "progress-mark:69:libpthread-stubs cross build"
# needed by libxcb

builddep_libxcb() {
	# check dependency lacks nocheck profile annotation
	$APT_GET install "libxau-dev:$1" "libxdmcp-dev:$1" xcb-proto "libpthread-stubs0-dev:$1" debhelper pkg-config xsltproc  python-xcbgen libtool automake python dctrl-tools
}
cross_build libxcb
echo "progress-mark:70:libxcb cross build"
# needed by libx11

export xorg_cv_malloc0_returns_null=no
cross_build libx11
unset xorg_cv_malloc0_returns_null
echo "progress-mark:71:libx11 cross build"
# needed by groff, dbus

cross_build libice
echo "progress-mark:72:libice cross build"
# needed by libsm
