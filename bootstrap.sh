#!/bin/sh

set -v
set -e

export DEB_BUILD_OPTIONS="nocheck parallel=1"
export DH_VERBOSE=1
RESULT="/tmp/result"
HOST_ARCH=undefined
GCC_VER=4.8
MIRROR="http://ftp.stw-bonn.de/debian"

# evaluate command line parameters of the form KEY=VALUE
for param in "$*"; do
	eval $param
done

if test -z "$HOST_ARCH" || ! dpkg-architecture -a$HOST_ARCH; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
fi
mkdir -p "$RESULT"

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
		*", Motorola 68020, version "*)
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
		*", SPARC version "*)
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

grep -q '^deb-src ' /etc/apt/sources.list || echo "deb-src $MIRROR sid main" >> /etc/apt/sources.list

apt-get update
dpkg --add-architecture $HOST_ARCH

# binutils
PKG=`echo $RESULT/binutils-*.deb`
if test -f "$PKG"; then
	echo "skipping rebuild of binutils-target"
	dpkg -i "$PKG"
else
	apt-get install -y autoconf bison flex gettext texinfo dejagnu quilt python3 file lsb-release zlib1g-dev
	cd /tmp/buildd
	mkdir binutils
	cd binutils
	obtain_source_package binutils
	cd binutils-*
	TARGET=$HOST_ARCH dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
	dpkg -i binutils-*.deb
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
PKG=`echo $RESULT/linux-libc-dev_*.deb`
if test -f "$PKG"; then
	echo "skipping rebuild of linux-libc-dev"
	dpkg -i "$PKG"
else
	apt-get install -y bc cpio debhelper kernel-wedge patchutils python quilt python-six
	cd /tmp/buildd
	mkdir linux
	cd linux
	obtain_source_package linux
	cd linux-*
	dpkg-checkbuilddeps -B -a$HOST_ARCH || : # tell unmet build depends
	KBUILD_VERBOSE=1 make -f debian/rules.gen binary-libc-dev_$HOST_ARCH
	cd ..
	ls -l
	dpkg -i linux-libc-dev_*.deb
	test -d "$RESULT" && cp -v linux-libc-dev_*.deb "$RESULT"
	cd ..
	rm -Rf linux
fi
echo "progress-mark:2:linux-libc-dev complete"

# gcc
patch_gcc() {
	if test "$GCC_VER" = "4.8"; then
		echo "patching gcc-4.8: failure to include headers in stage1"
		patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/rules.d/binary-gcc.mk gcc-4.8-4.8.2/debian/rules.d/binary-gcc.mk
--- gcc-4.8-4.8.2/debian/rules.d/binary-gcc.mk
+++ gcc-4.8-4.8.2/debian/rules.d/binary-gcc.mk
@@ -36,6 +36,10 @@
 	\$(shell test -e \$(d)/\$(gcc_lib_dir)/SYSCALLS.c.X \\
 		&& echo \$(gcc_lib_dir)/SYSCALLS.c.X)
 
+ifeq (\$(DEB_STAGE),stage1)
+    files_gcc += \$(gcc_lib_dir)/include \$(gcc_lib_dir)/include-fixed
+endif
+
 ifneq (\$(GFDL_INVARIANT_FREE),yes)
     files_gcc += \\
 	\$(PF)/share/man/man1/\$(cmd_prefix){gcc,gcov}\$(pkg_ver).1
EOF
	fi
	if test "$GCC_VER" = "4.8" -a "$HOST_ARCH" = "sparc64"; then
		echo "patching gcc-4.8 for sparc64: honor DEB_CROSS_NO_BIARCH #743342"
		patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/rules2 gcc-4.8-4.8.2/debian/rules2
--- gcc-4.8-4.8.2/debian/rules2
+++ gcc-4.8-4.8.2/debian/rules2
@@ -334,7 +334,7 @@
     endif
 endif
 
-ifneq (,\$(filter \$(DEB_TARGET_GNU_TYPE), x86_64-linux-gnu x86_64-linux-gnux32 x86_64-kfreebsd-gnu s390x-linux-gnu))
+ifneq (,\$(filter \$(DEB_TARGET_GNU_TYPE), x86_64-linux-gnu x86_64-linux-gnux32 x86_64-kfreebsd-gnu s390x-linux-gnu sparc64-linux-gnu))
     ifneq (\$(biarch32),yes)
       CONFARGS += --disable-multilib
     endif
EOF
	fi
}

if test -d "$RESULT/gcc1"; then
	echo "skipping rebuild of gcc stage1"
	apt-get remove -y gcc-multilib
	dpkg -i $RESULT/gcc1/*.deb
else
	apt-get install -y debhelper gawk patchutils bison flex python realpath lsb-release quilt g++-multilib libc6-dev-i386 lib32gcc1 libc6-dev-x32 libx32gcc1 libc6-dbg libtool autoconf2.64 zlib1g-dev gperf texinfo locales sharutils procps libantlr-java libffi-dev fastjar libmagic-dev libecj-java zip libasound2-dev libxtst-dev libxt-dev libgtk2.0-dev libart-2.0-dev libcairo2-dev netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen chrpath binutils-multiarch
	cd /tmp/buildd
	mkdir gcc1
	cd gcc1
	obtain_source_package gcc-$GCC_VER
	cd gcc-$GCC_VER-*
	patch_gcc
	dpkg-checkbuilddeps -B -a$HOST_ARCH || : # tell unmet build depends
	DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -T control
	DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us
	cd ..
	ls -l
	apt-get remove -y gcc-multilib
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

# eglibc looks for linux headers in /usr/<triplet>/include/linux rather than /usr/include/linux
# later gcc looks for pthread.h and stuff in /usr/<triplet>/include rather than /usr/include
mkdir -p /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`
ln -s ../include /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`/include

# eglibc
patch_eglibc() {
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
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@.*,%%g' < \$@T > debian/control
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
	echo "patching eglibc to build without selinux in stage2 #742640"
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
+Depends: @nobootstrap@, libgcc1 [!hppa !m68k], @nobootstrap@ libgcc2 [m68k], @nobootstrap@ libgcc4 [hppa], \${shlibs:Depends}
 Recommends: libc6-i686 [i386], libc0.1-i686 [kfreebsd-i386], libc0.3-i686 [hurd-i386] 
 Suggests: glibc-doc, debconf | debconf-2.0, locales [!hurd-i386]
 Provides: \${locale-compat:Depends}, libc6-sparcv9b [sparc sparc64]
diff -Nru eglibc-2.18/debian/rules.d/control.mk eglibc-2.18/debian/rules.d/control.mk
--- eglibc-2.18/debian/rules.d/control.mk
+++ eglibc-2.18/debian/rules.d/control.mk
@@ -45,7 +45,11 @@
 ifeq (\$(DEB_BUILD_PROFILE),bootstrap)
 	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@.*,%%g' < \$@T > debian/control
 else
+ifneq (\$(filter stage2,\$(DEB_BUILD_PROFILES)),)
+	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@.*,%%g' < \$@T > debian/control
+else
 	sed -e 's%@libc@%\$(libc)%g;s%@nobootstrap@%%g' < \$@T > debian/control
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
}
PKG=`echo $RESULT/libc*-dev_*.deb`
if test -f "$PKG"; then
	echo "skipping rebuild of eglibc stage1"
	apt-get -y remove libc6-dev-i386
	dpkg -i "$PKG"
else
	apt-get install -y gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase
	cd /tmp/buildd
	mkdir eglibc
	cd eglibc
	obtain_source_package eglibc
	cd eglibc-*
	patch_eglibc
	dpkg-checkbuilddeps -B -a$HOST_ARCH || : # tell unmet build depends
	DEB_GCC_VERSION=-$GCC_VER DEB_BUILD_PROFILE=bootstrap dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d
	cd ..
	ls -l
	apt-get -y remove libc6-dev-i386
	dpkg -i libc*-dev_*.deb
	test -d "$RESULT" && cp -v libc*-dev_*.deb "$RESULT/"
	cd ..
	rm -Rf eglibc
fi
echo "progress-mark:4:eglibc stage1 complete"
# binutils looks for libc.so in /usr/<triplet>/lib rather than /usr/lib/<triplet>
mkdir -p /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`
ln -s /usr/lib/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH` /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`/lib

if test -d "$RESULT/gcc2"; then
	echo "skipping rebuild of gcc stage2"
	dpkg -i "$RESULT"/gcc2/*.deb
else
	apt-get install -y debhelper gawk patchutils bison flex python realpath lsb-release quilt lib32gcc1 libx32gcc1 libc6-dbg libtool autoconf2.64 zlib1g-dev gperf texinfo locales sharutils procps libantlr-java libffi-dev fastjar libmagic-dev libecj-java zip libasound2-dev libxtst-dev libxt-dev libgtk2.0-dev libart-2.0-dev libcairo2-dev netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen chrpath binutils-multiarch
	cd /tmp/buildd
	mkdir gcc2
	cd gcc2
	obtain_source_package gcc-$GCC_VER
	cd gcc-$GCC_VER-*
	patch_gcc
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage -d -T control
	gcc_cv_libc_provides_ssp=yes DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage2 dpkg-buildpackage -d -b -uc -us
	cd ..
	ls -l
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

if test -d "$RESULT/eglibc2"; then
	echo "skipping rebuild of eglibc stage2"
	dpkg -i "$RESULT"/eglibc2/*.deb
else
	apt-get install -y gettext file quilt autoconf gawk debhelper rdfind symlinks libaudit-dev libcap-dev libselinux-dev binutils bison netbase
	cd /tmp/buildd
	mkdir eglibc2
	cd eglibc2
	obtain_source_package eglibc
	cd eglibc-*
	patch_eglibc
	dpkg-checkbuilddeps -B -a$HOST_ARCH || : # tell unmet build depends
	DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d -Pstage2
	cd ..
	ls -l
	dpkg -i libc*-dev_*.deb libc*[0-9]_*_*.deb
	test -d "$RESULT" && mkdir "$RESULT/eglibc2"
	test -d "$RESULT" && cp libc*-dev_*.deb libc*[0-9]_*_*.deb "$RESULT/eglibc2"
	cd ..
	rm -Rf eglibc2
fi
echo "progress-mark:6:eglibc stage2 complete"

if test -d "$RESULT/gcc3"; then
	echo "skipping rebuild of gcc stage3"
	dpkg -i "$RESULT"/gcc3/*.deb
else
	apt-get install -y debhelper gawk patchutils bison flex python realpath lsb-release quilt lib32gcc1 libx32gcc1 libc6-dbg libtool autoconf2.64 zlib1g-dev gperf texinfo locales sharutils procps libantlr-java libffi-dev fastjar libmagic-dev libecj-java zip libasound2-dev libxtst-dev libxt-dev libgtk2.0-dev libart-2.0-dev libcairo2-dev netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev dejagnu autogen chrpath binutils-multiarch
	cd /tmp/buildd
	mkdir gcc3
	cd gcc3
	obtain_source_package gcc-$GCC_VER
	cd gcc-$GCC_VER-*
	patch_gcc
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	DEB_TARGET_ARCH=$HOST_ARCH dpkg-buildpackage -d -T control
	DEB_TARGET_ARCH=$HOST_ARCH dpkg-buildpackage -d -b -uc -us
	cd ..
	ls -l
	dpkg -i *.deb
	compiler="`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`-gcc-$GCC_VER"
	if ! which "$compiler"; then echo "$compiler missing in stage3 gcc package"; exit 1; fi
	if ! $compiler -x c -c /dev/null -o test.o; then echo "stage3 gcc fails to execute"; exit 1; fi
	if ! test -f test.o; then echo "stage3 gcc fails to create binaries"; exit 1; fi
	check_arch test.o "$HOST_ARCH"
	test -d "$RESULT" && mkdir "$RESULT/gcc3"
	test -d "$RESULT" && cp *.deb "$RESULT/gcc3"
	cd ..
	rm -Rf gcc3
fi
echo "progress-mark:7:gcc stage3 complete"
