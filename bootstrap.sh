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
REPODIR=/tmp/repo
APT_GET="apt-get --no-install-recommends -y"
DEFAULT_PROFILES=cross
LIBC_NAME=eglibc

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

for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
	test -f "$f" && sed -i "s/^deb /deb [ arch-=$HOST_ARCH ] /" $f
done
grep -q '^deb-src ' /etc/apt/sources.list || echo "deb-src $MIRROR sid main" >> /etc/apt/sources.list

dpkg --add-architecture $HOST_ARCH
apt-get update
$APT_GET install pinentry-curses # avoid installing pinentry-gtk (via reprepro)
$APT_GET install build-essential reprepro

if test -z "$GCC_VER"; then
	GCC_VER=`apt-cache depends gcc | sed 's/^ *Depends: gcc-\([0-9.]*\)$/\1/;t;d'`
fi

if test -z "$HOST_ARCH" || ! dpkg-architecture -a$HOST_ARCH; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
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
			"builddep_$mangledpkg" "$profiles"
		else
			echo "installing Build-Depends for $pkg using apt-get build-dep"
			$APT_GET build-dep -a$HOST_ARCH --arch-only -P "$profiles" "$pkg"
		fi
		cross_build_setup "$pkg"
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
patch_gcc_4_9() {
	if test "$GCC_VER" = "4.8"; then
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
	fi
	if test "$GCC_VER" = "4.8"; then
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
	fi
}
patch_gcc_4_8() {
	patch_gcc_4_9
}
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
if test "`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_ARCH_OS`" = "linux"; then
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
	$APT_GET install debhelper gawk patchutils bison flex python realpath lsb-release quilt libc6-dbg libtool autoconf2.64 zlib1g-dev gperf texinfo locales sharutils procps libantlr-java libffi-dev fastjar libmagic-dev libecj-java zip libasound2-dev libxtst-dev libxt-dev libgtk2.0-dev libart-2.0-dev libcairo2-dev netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen chrpath binutils-multiarch binutils$HOST_ARCH_SUFFIX linux-libc-dev:$HOST_ARCH
	cross_build_setup "gcc-$GCC_VER" gcc1
	dpkg-checkbuilddeps -B || : # tell unmet build depends
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_TARGET_ARCH=$HOST_ARCH DEB_STAGE=stage1 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -B || : # tell unmet build depends again after rewriting control
		DEB_TARGET_ARCH=$HOST_ARCH DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us
	else
		DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -B || : # tell unmet build depends again after rewriting control
		DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us
	fi
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET remove gcc-multilib
	rm -vf *multilib*.deb
	dpkg -i cpp-$GCC_VER-*.deb gcc-$GCC_VER-*.deb
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
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

# $LIBC_NAME looks for linux headers in /usr/<triplet>/include/linux rather than /usr/include/linux
# later gcc looks for pthread.h and stuff in /usr/<triplet>/include rather than /usr/include
mkdir -p /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`
ln -s ../include /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`/include
ln -s ../include/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH` /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`/sys-include

# libc
patch_libc_common() {
	echo "fixing glibc make ftbfs #747013"
	sed -i 's/\(3\.\[89\]\*\))/\1 | 4.*)/' configure
	echo "patching eglibc to avoid dependency on libc6 from libc6-dev in stage1"
	patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/control.in/libc eglibc-2.18/debian/control.in/libc
--- eglibc-2.18/debian/control.in/libc
+++ eglibc-2.18/debian/control.in/libc
@@ -28,7 +28,7 @@
 Section: libdevel
 Priority: optional
 Multi-Arch: same
-Depends: @libc@ (= \${binary:Version}), libc-dev-bin (= \${binary:Version}), \${misc:Depends}, linux-libc-dev [linux-any], kfreebsd-kernel-headers (>= 0.11) [kfreebsd-any], gnumach-dev [hurd-i386], hurd-dev (>= 20080607-3) [hurd-i386]
+Depends: @nobootstrap@ @libc@ (= \${binary:Version}), libc-dev-bin (= \${binary:Version}), \${misc:Depends}, linux-libc-dev [linux-any], kfreebsd-kernel-headers (>= 0.11) [kfreebsd-any], gnumach-dev [hurd-i386], hurd-dev (>= 20080607-3) [hurd-i386]
 Replaces: hurd-dev (<< 20120408-3) [hurd-i386]
 Recommends: gcc | c-compiler
 Suggests: glibc-doc, manpages-dev
diff -Nru eglibc-2.18/debian/rules.d/control.mk eglibc-2.18/debian/rules.d/control.mk
--- eglibc-2.18/debian/rules.d/control.mk
+++ eglibc-2.18/debian/rules.d/control.mk
@@ -42,6 +42,10 @@
 	cat debian/control.in/opt		>> \$@T
 	cat debian/control.in/libnss-dns-udeb	>> \$@T
 	cat debian/control.in/libnss-files-udeb	>> \$@T
-	sed -e 's%@libc@%\$(libc)%g' < \$@T > debian/control
+ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@[^,]*,%%g' < \$@T > debian/control
+else
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@%%g' < \$@T > debian/control
+endif
 	rm \$@T
 	touch \$@
EOF
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
 	\${CC} -nostdlib -nostartfiles -shared -x c /dev/null \\
-	        -o \$(CURDIR)/debian/tmp-\$(curpass)/lib/libc.so
+	        -o \$(CURDIR)/debian/tmp-\$(curpass)/\$(call xx,libdir)/libc.so
 else
 	: # FIXME: why just needed for ARM multilib?
 	case "\$(curpass)" in \\
diff -Nru eglibc-2.18/debian/rules.d/debhelper.mk eglibc-2.18/debian/rules.d/debhelper.mk
--- eglibc-2.18/debian/rules.d/debhelper.mk
+++ eglibc-2.18/debian/rules.d/debhelper.mk
@@ -208,7 +208,8 @@
 
 	egrep -v "LIBDIR.*.a " debian/\$(libc)-dev.install >debian/\$(libc)-dev.install-
 	mv debian/\$(libc)-dev.install- debian/\$(libc)-dev.install
-	sed -e "s#LIBDIR#lib#g" -i debian/\$(libc)-dev.install
+	libdir=\$(call xx,libdir) ; \\
+	sed -e "s#LIBDIR#\$\$libdir#g" -i debian/\$(libc)-dev.install
 else
 \$(patsubst %,debhelper_%,\$(EGLIBC_PASSES)) :: debhelper_% : \$(stamp)debhelper_%
 \$(stamp)debhelper_%: \$(stamp)debhelper-common \$(stamp)install_%
EOF
	echo "patching eglibc to build without selinux in stage2 #742640"
	case `dpkg-parsechangelog --show-field Version` in
		2.18-*)
			patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/sysdeps/linux.mk eglibc-2.18/debian/sysdeps/linux.mk
--- eglibc-2.18/debian/sysdeps/linux.mk
+++ eglibc-2.18/debian/sysdeps/linux.mk
@@ -12,7 +12,11 @@
 ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
   libc_extra_config_options = \$(extra_config_options)
 else
-  libc_extra_config_options = --with-selinux \$(extra_config_options)
+  ifneq (\$(filter stage2,\$(DEB_BUILD_PROFILES)),)
+    libc_extra_config_options = \$(extra_config_options)
+  else 
+    libc_extra_config_options = --with-selinux \$(extra_config_options)
+  endif
 endif
 
 ifndef LINUX_SOURCE
EOF
		;;
		2.19-*)
			patch -p1 <<EOF
diff -Nru eglibc-2.19/debian/sysdeps/linux.mk eglibc-2.19/debian/sysdeps/linux.mk
--- eglibc-2.19/debian/sysdeps/linux.mk
+++ eglibc-2.19/debian/sysdeps/linux.mk
@@ -12,7 +12,11 @@
 ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
   libc_extra_config_options = \$(extra_config_options)
 else
-  libc_extra_config_options = --with-selinux --enable-systemtap \$(extra_config_options)
+  ifneq (\$(filter stage2,\$(DEB_BUILD_PROFILES)),)
+    libc_extra_config_options = \$(extra_config_options)
+  else 
+    libc_extra_config_options = --with-selinux --enable-systemtap \$(extra_config_options)
+  endif
 endif
 
 ifndef LINUX_SOURCE
EOF
		;;
		*)
			echo "unknown glibc version"
			exit 1
		;;
	esac
	echo "patching eglibc to not depend on libgcc in stage2"
	patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/control.in/libc eglibc-2.18/debian/control.in/libc
--- eglibc-2.18/debian/control.in/libc
+++ eglibc-2.18/debian/control.in/libc
@@ -3,7 +3,7 @@
 Section: libs
 Priority: required
 Multi-Arch: same
-Depends: \${shlibs:Depends}, libgcc1 [!hppa !m68k], libgcc2 [m68k], libgcc4 [hppa]
+Depends: @nostage2@ libgcc1 [!hppa !m68k], @nostage2@ libgcc2 [m68k], @nostage2@ libgcc4 [hppa], \${shlibs:Depends}
 Recommends: libc6-i686 [i386], libc0.1-i686 [kfreebsd-i386], libc0.3-i686 [hurd-i386] 
 Suggests: glibc-doc, debconf | debconf-2.0, locales [!hurd-i386]
 Provides: \${locale-compat:Depends}, libc6-sparcv9b [sparc sparc64]
diff -Nru eglibc-2.18/debian/rules.d/control.mk eglibc-2.18/debian/rules.d/control.mk
--- eglibc-2.18/debian/rules.d/control.mk
+++ eglibc-2.18/debian/rules.d/control.mk
@@ -45,7 +45,11 @@
 ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
-	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@[^,]*,%%g' < \$@T > debian/control
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@[^,]*,%%g;s%@nostage2@%%g' < \$@T > debian/control
 else
-	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@%%g' < \$@T > debian/control
+ifneq (\$(filter stage2,\$(DEB_BUILD_PROFILES)),)
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@%%g;s%@nostage2@[^,]*,%%g' < \$@T > debian/control
+else
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@%%g;s%@nostage2@%%g' < \$@T > debian/control
+endif
 endif
 	rm \$@T
 	touch \$@
EOF
	if test "$HOST_ARCH" = "i386"; then
		echo "patching eglibc to avoid installing xen stuff in stage1 that wasn't built #743676"
		patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/sysdeps/i386.mk eglibc-2.18/debian/sysdeps/i386.mk
--- eglibc-2.18/debian/sysdeps/i386.mk
+++ eglibc-2.18/debian/sysdeps/i386.mk
@@ -51,11 +51,13 @@
 	debian/tmp-libc/usr/bin
 endef
 
+ifneq (\$(DEB_BUILD_PROFILE),bootstrap)
 define libc6-dev_extra_pkg_install
 mkdir -p debian/libc6-dev/\$(libdir)/xen
 cp -af debian/tmp-xen/\$(libdir)/*.a \\
 	debian/libc6-dev/\$(libdir)/xen
 endef
+endif
 
 define libc6-dev-amd64_extra_pkg_install
 
EOF
	fi
	if test "$HOST_ARCH" = "i386"; then
		echo "patching eglibc to avoid installing xen stuff in stage2 that wasn't built"
		patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/sysdeps/i386.mk eglibc-2.18/debian/sysdeps/i386.mk
--- eglibc-2.18/debian/sysdeps/i386.mk
+++ eglibc-2.18/debian/sysdeps/i386.mk
@@ -52,11 +52,13 @@
 endef
 
 ifneq (\$(DEB_BUILD_PROFILE),bootstrap)
+ifeq (\$(filter stage2,\$(DEB_BUILD_PROFILES)),)
 define libc6-dev_extra_pkg_install
 mkdir -p debian/libc6-dev/\$(libdir)/xen
 cp -af debian/tmp-xen/\$(libdir)/*.a \\
 	debian/libc6-dev/\$(libdir)/xen
 endef
+endif
 endif
 
 define libc6-dev-amd64_extra_pkg_install
EOF
	fi
}
patch_eglibc() {
	patch_libc_common
	echo "patching eglibc to avoid multilib for bootstrap profile"
	patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/rules eglibc-2.18/debian/rules
--- eglibc-2.18/debian/rules
+++ eglibc-2.18/debian/rules
@@ -196,6 +196,11 @@
   endif
 endif
 
+ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
+override EGLIBC_PASSES = libc
+override DEB_ARCH_REGULAR_PACKAGES = \$(libc)-dev
+endif
+
 # And now the rules...
 include debian/rules.d/*.mk
 
EOF
	echo "patching eglibc to not build multilib in the nobiarch profile #745380"
	patch -p1 <<EOF
diff -Nru eglibc-2.18/debian/rules eglibc-2.18/debian/rules
--- eglibc-2.18/debian/rules
+++ eglibc-2.18/debian/rules
@@ -173,6 +173,11 @@
 -include debian/sysdeps/\$(DEB_HOST_ARCH_OS).mk
 -include debian/sysdeps/\$(DEB_HOST_ARCH).mk
 
+# build multilib packages unless build is staged
+ifeq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+DEB_ARCH_REGULAR_PACKAGES += \$(DEB_ARCH_MULTILIB_PACKAGES)
+endif
+
 # Don't run dh_strip on this package
 NOSTRIP_\$(libc)-dbg = 1
 
@@ -201,6 +206,10 @@
 override DEB_ARCH_REGULAR_PACKAGES = \$(libc)-dev
 endif
 
+ifneq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+override EGLIBC_PASSES = libc
+endif
+
 # And now the rules...
 include debian/rules.d/*.mk
 
diff -Nru eglibc-2.18/debian/sysdeps/alpha.mk eglibc-2.18/debian/sysdeps/alpha.mk
--- eglibc-2.18/debian/sysdeps/alpha.mk
+++ eglibc-2.18/debian/sysdeps/alpha.mk
@@ -4,7 +4,7 @@
 
 # build an ev67 optimized library
 EGLIBC_PASSES += alphaev67
-DEB_ARCH_REGULAR_PACKAGES += libc6.1-alphaev67
+DEB_ARCH_MULTILIB_PACKAGES += libc6.1-alphaev67
 alphaev67_add-ons = ports nptl \$(add-ons)
 alphaev67_configure_target = alphaev67-linux-gnu
 alphaev67_extra_cflags = -mcpu=ev67 -mtune=ev67 -O2
diff -Nru eglibc-2.18/debian/sysdeps/amd64.mk eglibc-2.18/debian/sysdeps/amd64.mk
--- eglibc-2.18/debian/sysdeps/amd64.mk
+++ eglibc-2.18/debian/sysdeps/amd64.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (i386) alternative library
 EGLIBC_PASSES += i386
-DEB_ARCH_REGULAR_PACKAGES += libc6-i386 libc6-dev-i386
+DEB_ARCH_MULTILIB_PACKAGES += libc6-i386 libc6-dev-i386
 libc6-i386_shlib_dep = libc6-i386 (>= \$(shlib_dep_ver))
 i386_add-ons = nptl \$(add-ons)
 i386_configure_target = i686-linux-gnu
@@ -39,7 +39,7 @@
 
 # build x32 ABI alternative library
 EGLIBC_PASSES += x32
-DEB_ARCH_REGULAR_PACKAGES += libc6-x32 libc6-dev-x32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-x32 libc6-dev-x32
 libc6-x32_shlib_dep = libc6-x32 (>= \$(shlib_dep_ver))
 x32_add-ons = nptl \$(add-ons)
 x32_configure_target = x86_64-linux-gnux32
diff -Nru eglibc-2.18/debian/sysdeps/armel.mk eglibc-2.18/debian/sysdeps/armel.mk
--- eglibc-2.18/debian/sysdeps/armel.mk
+++ eglibc-2.18/debian/sysdeps/armel.mk
@@ -2,7 +2,7 @@
 extra_config_options = --enable-multi-arch
 
 #EGLIBC_PASSES += armhf
-#DEB_ARCH_REGULAR_PACKAGES += libc6-armhf libc6-dev-armhf
+#DEB_ARCH_MULTILIB_PACKAGES += libc6-armhf libc6-dev-armhf
 #armhf_add-ons = ports nptl \$(add-ons)
 #armhf_configure_target = arm-linux-gnueabihf
 #armhf_CC = \$(CC) -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard
diff -Nru eglibc-2.18/debian/sysdeps/armhf.mk eglibc-2.18/debian/sysdeps/armhf.mk
--- eglibc-2.18/debian/sysdeps/armhf.mk
+++ eglibc-2.18/debian/sysdeps/armhf.mk
@@ -13,7 +13,7 @@
 endef
 
 #EGLIBC_PASSES += armel
-#DEB_ARCH_REGULAR_PACKAGES += libc6-armel libc6-dev-armel
+#DEB_ARCH_MULTILIB_PACKAGES += libc6-armel libc6-dev-armel
 #armel_add-ons = ports nptl \$(add-ons)
 #armel_configure_target = arm-linux-gnueabi
 #armel_CC = \$(CC) -mfloat-abi=soft
diff -Nru eglibc-2.18/debian/sysdeps/hurd-i386.mk eglibc-2.18/debian/sysdeps/hurd-i386.mk
--- eglibc-2.18/debian/sysdeps/hurd-i386.mk
+++ eglibc-2.18/debian/sysdeps/hurd-i386.mk
@@ -1,7 +1,7 @@
 # We use -march=i686 and glibc's i686 routines use cmov, so require it.
 # A Debian-local glibc patch adds cmov to the search path.
 EGLIBC_PASSES += i686
-DEB_ARCH_REGULAR_PACKAGES += libc0.3-i686
+DEB_ARCH_MULTILIB_PACKAGES += libc0.3-i686
 i686_add-ons = \$(libc_add-ons)
 i686_configure_target=i686-gnu
 i686_extra_cflags = -march=i686 -mtune=generic
diff -Nru eglibc-2.18/debian/sysdeps/i386.mk eglibc-2.18/debian/sysdeps/i386.mk
--- eglibc-2.18/debian/sysdeps/i386.mk
+++ eglibc-2.18/debian/sysdeps/i386.mk
@@ -4,7 +4,7 @@
 # A Debian-local glibc patch adds cmov to the search path.
 # The optimized libraries also use NPTL!
 EGLIBC_PASSES += i686
-DEB_ARCH_REGULAR_PACKAGES += libc6-i686
+DEB_ARCH_MULTILIB_PACKAGES += libc6-i686
 i686_add-ons = nptl \$(add-ons)
 i686_configure_target=i686-linux-gnu
 i686_extra_cflags = -march=i686 -mtune=generic
@@ -33,7 +33,7 @@
 
 # build 64-bit (amd64) alternative library
 EGLIBC_PASSES += amd64
-DEB_ARCH_REGULAR_PACKAGES += libc6-amd64 libc6-dev-amd64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-amd64 libc6-dev-amd64
 libc6-amd64_shlib_dep = libc6-amd64 (>= \$(shlib_dep_ver))
 amd64_add-ons = nptl \$(add-ons)
 amd64_configure_target = x86_64-linux-gnu
@@ -77,7 +77,7 @@
 
 # build x32 ABI alternative library
 EGLIBC_PASSES += x32
-DEB_ARCH_REGULAR_PACKAGES += libc6-x32 libc6-dev-x32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-x32 libc6-dev-x32
 libc6-x32_shlib_dep = libc6-x32 (>= \$(shlib_dep_ver))
 x32_add-ons = nptl \$(add-ons)
 x32_configure_target = x86_64-linux-gnux32
diff -Nru eglibc-2.18/debian/sysdeps/kfreebsd-amd64.mk eglibc-2.18/debian/sysdeps/kfreebsd-amd64.mk
--- eglibc-2.18/debian/sysdeps/kfreebsd-amd64.mk
+++ eglibc-2.18/debian/sysdeps/kfreebsd-amd64.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (i386) alternative library
 EGLIBC_PASSES += i386
-DEB_ARCH_REGULAR_PACKAGES += libc0.1-i386 libc0.1-dev-i386
+DEB_ARCH_MULTILIB_PACKAGES += libc0.1-i386 libc0.1-dev-i386
 libc0.1-i386_shlib_dep = libc0.1-i386 (>= \$(shlib_dep_ver))
 
 i386_configure_target = i686-kfreebsd-gnu
diff -Nru eglibc-2.18/debian/sysdeps/kfreebsd-i386.mk eglibc-2.18/debian/sysdeps/kfreebsd-i386.mk
--- eglibc-2.18/debian/sysdeps/kfreebsd-i386.mk
+++ eglibc-2.18/debian/sysdeps/kfreebsd-i386.mk
@@ -3,7 +3,7 @@
 
 # Build a 32-bit optimized library
 EGLIBC_PASSES += i686
-DEB_ARCH_REGULAR_PACKAGES += libc0.1-i686
+DEB_ARCH_MULTILIB_PACKAGES += libc0.1-i686
 
 # We use -march=i686 and glibc's i686 routines use cmov, so require it.
 # A Debian-local glibc patch adds cmov to the search path.
diff -Nru eglibc-2.18/debian/sysdeps/mips.mk eglibc-2.18/debian/sysdeps/mips.mk
--- eglibc-2.18/debian/sysdeps/mips.mk
+++ eglibc-2.18/debian/sysdeps/mips.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (n32) alternative library
 EGLIBC_PASSES += mipsn32
-DEB_ARCH_REGULAR_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
 mipsn32_add-ons = ports nptl \$(add-ons)
 mipsn32_configure_target = mips32-linux-gnu
 mipsn32_extra_cflags = -mno-plt
@@ -17,7 +17,7 @@
 
 # build 64-bit alternative library
 EGLIBC_PASSES += mips64
-DEB_ARCH_REGULAR_PACKAGES += libc6-mips64 libc6-dev-mips64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mips64 libc6-dev-mips64
 mips64_add-ons = ports nptl \$(add-ons)
 mips64_configure_target = mips64-linux-gnu
 mips64_extra_cflags = -mno-plt
diff -Nru eglibc-2.18/debian/sysdeps/mipsel.mk eglibc-2.18/debian/sysdeps/mipsel.mk
--- eglibc-2.18/debian/sysdeps/mipsel.mk
+++ eglibc-2.18/debian/sysdeps/mipsel.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (n32) alternative library
 EGLIBC_PASSES += mipsn32
-DEB_ARCH_REGULAR_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
 mipsn32_add-ons = ports nptl \$(add-ons)
 mipsn32_configure_target = mips32el-linux-gnu
 mipsn32_extra_cflags = -mno-plt
@@ -17,7 +17,7 @@
 
 # build 64-bit alternative library
 EGLIBC_PASSES += mips64
-DEB_ARCH_REGULAR_PACKAGES += libc6-mips64 libc6-dev-mips64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mips64 libc6-dev-mips64
 mips64_add-ons = ports nptl \$(add-ons)
 mips64_configure_target = mips64el-linux-gnu
 mips64_extra_cflags = -mno-plt
@@ -57,7 +57,7 @@
 
 # build a loongson-2f optimized library
 EGLIBC_PASSES += loongson2f
-DEB_ARCH_REGULAR_PACKAGES += libc6-loongson2f
+DEB_ARCH_MULTILIB_PACKAGES += libc6-loongson2f
 loongson2f_add-ons = ports nptl \$(add-ons)
 loongson2f_configure_target = mips32el-linux-gnu
 loongson2f_CC = \$(CC) -mabi=32
diff -Nru eglibc-2.18/debian/sysdeps/powerpc.mk eglibc-2.18/debian/sysdeps/powerpc.mk
--- eglibc-2.18/debian/sysdeps/powerpc.mk
+++ eglibc-2.18/debian/sysdeps/powerpc.mk
@@ -2,7 +2,7 @@
 
 # build 64-bit (ppc64) alternative library
 EGLIBC_PASSES += ppc64
-DEB_ARCH_REGULAR_PACKAGES += libc6-ppc64 libc6-dev-ppc64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-ppc64 libc6-dev-ppc64
 ppc64_add-ons = nptl \$(add-ons)
 ppc64_configure_target = powerpc64-linux-gnu
 ppc64_CC = \$(CC) -m64
diff -Nru eglibc-2.18/debian/sysdeps/ppc64.mk eglibc-2.18/debian/sysdeps/ppc64.mk
--- eglibc-2.18/debian/sysdeps/ppc64.mk
+++ eglibc-2.18/debian/sysdeps/ppc64.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (powerpc) alternative library
 EGLIBC_PASSES += powerpc
-DEB_ARCH_REGULAR_PACKAGES += libc6-powerpc libc6-dev-powerpc
+DEB_ARCH_MULTILIB_PACKAGES += libc6-powerpc libc6-dev-powerpc
 libc6-powerpc_shlib_dep = libc6-powerpc (>= \$(shlib_dep_ver))
 powerpc_add-ons = nptl \$(add-ons)
 powerpc_configure_target = powerpc-linux-gnu
diff -Nru eglibc-2.18/debian/sysdeps/s390x.mk eglibc-2.18/debian/sysdeps/s390x.mk
--- eglibc-2.18/debian/sysdeps/s390x.mk
+++ eglibc-2.18/debian/sysdeps/s390x.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (s390) alternative library
 EGLIBC_PASSES += s390
-DEB_ARCH_REGULAR_PACKAGES += libc6-s390 libc6-dev-s390
+DEB_ARCH_MULTILIB_PACKAGES += libc6-s390 libc6-dev-s390
 s390_add-ons = nptl \$(add-ons)
 s390_configure_target = s390-linux-gnu
 s390_CC = \$(CC) -m31
diff -Nru eglibc-2.18/debian/sysdeps/sparc.mk eglibc-2.18/debian/sysdeps/sparc.mk
--- eglibc-2.18/debian/sysdeps/sparc.mk
+++ eglibc-2.18/debian/sysdeps/sparc.mk
@@ -1,8 +1,8 @@
 extra_config_options = --enable-multi-arch
 
 # build 64-bit (sparc64) alternative library
 EGLIBC_PASSES += sparc64
-DEB_ARCH_REGULAR_PACKAGES += libc6-sparc64 libc6-dev-sparc64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-sparc64 libc6-dev-sparc64
 sparc64_add-ons = nptl \$(add-ons)
 sparc64_configure_target=sparc64-linux-gnu
 sparc64_CC = \$(CC) -m64
diff -Nru eglibc-2.18/debian/sysdeps/sparc64.mk eglibc-2.18/debian/sysdeps/sparc64.mk
--- eglibc-2.18/debian/sysdeps/sparc64.mk
+++ eglibc-2.18/debian/sysdeps/sparc64.mk
@@ -4,7 +4,7 @@
 
 # build 32-bit (sparc) alternative library
 EGLIBC_PASSES += sparc
-DEB_ARCH_REGULAR_PACKAGES += libc6-sparc libc6-dev-sparc
+DEB_ARCH_MULTILIB_PACKAGES += libc6-sparc libc6-dev-sparc
 sparc_add-ons = nptl \$(add-ons)
 sparc_configure_target=sparc-linux-gnu
 sparc_CC = \$(CC) -m32
diff -Nru eglibc-2.18/debian/sysdeps/x32.mk eglibc-2.18/debian/sysdeps/x32.mk
--- eglibc-2.18/debian/sysdeps/x32.mk
+++ eglibc-2.18/debian/sysdeps/x32.mk
@@ -1,9 +1,9 @@
 libc_rtlddir = /libx32
 extra_config_options = --enable-multi-arch
 
 # build 64-bit (amd64) alternative library
 EGLIBC_PASSES += amd64
-DEB_ARCH_REGULAR_PACKAGES += libc6-amd64 libc6-dev-amd64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-amd64 libc6-dev-amd64
 libc6-amd64_shlib_dep = libc6-amd64 (>= \$(shlib_dep_ver))
 amd64_add-ons = nptl \$(add-ons)
 amd64_configure_target = x86_64-linux-gnu
@@ -34,7 +35,7 @@
 
 # build 32-bit (i386) alternative library
 EGLIBC_PASSES += i386
-DEB_ARCH_REGULAR_PACKAGES += libc6-i386 libc6-dev-i386
+DEB_ARCH_MULTILIB_PACKAGES += libc6-i386 libc6-dev-i386
 libc6-i386_shlib_dep = libc6-i386 (>= \$(shlib_dep_ver))
 i386_add-ons = nptl \$(add-ons)
 i386_configure_target = i686-linux-gnu
EOF
}
patch_glibc() {
	patch_libc_common
	echo "patching glibc to avoid multilib for bootstrap profile"
	patch -p1 <<EOF
diff -Nru glibc-2.19/debian/rules glibc-2.19/debian/rules
--- glibc-2.19/debian/rules
+++ glibc-2.19/debian/rules
@@ -196,6 +196,11 @@
   endif
 endif
 
+ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
+override GLIBC_PASSES = libc
+override DEB_ARCH_REGULAR_PACKAGES = \$(libc)-dev
+endif
+
 # And now the rules...
 include debian/rules.d/*.mk
 
EOF
	echo "patching glibc to not build multilib in the nobiarch profile #745380"
	patch -p1 <<EOF
diff -Nru glibc-2.19/debian/rules glibc-2.19/debian/rules
--- glibc-2.19/debian/rules
+++ glibc-2.19/debian/rules
@@ -173,6 +173,11 @@
 -include debian/sysdeps/\$(DEB_HOST_ARCH_OS).mk
 -include debian/sysdeps/\$(DEB_HOST_ARCH).mk
 
+# build multilib packages unless build is staged
+ifeq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+DEB_ARCH_REGULAR_PACKAGES += \$(DEB_ARCH_MULTILIB_PACKAGES)
+endif
+
 # Don't run dh_strip on this package
 NOSTRIP_\$(libc)-dbg = 1
 
@@ -201,6 +206,10 @@
 override DEB_ARCH_REGULAR_PACKAGES = \$(libc)-dev
 endif
 
+ifneq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+override GLIBC_PASSES = libc
+endif
+
 # And now the rules...
 include debian/rules.d/*.mk
 
diff -Nru glibc-2.19/debian/sysdeps/alpha.mk glibc-2.19/debian/sysdeps/alpha.mk
--- glibc-2.19/debian/sysdeps/alpha.mk
+++ glibc-2.19/debian/sysdeps/alpha.mk
@@ -4,7 +4,7 @@
 
 # build an ev67 optimized library
 GLIBC_PASSES += alphaev67
-DEB_ARCH_REGULAR_PACKAGES += libc6.1-alphaev67
+DEB_ARCH_MULTILIB_PACKAGES += libc6.1-alphaev67
 alphaev67_add-ons = ports nptl \$(add-ons)
 alphaev67_configure_target = alphaev67-linux-gnu
 alphaev67_extra_cflags = -mcpu=ev67 -mtune=ev67 -O2
diff -Nru glibc-2.19/debian/sysdeps/amd64.mk glibc-2.19/debian/sysdeps/amd64.mk
--- glibc-2.19/debian/sysdeps/amd64.mk
+++ glibc-2.19/debian/sysdeps/amd64.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (i386) alternative library
 GLIBC_PASSES += i386
-DEB_ARCH_REGULAR_PACKAGES += libc6-i386 libc6-dev-i386
+DEB_ARCH_MULTILIB_PACKAGES += libc6-i386 libc6-dev-i386
 libc6-i386_shlib_dep = libc6-i386 (>= \$(shlib_dep_ver))
 i386_add-ons = nptl \$(add-ons)
 i386_configure_target = i686-linux-gnu
@@ -39,7 +39,7 @@
 
 # build x32 ABI alternative library
 GLIBC_PASSES += x32
-DEB_ARCH_REGULAR_PACKAGES += libc6-x32 libc6-dev-x32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-x32 libc6-dev-x32
 libc6-x32_shlib_dep = libc6-x32 (>= \$(shlib_dep_ver))
 x32_add-ons = nptl \$(add-ons)
 x32_configure_target = x86_64-linux-gnux32
diff -Nru glibc-2.19/debian/sysdeps/armel.mk glibc-2.19/debian/sysdeps/armel.mk
--- glibc-2.19/debian/sysdeps/armel.mk
+++ glibc-2.19/debian/sysdeps/armel.mk
@@ -2,7 +2,7 @@
 extra_config_options = --enable-multi-arch
 
 #GLIBC_PASSES += armhf
-#DEB_ARCH_REGULAR_PACKAGES += libc6-armhf libc6-dev-armhf
+#DEB_ARCH_MULTILIB_PACKAGES += libc6-armhf libc6-dev-armhf
 #armhf_add-ons = ports nptl \$(add-ons)
 #armhf_configure_target = arm-linux-gnueabihf
 #armhf_CC = \$(CC) -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard
diff -Nru glibc-2.19/debian/sysdeps/armhf.mk glibc-2.19/debian/sysdeps/armhf.mk
--- glibc-2.19/debian/sysdeps/armhf.mk
+++ glibc-2.19/debian/sysdeps/armhf.mk
@@ -13,7 +13,7 @@
 endef
 
 #GLIBC_PASSES += armel
-#DEB_ARCH_REGULAR_PACKAGES += libc6-armel libc6-dev-armel
+#DEB_ARCH_MULTILIB_PACKAGES += libc6-armel libc6-dev-armel
 #armel_add-ons = ports nptl \$(add-ons)
 #armel_configure_target = arm-linux-gnueabi
 #armel_CC = \$(CC) -mfloat-abi=soft
diff -Nru glibc-2.19/debian/sysdeps/hurd-i386.mk glibc-2.19/debian/sysdeps/hurd-i386.mk
--- glibc-2.19/debian/sysdeps/hurd-i386.mk
+++ glibc-2.19/debian/sysdeps/hurd-i386.mk
@@ -1,7 +1,7 @@
 # We use -march=i686 and glibc's i686 routines use cmov, so require it.
 # A Debian-local glibc patch adds cmov to the search path.
 GLIBC_PASSES += i686
-DEB_ARCH_REGULAR_PACKAGES += libc0.3-i686
+DEB_ARCH_MULTILIB_PACKAGES += libc0.3-i686
 i686_add-ons = \$(libc_add-ons)
 i686_configure_target=i686-gnu
 i686_extra_cflags = -march=i686 -mtune=generic
diff -Nru glibc-2.19/debian/sysdeps/i386.mk glibc-2.19/debian/sysdeps/i386.mk
--- glibc-2.19/debian/sysdeps/i386.mk
+++ glibc-2.19/debian/sysdeps/i386.mk
@@ -4,7 +4,7 @@
 # A Debian-local glibc patch adds cmov to the search path.
 # The optimized libraries also use NPTL!
 GLIBC_PASSES += i686
-DEB_ARCH_REGULAR_PACKAGES += libc6-i686
+DEB_ARCH_MULTILIB_PACKAGES += libc6-i686
 i686_add-ons = nptl \$(add-ons)
 i686_configure_target=i686-linux-gnu
 i686_extra_cflags = -march=i686 -mtune=generic
@@ -33,7 +33,7 @@
 
 # build 64-bit (amd64) alternative library
 GLIBC_PASSES += amd64
-DEB_ARCH_REGULAR_PACKAGES += libc6-amd64 libc6-dev-amd64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-amd64 libc6-dev-amd64
 libc6-amd64_shlib_dep = libc6-amd64 (>= \$(shlib_dep_ver))
 amd64_add-ons = nptl \$(add-ons)
 amd64_configure_target = x86_64-linux-gnu
@@ -77,7 +77,7 @@
 
 # build x32 ABI alternative library
 GLIBC_PASSES += x32
-DEB_ARCH_REGULAR_PACKAGES += libc6-x32 libc6-dev-x32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-x32 libc6-dev-x32
 libc6-x32_shlib_dep = libc6-x32 (>= \$(shlib_dep_ver))
 x32_add-ons = nptl \$(add-ons)
 x32_configure_target = x86_64-linux-gnux32
diff -Nru glibc-2.19/debian/sysdeps/kfreebsd-amd64.mk glibc-2.19/debian/sysdeps/kfreebsd-amd64.mk
--- glibc-2.19/debian/sysdeps/kfreebsd-amd64.mk
+++ glibc-2.19/debian/sysdeps/kfreebsd-amd64.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (i386) alternative library
 GLIBC_PASSES += i386
-DEB_ARCH_REGULAR_PACKAGES += libc0.1-i386 libc0.1-dev-i386
+DEB_ARCH_MULTILIB_PACKAGES += libc0.1-i386 libc0.1-dev-i386
 libc0.1-i386_shlib_dep = libc0.1-i386 (>= \$(shlib_dep_ver))
 
 i386_configure_target = i686-kfreebsd-gnu
diff -Nru glibc-2.19/debian/sysdeps/kfreebsd-i386.mk glibc-2.19/debian/sysdeps/kfreebsd-i386.mk
--- glibc-2.19/debian/sysdeps/kfreebsd-i386.mk
+++ glibc-2.19/debian/sysdeps/kfreebsd-i386.mk
@@ -3,7 +3,7 @@
 
 # Build a 32-bit optimized library
 GLIBC_PASSES += i686
-DEB_ARCH_REGULAR_PACKAGES += libc0.1-i686
+DEB_ARCH_MULTILIB_PACKAGES += libc0.1-i686
 
 # We use -march=i686 and glibc's i686 routines use cmov, so require it.
 # A Debian-local glibc patch adds cmov to the search path.
diff -Nru glibc-2.19/debian/sysdeps/mips.mk glibc-2.19/debian/sysdeps/mips.mk
--- glibc-2.19/debian/sysdeps/mips.mk
+++ glibc-2.19/debian/sysdeps/mips.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (n32) alternative library
 GLIBC_PASSES += mipsn32
-DEB_ARCH_REGULAR_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
 mipsn32_add-ons = ports nptl \$(add-ons)
 mipsn32_configure_target = mips32-linux-gnu
 mipsn32_extra_cflags = -mno-plt
@@ -17,7 +17,7 @@
 
 # build 64-bit alternative library
 GLIBC_PASSES += mips64
-DEB_ARCH_REGULAR_PACKAGES += libc6-mips64 libc6-dev-mips64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mips64 libc6-dev-mips64
 mips64_add-ons = ports nptl \$(add-ons)
 mips64_configure_target = mips64-linux-gnu
 mips64_extra_cflags = -mno-plt
diff -Nru glibc-2.19/debian/sysdeps/mipsel.mk glibc-2.19/debian/sysdeps/mipsel.mk
--- glibc-2.19/debian/sysdeps/mipsel.mk
+++ glibc-2.19/debian/sysdeps/mipsel.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (n32) alternative library
 GLIBC_PASSES += mipsn32
-DEB_ARCH_REGULAR_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mipsn32 libc6-dev-mipsn32
 mipsn32_add-ons = ports nptl \$(add-ons)
 mipsn32_configure_target = mips32el-linux-gnu
 mipsn32_extra_cflags = -mno-plt
@@ -17,7 +17,7 @@
 
 # build 64-bit alternative library
 GLIBC_PASSES += mips64
-DEB_ARCH_REGULAR_PACKAGES += libc6-mips64 libc6-dev-mips64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-mips64 libc6-dev-mips64
 mips64_add-ons = ports nptl \$(add-ons)
 mips64_configure_target = mips64el-linux-gnu
 mips64_extra_cflags = -mno-plt
@@ -57,7 +57,7 @@
 
 # build a loongson-2f optimized library
 GLIBC_PASSES += loongson2f
-DEB_ARCH_REGULAR_PACKAGES += libc6-loongson2f
+DEB_ARCH_MULTILIB_PACKAGES += libc6-loongson2f
 loongson2f_add-ons = ports nptl \$(add-ons)
 loongson2f_configure_target = mips32el-linux-gnu
 loongson2f_CC = \$(CC) -mabi=32
diff -Nru glibc-2.19/debian/sysdeps/powerpc.mk glibc-2.19/debian/sysdeps/powerpc.mk
--- glibc-2.19/debian/sysdeps/powerpc.mk
+++ glibc-2.19/debian/sysdeps/powerpc.mk
@@ -2,7 +2,7 @@
 
 # build 64-bit (ppc64) alternative library
 GLIBC_PASSES += ppc64
-DEB_ARCH_REGULAR_PACKAGES += libc6-ppc64 libc6-dev-ppc64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-ppc64 libc6-dev-ppc64
 ppc64_add-ons = nptl \$(add-ons)
 ppc64_configure_target = powerpc64-linux-gnu
 ppc64_CC = \$(CC) -m64
diff -Nru glibc-2.19/debian/sysdeps/ppc64.mk glibc-2.19/debian/sysdeps/ppc64.mk
--- glibc-2.19/debian/sysdeps/ppc64.mk
+++ glibc-2.19/debian/sysdeps/ppc64.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (powerpc) alternative library
 GLIBC_PASSES += powerpc
-DEB_ARCH_REGULAR_PACKAGES += libc6-powerpc libc6-dev-powerpc
+DEB_ARCH_MULTILIB_PACKAGES += libc6-powerpc libc6-dev-powerpc
 libc6-powerpc_shlib_dep = libc6-powerpc (>= \$(shlib_dep_ver))
 powerpc_add-ons = nptl \$(add-ons)
 powerpc_configure_target = powerpc-linux-gnu
diff -Nru glibc-2.19/debian/sysdeps/s390x.mk glibc-2.19/debian/sysdeps/s390x.mk
--- glibc-2.19/debian/sysdeps/s390x.mk
+++ glibc-2.19/debian/sysdeps/s390x.mk
@@ -3,7 +3,7 @@
 
 # build 32-bit (s390) alternative library
 GLIBC_PASSES += s390
-DEB_ARCH_REGULAR_PACKAGES += libc6-s390 libc6-dev-s390
+DEB_ARCH_MULTILIB_PACKAGES += libc6-s390 libc6-dev-s390
 s390_add-ons = nptl \$(add-ons)
 s390_configure_target = s390-linux-gnu
 s390_CC = \$(CC) -m31
diff -Nru glibc-2.19/debian/sysdeps/sparc.mk glibc-2.19/debian/sysdeps/sparc.mk
--- glibc-2.19/debian/sysdeps/sparc.mk
+++ glibc-2.19/debian/sysdeps/sparc.mk
@@ -1,8 +1,8 @@
 extra_config_options = --enable-multi-arch
 
 # build 64-bit (sparc64) alternative library
 GLIBC_PASSES += sparc64
-DEB_ARCH_REGULAR_PACKAGES += libc6-sparc64 libc6-dev-sparc64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-sparc64 libc6-dev-sparc64
 sparc64_add-ons = nptl \$(add-ons)
 sparc64_configure_target=sparc64-linux-gnu
 sparc64_CC = \$(CC) -m64
diff -Nru glibc-2.19/debian/sysdeps/sparc64.mk glibc-2.19/debian/sysdeps/sparc64.mk
--- glibc-2.19/debian/sysdeps/sparc64.mk
+++ glibc-2.19/debian/sysdeps/sparc64.mk
@@ -4,7 +4,7 @@
 
 # build 32-bit (sparc) alternative library
 GLIBC_PASSES += sparc
-DEB_ARCH_REGULAR_PACKAGES += libc6-sparc libc6-dev-sparc
+DEB_ARCH_MULTILIB_PACKAGES += libc6-sparc libc6-dev-sparc
 sparc_add-ons = nptl \$(add-ons)
 sparc_configure_target=sparc-linux-gnu
 sparc_CC = \$(CC) -m32
diff -Nru glibc-2.19/debian/sysdeps/x32.mk glibc-2.19/debian/sysdeps/x32.mk
--- glibc-2.19/debian/sysdeps/x32.mk
+++ glibc-2.19/debian/sysdeps/x32.mk
@@ -1,9 +1,9 @@
 libc_rtlddir = /libx32
 extra_config_options = --enable-multi-arch
 
 # build 64-bit (amd64) alternative library
 GLIBC_PASSES += amd64
-DEB_ARCH_REGULAR_PACKAGES += libc6-amd64 libc6-dev-amd64
+DEB_ARCH_MULTILIB_PACKAGES += libc6-amd64 libc6-dev-amd64
 libc6-amd64_shlib_dep = libc6-amd64 (>= \$(shlib_dep_ver))
 amd64_add-ons = nptl \$(add-ons)
 amd64_configure_target = x86_64-linux-gnu
@@ -34,7 +35,7 @@
 
 # build 32-bit (i386) alternative library
 GLIBC_PASSES += i386
-DEB_ARCH_REGULAR_PACKAGES += libc6-i386 libc6-dev-i386
+DEB_ARCH_MULTILIB_PACKAGES += libc6-i386 libc6-dev-i386
 libc6-i386_shlib_dep = libc6-i386 (>= \$(shlib_dep_ver))
 i386_add-ons = nptl \$(add-ons)
 i386_configure_target = i686-linux-gnu
EOF
}
if test -d "$RESULT/${LIBC_NAME}1"; then
	echo "skipping rebuild of $LIBC_NAME stage1"
	$APT_GET remove libc6-dev-i386
	dpkg -i "$RESULT/${LIBC_NAME}1/"*.deb
else
	$APT_GET install gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase linux-libc-dev:$HOST_ARCH
	cross_build_setup "$LIBC_NAME" "${LIBC_NAME}1"
	dpkg-checkbuilddeps -B -a$HOST_ARCH || : # tell unmet build depends
	DEB_GCC_VERSION=-$GCC_VER DEB_BUILD_PROFILE=bootstrap dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d
	cd ..
	ls -l
	pickup_packages *.changes
	$APT_GET remove libc6-dev-i386
	dpkg -i libc*-dev_*.deb
	test -d "$RESULT" && mkdir "$RESULT/${LIBC_NAME}1"
	test -d "$RESULT" && cp -v libc*-dev_*.deb "$RESULT/${LIBC_NAME}1"
	cd ..
	rm -Rf "${LIBC_NAME}1"
fi
echo "progress-mark:4:$LIBC_NAME stage1 complete"
# binutils looks for libc.so in /usr/<triplet>/lib rather than /usr/lib/<triplet>
mkdir -p /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`
ln -s /usr/lib/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH` /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`/lib

if test -d "$RESULT/gcc2"; then
	echo "skipping rebuild of gcc stage2"
	dpkg -i "$RESULT"/gcc2/*.deb
else
	$APT_GET install debhelper gawk patchutils bison flex python realpath lsb-release quilt libc6-dbg libtool autoconf2.64 zlib1g-dev gperf texinfo locales sharutils procps libantlr-java libffi-dev fastjar libmagic-dev libecj-java zip libasound2-dev libxtst-dev libxt-dev libgtk2.0-dev libart-2.0-dev libcairo2-dev netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen chrpath binutils-multiarch binutils$HOST_ARCH_SUFFIX
	cross_build_setup "gcc-$GCC_VER" gcc2
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_TARGET_ARCH=$HOST_ARCH DEB_STAGE=stage2 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends again after rewriting control
		gcc_cv_libc_provides_ssp=yes DEB_TARGET_ARCH=$HOST_ARCH DEB_STAGE=stage2 dpkg-buildpackage -d -b -uc -us
	else
		DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends again after rewriting control
		gcc_cv_libc_provides_ssp=yes DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage -d -b -uc -us
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
	$APT_GET install debhelper gawk patchutils bison flex python realpath lsb-release quilt libc6-dbg libtool autoconf2.64 zlib1g-dev gperf texinfo locales sharutils procps libantlr-java libffi-dev fastjar libmagic-dev libecj-java zip libasound2-dev libxtst-dev libxt-dev libgtk2.0-dev libart-2.0-dev libcairo2-dev netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen chrpath binutils-multiarch binutils$HOST_ARCH_SUFFIX
	cross_build_setup "gcc-$GCC_VER" gcc3
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes DEB_TARGET_ARCH=$HOST_ARCH dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends again after rewriting control
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes DEB_TARGET_ARCH=$HOST_ARCH dpkg-buildpackage -d -b -uc -us
	else
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends again after rewriting control
		DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=d,go,java,objc,obj-c++" with_deps_on_target_arch_pkgs=yes DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes dpkg-buildpackage -d -b -uc -us
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

cross_build pcre3
echo "progress-mark:8:pcre3 cross build"

$APT_GET remove libc6-i386 # breaks cross builds
builddep_attr() {
	# libtool dependency unsatisfiable
	$APT_GET install dpkg-dev debhelper autoconf automake gettext libtool
}
cross_build attr
echo "progress-mark:9:attr cross build"

builddep_acl() {
	# libtool dependency unsatisfiable
	$APT_GET install dpkg-dev debhelper autotools-dev autoconf automake gettext libtool libattr1-dev:$HOST_ARCH
}
cross_build acl
echo "progress-mark:10:acl cross build"

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
+Build-Depends: debhelper (>= 8.1.3~), binutils (>= 2.18.1~cvs20080103-2) [mips mipsel], gcc-multilib [amd64 i386 kfreebsd-amd64 mips mipsel powerpc ppc64 s390 sparc s390x] <!profile.nobiarch>, dpkg-dev (>= 1.16.1)
 
 Package: zlib1g
 Architecture: any
@@ -65,6 +65,7 @@
 Architecture: sparc s390 i386 powerpc mips mipsel
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: amd64-libs (<< 1.4)
+Build-Profiles: !nobiarch
 Description: compression library - 64 bit runtime
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes a 64 bit version of the
@@ -76,6 +77,7 @@
 Depends: lib64z1 (= \${binary:Version}), zlib1g-dev (= \${binary:Version}), lib64c-dev, \${misc:Depends}
 Replaces: amd64-libs-dev (<< 1.4)
 Provides: lib64z-dev
+Build-Profiles: !nobiarch
 Description: compression library - 64 bit development
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes the development support
@@ -86,6 +88,7 @@
 Conflicts: libc6-i386 (<= 2.9-18)
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: ia32-libs (<< 1.5)
+Build-Profiles: !nobiarch
 Description: compression library - 32 bit runtime
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes a 32 bit version of the
@@ -98,6 +101,7 @@
 Depends: lib32z1 (= \${binary:Version}), zlib1g-dev (= \${binary:Version}), lib32c-dev, \${misc:Depends}
 Provides: lib32z-dev
 Replaces: ia32-libs-dev (<< 1.5)
+Build-Profiles: !nobiarch
 Description: compression library - 32 bit development
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes the development support
@@ -106,6 +110,7 @@
 Package: libn32z1
 Architecture: mips mipsel
 Depends: \${shlibs:Depends}, \${misc:Depends}
+Build-Profiles: !nobiarch
 Description: compression library - n32 runtime
  zlib is a library implementing the deflate compression method found
  in gzip and PKZIP.  This package includes a n32 version of the shared
@@ -116,6 +121,7 @@
 Architecture: mips mipsel
 Depends: libn32z1 (= \${binary:Version}), zlib1g-dev (= \${binary:Version}), libn32c-dev, \${misc:Depends}
 Provides: libn32z-dev
+Build-Profiles: !nobiarch
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
echo "progress-mark:11:zlib cross build"

cross_build hostname
echo "progress-mark:12:hostname cross build"

if test "`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_ARCH_OS`" = "linux"; then
	cross_build libsepol
	echo "progress-mark:13:libsepol cross build"
fi

cross_build gmp
echo "progress-mark:14:gmp cross build"

cross_build mpfr4
echo "progress-mark:15:mpfr4 cross build"

patch_mpclib3() {
	echo "patching mpclib3 to use dh-autoreconf"
	patch -p1 <<EOF
diff -u mpclib3-1.0.1/debian/rules mpclib3-1.0.1/debian/rules
--- mpclib3-1.0.1/debian/rules
+++ mpclib3-1.0.1/debian/rules
@@ -33,8 +33,9 @@
 major=\`ls src/.libs/lib*.so.* | \\
  awk '{if (match(\$\$0,/\.so\.[0-9]+\$\$/)) print substr(\$\$0,RSTART+4)}'\`
 
-config.status: configure
+configure-stamp:
 	dh_testdir
+	dh_autoreconf
 	# Add here commands to configure the package.
 ifneq "\$(wildcard /usr/share/misc/config.sub)" ""
 	cp -f /usr/share/misc/config.sub config.sub
@@ -47,10 +48,11 @@
 		--mandir=\$${prefix}/share/man \\
 		--infodir=\$${prefix}/share/info \\
 		CFLAGS="\$(CFLAGS)" LDFLAGS="-Wl,-z,defs"
+	touch \$@
 
 
 build: build-stamp
-build-stamp:  config.status 
+build-stamp: configure-stamp
 	dh_testdir
 
 	# Add here commands to compile the package.
@@ -64,12 +66,13 @@
 clean: 
 	dh_testdir
 	dh_testroot
-	rm -f build-stamp 
+	rm -f build-stamp configure-stamp
 
 	# Add here commands to clean up after the build process.
 	[ ! -f Makefile ] || \$(MAKE) distclean
 	rm -f config.sub config.guess
 
+	dh_autoreconf_clean
 	dh_clean 
 
 install: build
diff -u mpclib3-1.0.1/debian/control mpclib3-1.0.1/debian/control
--- mpclib3-1.0.1/debian/control
+++ mpclib3-1.0.1/debian/control
@@ -1,7 +1,7 @@
 Source: mpclib3
 Priority: extra
 Maintainer: Laurent Fousse <lfousse@debian.org>
-Build-Depends: debhelper (>= 7), autotools-dev, libmpfr-dev, libgmp-dev
+Build-Depends: debhelper (>= 7), autotools-dev, libmpfr-dev, libgmp-dev, dh-autoreconf
 Standards-Version: 3.8.4
 Section: libs
 Homepage: http://www.multiprecision.org/mpc/
EOF
}
builddep_mpclib3() {
	# patch adds dh-autoreconf dependency
	$APT_GET install debhelper autotools-dev libmpfr-dev:$HOST_ARCH libgmp-dev:$HOST_ARCH dh-autoreconf
}
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
+               g++-multilib [amd64 i386 powerpc ppc64 s390 sparc] <!profile.nobiarch>,
                libgpm-dev [linux-any],
                pkg-config,
 Standards-Version: 3.9.5
@@ -158,6 +158,7 @@
 Depends: lib64tinfo5 (= \${binary:Version}),
          \${shlibs:Depends}, \${misc:Depends}
 Replaces: amd64-libs (<= 1.2)
+Build-Profiles: !nobiarch
 Description: shared libraries for terminal handling (64-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -177,6 +178,7 @@
          libncurses5-dev (= \${binary:Version}), lib64c-dev, \${misc:Depends}
 Suggests: ncurses-doc
 Replaces: amd64-libs-dev (<= 1.2), lib64tinfo5-dev
+Build-Profiles: !nobiarch
 Description: developer's libraries for ncurses (64-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -193,6 +195,7 @@
 Depends: lib32tinfo5 (= \${binary:Version}),
          \${shlibs:Depends}, \${misc:Depends}
 Replaces: ia32-libs (<< 1.10)
+Build-Profiles: !nobiarch
 Description: shared libraries for terminal handling (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -211,6 +214,7 @@
          lib32tinfo-dev (= \${binary:Version}),
          libncurses5-dev (= \${binary:Version}), lib32c-dev, \${misc:Depends}
 Suggests: ncurses-doc
+Build-Profiles: !nobiarch
 Description: developer's libraries for ncurses (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -226,6 +230,7 @@
 Priority: optional
 Depends: lib32tinfo5 (= \${binary:Version}),
          \${shlibs:Depends}, \${misc:Depends}
+Build-Profiles: !nobiarch
 Description: shared libraries for terminal handling (wide character support) (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -244,6 +249,7 @@
          lib32tinfo-dev (= \${binary:Version}),
          libncursesw5-dev (= \${binary:Version}), lib32c-dev, \${misc:Depends}
 Suggests: ncurses-doc
+Build-Profiles: !nobiarch
 Description: developer's libraries for ncursesw (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -261,6 +267,7 @@
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: lib64ncurses5 (<< 5.9-3)
 Breaks: lib64ncurses5 (<< 5.9-3)
+Build-Profiles: !nobiarch
 Description: shared low-level terminfo library for terminal handling (64-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -275,6 +282,7 @@
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: lib32ncurses5 (<< 5.9-3)
 Breaks: lib32ncurses5 (<< 5.9-3)
+Build-Profiles: !nobiarch
 Description: shared low-level terminfo library for terminal handling (32-bit)
  The ncurses library routines are a terminal-independent method of
  updating character screens with reasonable optimization.
@@ -291,6 +299,7 @@
          lib32c-dev, \${misc:Depends}
 Replaces: lib32ncurses5-dev (<< 5.9-3), lib32tinfo5-dev
 Breaks: lib32ncurses5-dev (<< 5.9-3)
+Build-Profiles: !nobiarch
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
 ifneq (\$(findstring linux,\$(DEB_HOST_GNU_SYSTEM)),)
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
diff -Nru readline6-6.3/debian/changelog readline6-6.3/debian/changelog
--- readline6-6.3/debian/changelog
+++ readline6-6.3/debian/changelog
@@ -1,3 +1,10 @@
+readline6 (6.3-6.1) UNRELEASED; urgency=low
+
+  * Non-maintainer upload.
+  * Support nobiarch build profile. (Closes: #737955)
+
+ -- Helmut Grohne <helmut@dedup1.subdivi.de>  Sun, 04 May 2014 14:47:47 +0200
+
 readline6 (6.3-6) unstable; urgency=medium
 
   * Really apply the patch to fix the display issue when a multiline
diff -Nru readline6-6.3/debian/control readline6-6.3/debian/control
--- readline6-6.3/debian/control
+++ readline6-6.3/debian/control
@@ -4,11 +4,11 @@
 Maintainer: Matthias Klose <doko@debian.org>
 Standards-Version: 3.9.5
 Build-Depends: debhelper (>= 8.1.3),
-  libtinfo-dev, lib32tinfo-dev [amd64 ppc64],
+  libtinfo-dev, lib32tinfo-dev [amd64 ppc64] <!profile.nobiarch>,
   libncursesw5-dev (>= 5.6),
-  lib32ncursesw5-dev [amd64 ppc64], lib64ncurses5-dev [i386 powerpc sparc s390],
+  lib32ncursesw5-dev [amd64 ppc64] <!profile.nobiarch>, lib64ncurses5-dev [i386 powerpc sparc s390] <!profile.nobiarch>,
   mawk | awk, texinfo, autotools-dev,
-  gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc]
+  gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc] <!profile.nobiarch>
 
 Package: libreadline6
 Architecture: any
@@ -30,6 +30,7 @@
 Depends: readline-common, \${shlibs:Depends}, \${misc:Depends}
 Section: libs
 Priority: optional
+Build-Profiles: !nobiarch
 Description: GNU readline and history libraries, run-time libraries (64-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
@@ -96,6 +97,7 @@
 Conflicts: lib64readline-dev, lib64readline-gplv2-dev
 Section: libdevel
 Priority: optional
+Build-Profiles: !nobiarch
 Description: GNU readline and history libraries, development files (64-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
@@ -139,6 +141,7 @@
 Depends: readline-common, \${shlibs:Depends}, \${misc:Depends}
 Section: libs
 Priority: optional
+Build-Profiles: !nobiarch
 Description: GNU readline and history libraries, run-time libraries (32-bit)
  The GNU readline library aids in the consistency of user interface
  across discrete programs that need to provide a command line
@@ -154,6 +157,7 @@
 Conflicts: lib32readline-dev, lib32readline-gplv2-dev
 Section: libdevel
 Priority: optional
+Build-Profiles: !nobiarch
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

patch_bzip2() {
	echo "patching bzip2 to support nobiarch build profile #737954"
	patch -p1 <<EOF
diff -Nru bzip2-1.0.6/debian/changelog bzip2-1.0.6/debian/changelog
--- bzip2-1.0.6/debian/changelog
+++ bzip2-1.0.6/debian/changelog
@@ -1,3 +1,10 @@
+bzip2 (1.0.6-5.1) UNRELEASED; urgency=low
+
+  * Non-maintainer upload.
+  * Support nobiarch build profile. (Closes: #737954)
+
+ -- Helmut Grohne <helmut@subdivi.de>  Sat, 10 May 2014 11:01:05 +0200
+
 bzip2 (1.0.6-5) unstable; urgency=low
 
   * Adding watch file
diff -Nru bzip2-1.0.6/debian/control bzip2-1.0.6/debian/control
--- bzip2-1.0.6/debian/control
+++ bzip2-1.0.6/debian/control
@@ -4,7 +4,7 @@
 Maintainer: Anibal Monsalve Salazar <anibal@debian.org>
 Uploaders: Santiago Ruano Rincón <santiago@debian.org>, Jorge Ernesto Guevara Cuenca <jguevara@debiancolombia.org>
 Standards-Version: 3.9.4
-Build-depends: texinfo, gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc] | gcc-4.1 (<< 4.1.2) [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc], dpkg-dev (>= 1.16.0)
+Build-depends: texinfo, gcc-multilib [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc] <!profile.nobiarch> | gcc-4.1 (<< 4.1.2) [amd64 i386 kfreebsd-amd64 powerpc ppc64 s390 sparc], dpkg-dev (>= 1.16.0)
 Homepage: http://www.bzip.org/
 Vcs-Git: git://git.debian.org/collab-maint/bzip2.git
 Vcs-Browser: http://git.debian.org/?p=collab-maint/bzip2.git
@@ -86,6 +86,7 @@
 Architecture: i386 powerpc sparc s390
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: amd64-libs (<< 1.5)
+Build-Profiles: !nobiarch
 Description: high-quality block-sorting file compressor library - 64bit runtime
  This package contains the libbzip2 64bit runtime library.
 
@@ -95,6 +96,7 @@
 Replaces: amd64-libs-dev (<< 1.5)
 Architecture: i386 powerpc sparc s390
 Depends: lib64bz2-1.0 (=\${binary:Version}), libbz2-dev (=\${binary:Version}), \${dev:Depends}
+Build-Profiles: !nobiarch
 Description: high-quality block-sorting file compressor library - 64bit development
  Static libraries and include files for the bzip2 compressor library (64bit).
 
@@ -105,6 +107,7 @@
 Pre-Depends: libc6-i386 (>= 2.9-18) [amd64]
 Depends: \${shlibs:Depends}, \${misc:Depends}
 Replaces: ia32-libs
+Build-Profiles: !nobiarch
 Description: high-quality block-sorting file compressor library - 32bit runtime
  This package contains the libbzip2 32bit runtime library.
 
@@ -114,6 +117,7 @@
 Architecture: amd64 ppc64
 Depends: lib32bz2-1.0 (=\${binary:Version}), libbz2-dev (=\${binary:Version}), \${dev:Depends}
 Replaces: ia32-libs-dev
+Build-Profiles: !nobiarch
 Description: high-quality block-sorting file compressor library - 32bit development
  Static libraries and include files for the bzip2 compressor library (32bit).
 
diff -Nru bzip2-1.0.6/debian/rules bzip2-1.0.6/debian/rules
--- bzip2-1.0.6/debian/rules
+++ bzip2-1.0.6/debian/rules
@@ -52,6 +52,11 @@
 	lib32 := usr/lib32
 endif
 
+ifneq (\$(filter nobiarch,\$(DEB_BUILD_PROFILES)),)
+build64-stamp :=
+build32-stamp :=
+endif
+
 build-arch: build
 build-indep: build
 build: build-stamp \$(build32-stamp) \$(build64-stamp)
EOF
}
builddep_bzip2() {
	# gcc-multilib dependency unsatisfiable
	$APT_GET install texinfo dpkg-dev
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
