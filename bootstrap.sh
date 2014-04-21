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
apt-get -y install build-essential
dpkg --add-architecture $HOST_ARCH

if test -z "$GCC_VER"; then
	GCC_VER=`apt-cache depends gcc | sed 's/^ *Depends: gcc-\([0-9.]*\)$/\1/;t;d'`
fi

if test -z "$HOST_ARCH" || ! dpkg-architecture -a$HOST_ARCH; then
	echo "architecture $HOST_ARCH unknown to dpkg"
	exit 1
fi
mkdir -p /tmp/buildd
mkdir -p "$RESULT"

# choosing libatomic1 arbitrarily here, cause it never bumped soname
BUILD_GCC_MULTIARCH_VER=`apt-cache show --no-all-versions libatomic1 | sed 's/^Source: gcc-\([0-9.]*\)$/\1/;t;d'`
if test "$GCC_VER" != "$BUILD_GCC_MULTIARCH_VER"; then
	echo "host gcc version ($GCC_VER) and build gcc version ($BUILD_GCC_MULTIARCH_VER) mismatch. need different build gcc"
if test -d "$RESULT/gcc0"; then
	echo "skipping rebuild of build gcc"
	dpkg -i $RESULT/gcc0/*.deb
else
	apt-get build-dep --arch-only -y gcc-$GCC_VER
	cd /tmp/buildd
	mkdir gcc0
	cd gcc0
	obtain_source_package gcc-$GCC_VER
	cd gcc-*
	DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS nolang=biarch,d,go,java,objc,obj-c++" dpkg-buildpackage -B -uc -us
	cd ..
	ls -l
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
	dpkg -i "$PKG"
else
	apt-get install -y autoconf bison flex gettext texinfo dejagnu quilt python3 file lsb-release zlib1g-dev
	cd /tmp/buildd
	mkdir binutils
	cd binutils
	obtain_source_package binutils
	cd binutils-*
	WITH_SYSROOT=/ TARGET=$HOST_ARCH dpkg-buildpackage -B -uc -us
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
if test "`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_ARCH_OS`" = "linux"; then
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
fi

# gcc
patch_gcc() {
	if test "$GCC_VER" = "4.8" -a "$HOST_ARCH" = "sparc64"; then
		echo "fixing broken sparc64 patch #743342"
		sed -i 's/sparc64-linux-gnuA/sparc64-linux-gnu/' debian/rules2
	fi
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
	if test "$GCC_VER" = "4.8"; then
		echo "fixing application of gcc-linaro.diff #743764"
		patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/patches/gcc-linaro.diff gcc-4.8-4.8.2/debian/patches/gcc-linaro.diff
--- gcc-4.8-4.8.2/debian/patches/gcc-linaro.diff
+++ gcc-4.8-4.8.2/debian/patches/gcc-linaro.diff
@@ -17144,67 +17144,6 @@
      insn="nop"
      ;;
    ia64 | s390)
---- a/src/gcc/function.c
-+++ b/src/gcc/function.c
-@@ -5509,22 +5509,45 @@
- 	 except for any part that overlaps SRC (next loop).  */
-       bb_uses = &DF_LR_BB_INFO (bb)->use;
-       bb_defs = &DF_LR_BB_INFO (bb)->def;
--      for (i = dregno; i < end_dregno; i++)
-+      if (df_live)
- 	{
--	  if (REGNO_REG_SET_P (bb_uses, i) || REGNO_REG_SET_P (bb_defs, i))
--	    next_block = NULL;
--	  CLEAR_REGNO_REG_SET (live_out, i);
--	  CLEAR_REGNO_REG_SET (live_in, i);
-+	  for (i = dregno; i < end_dregno; i++)
-+	    {
-+	      if (REGNO_REG_SET_P (bb_uses, i) || REGNO_REG_SET_P (bb_defs, i)
-+		  || REGNO_REG_SET_P (&DF_LIVE_BB_INFO (bb)->gen, i))
-+		next_block = NULL;
-+	      CLEAR_REGNO_REG_SET (live_out, i);
-+	      CLEAR_REGNO_REG_SET (live_in, i);
-+	    }
-+
-+	  /* Check whether BB clobbers SRC.  We need to add INSN to BB if so.
-+	     Either way, SRC is now live on entry.  */
-+	  for (i = sregno; i < end_sregno; i++)
-+	    {
-+	      if (REGNO_REG_SET_P (bb_defs, i)
-+		  || REGNO_REG_SET_P (&DF_LIVE_BB_INFO (bb)->gen, i))
-+		next_block = NULL;
-+	      SET_REGNO_REG_SET (live_out, i);
-+	      SET_REGNO_REG_SET (live_in, i);
-+	    }
- 	}
-+      else
-+	{
-+	  /* DF_LR_BB_INFO (bb)->def does not comprise the DF_REF_PARTIAL and
-+	     DF_REF_CONDITIONAL defs.  So if DF_LIVE doesn't exist, i.e.
-+	     at -O1, just give up searching NEXT_BLOCK.  */
-+	  next_block = NULL;
-+	  for (i = dregno; i < end_dregno; i++)
-+	    {
-+	      CLEAR_REGNO_REG_SET (live_out, i);
-+	      CLEAR_REGNO_REG_SET (live_in, i);
-+	    }
- 
--      /* Check whether BB clobbers SRC.  We need to add INSN to BB if so.
--	 Either way, SRC is now live on entry.  */
--      for (i = sregno; i < end_sregno; i++)
--	{
--	  if (REGNO_REG_SET_P (bb_defs, i))
--	    next_block = NULL;
--	  SET_REGNO_REG_SET (live_out, i);
--	  SET_REGNO_REG_SET (live_in, i);
-+	  for (i = sregno; i < end_sregno; i++)
-+	    {
-+	      SET_REGNO_REG_SET (live_out, i);
-+	      SET_REGNO_REG_SET (live_in, i);
-+	    }
- 	}
- 
-       /* If we don't need to add the move to BB, look for a single
 --- a/src/gcc/tree-vectorizer.h
 +++ b/src/gcc/tree-vectorizer.h
 @@ -838,6 +838,14 @@
EOF
	fi
	if test "$GCC_VER" = "4.8"; then
		echo "fixing patch application for powerpc* #743718"
		patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/patches/powerpc_remove_many.diff gcc-4.8-4.8.2/debian/patches/powerpc_remove_many.diff
--- gcc-4.8-4.8.2/debian/patches/powerpc_remove_many.diff
+++ gcc-4.8-4.8.2/debian/patches/powerpc_remove_many.diff
@@ -20,9 +20,9 @@
     handling -mcpu=xxx switches.  There is a parallel list in driver-rs6000.c to
     provide the default assembler options if the user uses -mcpu=native, so if
 @@ -170,7 +176,8 @@
- %{mcpu=e500mc64: -me500mc64} \\
  %{maltivec: -maltivec} \\
  %{mvsx: -mvsx %{!maltivec: -maltivec} %{!mcpu*: %(asm_cpu_power7)}} \\
+ %{mpower8-vector|mcrypto|mdirect-move|mhtm: %{!mcpu*: %(asm_cpu_power8)}} \\
 --many"
 +" \\
 +ASM_CPU_SPU_MANY_NOT_SPE
EOF
	fi
	if test "$GCC_VER" = "4.8" -o "$GCC_VER" = "4.9"; then
		echo "build gcc-X.Y-base when with_deps_on_target_arch_pkgs #744782"
		patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/control.m4 gcc-4.8-4.8.2/debian/control.m4
--- gcc-4.8-4.8.2/debian/control.m4
+++ gcc-4.8-4.8.2/debian/control.m4
@@ -125,11 +125,10 @@
 define(\`SOFTBASEDEP', \`gnat\`'PV-base (>= \${gnat:SoftVersion})')
 ')
 
-ifdef(\`TARGET', \`', \`
 ifenabled(\`gccbase',\`
 
 Package: gcc\`'PV-base
-Architecture: any
+Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
 ifdef(\`MULTIARCH', \`Multi-Arch: same
 ')\`'dnl
 Section: libs
@@ -146,8 +145,7 @@
  This version of GCC is not yet available for this architecture.
  Please use the compilers from the gcc-snapshot package for testing.
 ')\`'dnl
-')\`'dnl
-')\`'dnl native
+')\`'dnl gccbase
 
 ifenabled(\`gccxbase',\`
 dnl override default base package dependencies to cross version
diff -u gcc-4.8-4.8.2/debian/rules.d/binary-base.mk gcc-4.8-4.8.2/debian/rules.d/binary-base.mk
--- gcc-4.8-4.8.2/debian/rules.d/binary-base.mk
+++ gcc-4.8-4.8.2/debian/rules.d/binary-base.mk
@@ -38,7 +38,11 @@
 	dh_installchangelogs -p\$(p_base)
 	dh_compress -p\$(p_base)
 	dh_fixperms -p\$(p_base)
+ifeq (\$(with_deps_on_target_arch_pkgs),yes)
+	\$(cross_gencontrol) dh_gencontrol -p\$(p_base) -- -v\$(DEB_VERSION) \$(common_substvars)
+else
 	dh_gencontrol -p\$(p_base) -- -v\$(DEB_VERSION) \$(common_substvars)
+endif
 	dh_installdeb -p\$(p_base)
 	dh_md5sums -p\$(p_base)
 	dh_builddeb -p\$(p_base)
diff -u gcc-4.8-4.8.2/debian/rules.defs gcc-4.8-4.8.2/debian/rules.defs
--- gcc-4.8-4.8.2/debian/rules.defs
+++ gcc-4.8-4.8.2/debian/rules.defs
@@ -427,6 +427,8 @@
   else
     ifneq (\$(with_deps_on_target_arch_pkgs),yes)
       with_gccxbase := yes
+    else
+      with_gccbase := yes
     endif
   endif
 endif
EOF
	fi
	if test "$GCC_VER" = "4.9"; then
		echo "patching gcc to cover libvtv and libcilkrts in cross-ma-install-location.diff"
		patch -p1 <<EOF
diff -u gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff
--- gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff
+++ gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff
@@ -346,0 +347,40 @@
+--- a/src/libvtv/configure.ac
++++ b/src/libvtv/configure.ac
+@@ -72,15 +72,8 @@
+     toolexeclibdir='\$(toolexecdir)/\$(gcc_version)\$(MULTISUBDIR)'
+     ;;
+   no)
+-    if test -n "\$with_cross_host" &&
+-       test x"\$with_cross_host" != x"no"; then
+-      # Install a library built with a cross compiler in tooldir, not libdir.
+-      toolexecdir='\$(exec_prefix)/\$(target_alias)'
+-      toolexeclibdir='\$(toolexecdir)/lib'
+-    else
+-      toolexecdir='\$(libdir)/gcc-lib/\$(target_alias)'
+-      toolexeclibdir='\$(libdir)'
+-    fi
++    toolexecdir='\$(libdir)/gcc-lib/\$(target_alias)'
++    toolexeclibdir='\$(libdir)'
+     multi_os_directory=\`\$CC -print-multi-os-directory\`
+     case \$multi_os_directory in
+       .) ;; # Avoid trailing /.
+--- a/src/libcilkrts/configure.ac
++++ b/src/libcilkrts/configure.ac
+@@ -103,15 +103,8 @@
+     toolexeclibdir='\$(toolexecdir)/\$(gcc_version)\$(MULTISUBDIR)'
+     ;;
+   no)
+-    if test -n "\$with_cross_host" &&
+-       test x"\$with_cross_host" != x"no"; then
+-      # Install a library built with a cross compiler in tooldir, not libdir.
+-      toolexecdir='\$(exec_prefix)/\$(target_alias)'
+-      toolexeclibdir='\$(toolexecdir)/lib'
+-    else
+-      toolexecdir='\$(libdir)/gcc-lib/\$(target_alias)'
+-      toolexeclibdir='\$(libdir)'
+-    fi
++    toolexecdir='\$(libdir)/gcc-lib/\$(target_alias)'
++    toolexeclibdir='\$(libdir)'
+     multi_os_directory=\`\$CC -print-multi-os-directory\`
+     case \$multi_os_directory in
+       .) ;; # Avoid trailing /.
EOF
	fi
	if test "$GCC_VER" = "4.9"; then
		echo "patching gcc to apply cross-ma-install-location.diff again #744265"
		patch -p1 <<EOF
diff -u gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff
--- gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff
+++ gcc-4.9-4.9-20140411/debian/patches/cross-ma-install-location.diff
@@ -185,26 +185,6 @@
      multi_os_directory=\`\$CC -print-multi-os-directory\`
      case \$multi_os_directory in
        .) toolexeclibdir=\$toolexecmainlibdir ;; # Avoid trailing /.
---- a/src/libmudflap/configure.ac
-+++ b/src/libmudflap/configure.ac
-@@ -157,15 +157,8 @@
-     toolexeclibdir='\$(toolexecdir)/\$(gcc_version)\$(MULTISUBDIR)'
-     ;;
-   no)
--    if test -n "\$with_cross_host" &&
--       test x"\$with_cross_host" != x"no"; then
--      # Install a library built with a cross compiler in tooldir, not libdir.
--      toolexecdir='\$(exec_prefix)/\$(target_alias)'
--      toolexeclibdir='\$(toolexecdir)/lib'
--    else
--      toolexecdir='\$(libdir)/gcc-lib/\$(target_alias)'
--      toolexeclibdir='\$(libdir)'
--    fi
-+    toolexecdir='\$(libdir)/gcc-lib/\$(target_alias)'
-+    toolexeclibdir='\$(libdir)'
-     multi_os_directory=\`\$CC -print-multi-os-directory\`
-     case \$multi_os_directory in
-       .) ;; # Avoid trailing /.
 --- a/src/libobjc/configure.ac
 +++ b/src/libobjc/configure.ac
 @@ -109,15 +109,8 @@
EOF
	fi
	if test "$GCC_VER" = "4.8"; then
		echo "patching gcc to support multiarch crossbuilds #716795"
		patch -p1 <<EOF
diff -u gcc-4.8-4.8.2/debian/control.m4 gcc-4.8-4.8.2/debian/control.m4
--- gcc-4.8-4.8.2/debian/control.m4
+++ gcc-4.8-4.8.2/debian/control.m4
@@ -21,6 +21,7 @@
 define(\`depifenabled', \`ifelse(index(enabled_languages, \`\$1'), -1, \`', \`\$2')')
 define(\`ifenabled', \`ifelse(index(enabled_languages, \`\$1'), -1, \`dnl', \`\$2')')
 
+ifdef(\`TARGET',\`ifdef(\`CROSS_ARCH',\`',\`undefine(\`MULTIARCH')')')
 define(\`CROSS_ARCH', ifdef(\`CROSS_ARCH', CROSS_ARCH, \`all'))
 define(\`libdep', \`lib\$2\$1\`'LS\`'AQ (ifelse(\`\$3',\`',\`>=',\`\$3') ifelse(\`\$4',\`',\`\${gcc:Version}',\`\$4'))')
 define(\`libdevdep', \`lib\$2\$1\`'LS\`'AQ (ifelse(\`\$3',\`',\`=',\`\$3') ifelse(\`\$4',\`',\`\${gcc:Version}',\`\$4'))')
@@ -224,11 +225,11 @@
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Priority: ifdef(\`TARGET',\`extra',required)
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`Provides: libgcc1-TARGET-dcv1',
+ifdef(\`TARGET',\`Provides: libgcc1-TARGET-dcv1',\`Provides: libgcc1-armel [armel], libgcc1-armhf [armhf]')
 ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libgcc1-armel [armel], libgcc1-armhf [armhf]')
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Shared version of the support library, a library of internal subroutines
@@ -245,11 +246,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gcc1,,=,\${gcc:EpochVersion}), \${misc:Depends}
-ifdef(\`TARGET',\`',\`dnl
+ifdef(\`TARGET',\`',\`Provides: libgcc1-dbg-armel [armel], libgcc1-dbg-armhf [armhf]
+')\`'dnl
 ifdef(\`MULTIARCH',\`Multi-Arch: same
-')dnl
-Provides: libgcc1-dbg-armel [armel], libgcc1-dbg-armhf [armhf]
-')dnl
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library (debug symbols)\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Debug symbols for the GCC support library.
@@ -265,10 +265,11 @@
 Priority: ifdef(\`TARGET',\`extra',required)
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 ifdef(\`TARGET',\`Provides: libgcc2-TARGET-dcv1
-',ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-'))\`'dnl
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Shared version of the support library, a library of internal subroutines
@@ -285,8 +286,8 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gcc2,,=,\${gcc:Version}), \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library (debug symbols)\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Debug symbols for the GCC support library.
@@ -304,8 +305,8 @@
 Priority: optional
 Recommends: \${dep:libcdev}
 Depends: BASEDEP, \${dep:libgcc}, \${dep:libssp}, \${dep:libgomp}, \${dep:libitm}, \${dep:libatomic}, \${dep:libbtrace}, \${dep:libasan}, \${dep:libtsan}, \${dep:libqmath}, \${dep:libunwinddev}, \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library (development files)
  This package contains the headers and static library files necessary for
@@ -315,10 +316,10 @@
 ifenabled(\`lib4gcc',\`
 Package: libgcc4\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`hppa')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-'))\`'dnl
+')\`'dnl
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Priority: ifdef(\`TARGET',\`extra',required)
 Depends: ifdef(\`STANDALONEJAVA',\`gcj\`'PV-base (>= \${gcj:Version})',\`BASEDEP'), \${shlibs:Depends}, \${misc:Depends}
@@ -335,8 +336,8 @@
 
 Package: libgcc4-dbg\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`hppa')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gcc4,,=,\${gcc:Version}), \${misc:Depends}
@@ -931,10 +932,12 @@
 Package: libgomp\`'GOMP_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgomp'GOMP_SO\`-armel [armel], libgomp'GOMP_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libgomp'GOMP_SO\`-armel [armel], libgomp'GOMP_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -947,8 +950,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gomp\`'GOMP_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libgomp'GOMP_SO\`-dbg-armel [armel], libgomp'GOMP_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libgomp'GOMP_SO\`-dbg-armel [armel], libgomp'GOMP_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC OpenMP (GOMP) support library (debug symbols)
  GOMP is an implementation of OpenMP for the C, C++, and Fortran compilers
@@ -1101,9 +1106,11 @@
 Package: libitm\`'ITM_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libitm'ITM_SO\`-armel [armel], libitm'ITM_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libitm'ITM_SO\`-armel [armel], libitm'ITM_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1117,8 +1124,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(itm\`'ITM_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libitm'ITM_SO\`-dbg-armel [armel], libitm'ITM_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libitm'ITM_SO\`-dbg-armel [armel], libitm'ITM_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GNU Transactional Memory Library (debug symbols)
  GNU Transactional Memory Library (libitm) provides transaction support for
@@ -1287,9 +1296,11 @@
 Package: libatomic\`'ATOMIC_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libatomic'ATOMIC_SO\`-armel [armel], libatomic'ATOMIC_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libatomic'ATOMIC_SO\`-armel [armel], libatomic'ATOMIC_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1302,8 +1313,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(atomic\`'ATOMIC_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libatomic'ATOMIC_SO\`-dbg-armel [armel], libatomic'ATOMIC_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libatomic'ATOMIC_SO\`-dbg-armel [armel], libatomic'ATOMIC_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: support library providing __atomic built-in functions (debug symbols)
  library providing __atomic built-in functions. When an atomic call cannot
@@ -1458,9 +1471,11 @@
 Package: libasan\`'ASAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libasan'ASAN_SO\`-armel [armel], libasan'ASAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libasan'ASAN_SO\`-armel [armel], libasan'ASAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1473,8 +1488,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(asan\`'ASAN_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libasan'ASAN_SO\`-dbg-armel [armel], libasan'ASAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libasan'ASAN_SO\`-dbg-armel [armel], libasan'ASAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: AddressSanitizer -- a fast memory error detector (debug symbols)
  AddressSanitizer (ASan) is a fast memory error detector.  It finds
@@ -1629,9 +1646,11 @@
 Package: libtsan\`'TSAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libtsan'TSAN_SO\`-armel [armel], libtsan'TSAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libtsan'TSAN_SO\`-armel [armel], libtsan'TSAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1644,8 +1663,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(tsan\`'TSAN_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libtsan'TSAN_SO\`-dbg-armel [armel], libtsan'TSAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libtsan'TSAN_SO\`-dbg-armel [armel], libtsan'TSAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: ThreadSanitizer -- a Valgrind-based detector of data races (debug symbols)
  ThreadSanitizer (Tsan) is a data race detector for C/C++ programs. 
@@ -1804,9 +1825,11 @@
 Package: libbacktrace\`'BTRACE_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libbacktrace'BTRACE_SO\`-armel [armel], libbacktrace'BTRACE_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libbacktrace'BTRACE_SO\`-armel [armel], libbacktrace'BTRACE_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1819,8 +1842,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(backtrace\`'BTRACE_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libbacktrace'BTRACE_SO\`-dbg-armel [armel], libbacktrace'BTRACE_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libbacktrace'BTRACE_SO\`-dbg-armel [armel], libbacktrace'BTRACE_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: stack backtrace library (debug symbols)
  libbacktrace uses the GCC unwind interface to collect a stack trace,
@@ -1976,9 +2001,9 @@
 Package: libquadmath\`'QMATH_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1992,8 +2017,8 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(quadmath\`'QMATH_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC Quad-Precision Math Library (debug symbols)
  A library, which provides quad-precision mathematical functions on targets
@@ -2199,8 +2224,8 @@
 Section: libdevel
 Priority: optional
 Depends: BASEDEP, libdevdep(gcc\`'PV-dev,), libdep(objc\`'OBJC_SO,), \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: Runtime library for GNU Objective-C applications (development files)
  This package contains the headers and static library files needed to build
@@ -2277,10 +2302,12 @@
 Package: libobjc\`'OBJC_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libobjc'OBJC_SO\`-armel [armel], libobjc'OBJC_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 ifelse(OBJC_SO,\`2',\`Breaks: \${multiarch:breaks}
-',\`')')\`Provides: libobjc'OBJC_SO\`-armel [armel], libobjc'OBJC_SO\`-armhf [armhf]')
+',\`')')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2290,8 +2317,10 @@
 Package: libobjc\`'OBJC_SO-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libobjc'OBJC_SO\`-dbg-armel [armel], libobjc'OBJC_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libobjc'OBJC_SO\`-dbg-armel [armel], libobjc'OBJC_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libdep(objc\`'OBJC_SO,,=), libdbgdep(gcc\`'GCC_SO-dbg,,>=,\${libgcc:Version}), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2483,8 +2512,8 @@
 Section: ifdef(\`TARGET',\`devel',\`libdevel')
 Priority: optional
 Depends: BASEDEP, libdevdep(gcc\`'PV-dev\`',), libdep(gfortran\`'FORTRAN_SO,), \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: Runtime library for GNU Fortran applications (development files)
  This package contains the headers and static library files needed to build
@@ -2561,10 +2590,12 @@
 Package: libgfortran\`'FORTRAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgfortran'FORTRAN_SO\`-armel [armel], libgfortran'FORTRAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libgfortran'FORTRAN_SO\`-armel [armel], libgfortran'FORTRAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',PRI(optional))
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2575,8 +2606,10 @@
 Package: libgfortran\`'FORTRAN_SO-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libgfortran'FORTRAN_SO\`-dbg-armel [armel], libgfortran'FORTRAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libgfortran'FORTRAN_SO\`-dbg-armel [armel], libgfortran'FORTRAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libdep(gfortran\`'FORTRAN_SO,,=), libdbgdep(gcc\`'GCC_SO-dbg,,>=,\${libgcc:Version}), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2787,9 +2820,11 @@
 Package: libgo\`'GO_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgo'GO_SO\`-armel [armel], libgo'GO_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libgo'GO_SO\`-armel [armel], libgo'GO_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',PRI(optional))
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 Replaces: libgo3\`'LS
@@ -2801,8 +2836,10 @@
 Package: libgo\`'GO_SO-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libgo'GO_SO\`-dbg-armel [armel], libgo'GO_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libgo'GO_SO\`-dbg-armel [armel], libgo'GO_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libdep(go\`'GO_SO,,=), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3152,11 +3189,11 @@
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Priority: ifdef(\`TARGET',\`extra',PRI(important))
 Depends: BASEDEP, \${dep:libc}, \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`Provides: libstdc++CXX_SO-TARGET-dcv1',
+ifdef(\`TARGET',\`Provides: libstdc++CXX_SO-TARGET-dcv1',\`Provides: libstdc++'CXX_SO\`-armel [armel], libstdc++'CXX_SO\`-armhf [armhf]')
 ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libstdc++'CXX_SO\`-armel [armel], libstdc++'CXX_SO\`-armhf [armhf]')
+')\`'dnl
 Conflicts: scim (<< 1.4.2-1)
 BUILT_USING\`'dnl
 Description: GNU Standard C++ Library v3\`'ifdef(\`TARGET)',\` (TARGET)', \`')
@@ -3328,8 +3365,8 @@
 ifenabled(\`c++dev',\`
 Package: libstdc++\`'PV-dev\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Section: ifdef(\`TARGET',\`devel',\`libdevel')
 Priority: ifdef(\`TARGET',\`extra',PRI(optional))
 Depends: BASEDEP, libdevdep(gcc\`'PV-dev,,=), libdep(stdc++CXX_SO,,>=), \${dep:libcdev}, \${misc:Depends}
@@ -3354,8 +3391,8 @@
 
 Package: libstdc++\`'PV-pic\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Section: ifdef(\`TARGET',\`devel',\`libdevel')
 Priority: extra
 Depends: BASEDEP, libdep(stdc++CXX_SO,), libdevdep(stdc++\`'PV-dev,), \${misc:Depends}
@@ -3378,10 +3415,9 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(stdc++CXX_SO,), libdbgdep(gcc\`'GCC_SO-dbg,,>=,\${libgcc:Version}), \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`Provides: libstdc++CXX_SO-dbg-TARGET-dcv1',\`dnl
-ifdef(\`MULTIARCH', \`Multi-Arch: same',\`dnl')
-Provides: libstdc++'CXX_SO\`'PV\`-dbg-armel [armel], libstdc++'CXX_SO\`'PV\`-dbg-armhf [armhf]dnl
-')
+ifdef(\`TARGET',\`Provides: libstdc++CXX_SO-dbg-TARGET-dcv1',\`Provides: libstdc++'CXX_SO\`'PV\`-dbg-armel [armel], libstdc++'CXX_SO\`'PV\`-dbg-armhf [armhf]')
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Recommends: libdevdep(stdc++\`'PV-dev,)
 Conflicts: libstdc++5-dbg\`'LS, libstdc++5-3.3-dbg\`'LS, libstdc++6-dbg\`'LS, libstdc++6-4.0-dbg\`'LS, libstdc++6-4.1-dbg\`'LS, libstdc++6-4.2-dbg\`'LS, libstdc++6-4.3-dbg\`'LS, libstdc++6-4.4-dbg\`'LS, libstdc++6-4.5-dbg\`'LS, libstdc++6-4.6-dbg\`'LS, libstdc++6-4.7-dbg\`'LS
 BUILT_USING\`'dnl
@@ -3678,9 +3714,9 @@
 Package: libgnat\`'-GNAT_V\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: PRI(optional)
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3696,9 +3732,9 @@
 Package: libgnat\`'-GNAT_V-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libgnat\`'-GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3731,9 +3767,9 @@
 
 Package: libgnatvsn\`'GNAT_V\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: PRI(optional)
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Depends: BASEDEP, libgnat\`'-GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
@@ -3750,9 +3786,9 @@
 
 Package: libgnatvsn\`'GNAT_V-dbg\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: extra
 Section: debug
 Depends: BASEDEP, libgnatvsn\`'GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
@@ -3792,9 +3828,9 @@
 
 Package: libgnatprj\`'GNAT_V\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: PRI(optional)
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Depends: BASEDEP, libgnat\`'-GNAT_V\`'LS (= \${gnat:Version}), libgnatvsn\`'GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
@@ -3814,9 +3850,9 @@
 
 Package: libgnatprj\`'GNAT_V-dbg\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: extra
 Section: debug
 Depends: BASEDEP, libgnatprj\`'GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
EOF
	fi
	if test "$GCC_VER" = "4.9"; then
		echo "patching gcc 4.9 to support multiarch crossbuilds #716795"
		patch -p1 <<EOF
diff -u gcc-4.9-4.9-20140411/debian/control.m4 gcc-4.9-4.9-20140411/debian/control.m4
--- gcc-4.9-4.9-20140411/debian/control.m4
+++ gcc-4.9-4.9-20140411/debian/control.m4
@@ -21,6 +21,7 @@
 define(\`depifenabled', \`ifelse(index(enabled_languages, \`\$1'), -1, \`', \`\$2')')
 define(\`ifenabled', \`ifelse(index(enabled_languages, \`\$1'), -1, \`dnl', \`\$2')')
 
+ifdef(\`TARGET',\`ifdef(\`CROSS_ARCH',\`',\`undefine(\`MULTIARCH')')')
 define(\`CROSS_ARCH', ifdef(\`CROSS_ARCH', CROSS_ARCH, \`all'))
 define(\`libdep', \`lib\$2\$1\`'LS\`'AQ (ifelse(\`\$3',\`',\`>=',\`\$3') ifelse(\`\$4',\`',\`\${gcc:Version}',\`\$4'))')
 define(\`libdevdep', \`lib\$2\$1\`'LS\`'AQ (ifelse(\`\$3',\`',\`=',\`\$3') ifelse(\`\$4',\`',\`\${gcc:Version}',\`\$4'))')
@@ -224,11 +225,11 @@
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Priority: ifdef(\`TARGET',\`extra',required)
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`Provides: libgcc1-TARGET-dcv1',
+Provides: ifdef(\`TARGET',\`libgcc1-TARGET-dcv1',\`libgcc1-armel [armel], libgcc1-armhf [armhf]')
 ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libgcc1-armel [armel], libgcc1-armhf [armhf]')
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Shared version of the support library, a library of internal subroutines
@@ -245,10 +246,9 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gcc1,,=,\${gcc:EpochVersion}), \${misc:Depends}
-ifdef(\`TARGET',\`',\`dnl
-ifdef(\`MULTIARCH',\`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgcc1-dbg-armel [armel], libgcc1-dbg-armhf [armhf]
 ')dnl
-Provides: libgcc1-dbg-armel [armel], libgcc1-dbg-armhf [armhf]
+ifdef(\`MULTIARCH',\`Multi-Arch: same
 ')dnl
 BUILT_USING\`'dnl
 Description: GCC support library (debug symbols)\`'ifdef(\`TARGET)',\` (TARGET)', \`')
@@ -265,10 +265,11 @@
 Priority: ifdef(\`TARGET',\`extra',required)
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 ifdef(\`TARGET',\`Provides: libgcc2-TARGET-dcv1
-',ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-'))\`'dnl
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Shared version of the support library, a library of internal subroutines
@@ -285,8 +286,8 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gcc2,,=,\${gcc:Version}), \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC support library (debug symbols)\`'ifdef(\`TARGET)',\` (TARGET)', \`')
  Debug symbols for the GCC support library.
@@ -307,8 +308,8 @@
  \${dep:libatomic}, \${dep:libbtrace}, \${dep:libasan}, \${dep:liblsan},
  \${dep:libtsan}, \${dep:libubsan}, \${dep:libcilkrts}, \${dep:libvtv},
  \${dep:libqmath}, \${dep:libunwinddev}, \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Replaces: gccgo-4.9 (<< \${gcc:Version})
 BUILT_USING\`'dnl
 Description: GCC support library (development files)
@@ -319,10 +320,10 @@
 ifenabled(\`lib4gcc',\`
 Package: libgcc4\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`hppa')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-'))\`'dnl
+')\`'dnl
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Priority: ifdef(\`TARGET',\`extra',required)
 Depends: ifdef(\`STANDALONEJAVA',\`gcj\`'PV-base (>= \${gcj:Version})',\`BASEDEP'), \${shlibs:Depends}, \${misc:Depends}
@@ -339,8 +340,8 @@
 
 Package: libgcc4-dbg\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`hppa')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gcc4,,=,\${gcc:Version}), \${misc:Depends}
@@ -978,10 +979,12 @@
 Package: libgomp\`'GOMP_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgomp'GOMP_SO\`-armel [armel], libgomp'GOMP_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libgomp'GOMP_SO\`-armel [armel], libgomp'GOMP_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -994,8 +997,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(gomp\`'GOMP_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libgomp'GOMP_SO\`-dbg-armel [armel], libgomp'GOMP_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libgomp'GOMP_SO\`-dbg-armel [armel], libgomp'GOMP_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC OpenMP (GOMP) support library (debug symbols)
  GOMP is an implementation of OpenMP for the C, C++, and Fortran compilers
@@ -1148,9 +1153,11 @@
 Package: libitm\`'ITM_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libitm'ITM_SO\`-armel [armel], libitm'ITM_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libitm'ITM_SO\`-armel [armel], libitm'ITM_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1164,8 +1171,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(itm\`'ITM_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libitm'ITM_SO\`-dbg-armel [armel], libitm'ITM_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libitm'ITM_SO\`-dbg-armel [armel], libitm'ITM_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GNU Transactional Memory Library (debug symbols)
  GNU Transactional Memory Library (libitm) provides transaction support for
@@ -1334,9 +1343,11 @@
 Package: libatomic\`'ATOMIC_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libatomic'ATOMIC_SO\`-armel [armel], libatomic'ATOMIC_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libatomic'ATOMIC_SO\`-armel [armel], libatomic'ATOMIC_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1349,8 +1360,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(atomic\`'ATOMIC_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libatomic'ATOMIC_SO\`-dbg-armel [armel], libatomic'ATOMIC_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libatomic'ATOMIC_SO\`-dbg-armel [armel], libatomic'ATOMIC_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: support library providing __atomic built-in functions (debug symbols)
  library providing __atomic built-in functions. When an atomic call cannot
@@ -1505,9 +1518,11 @@
 Package: libasan\`'ASAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libasan'ASAN_SO\`-armel [armel], libasan'ASAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libasan'ASAN_SO\`-armel [armel], libasan'ASAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1520,8 +1535,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(asan\`'ASAN_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libasan'ASAN_SO\`-dbg-armel [armel], libasan'ASAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libasan'ASAN_SO\`-dbg-armel [armel], libasan'ASAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: AddressSanitizer -- a fast memory error detector (debug symbols)
  AddressSanitizer (ASan) is a fast memory error detector.  It finds
@@ -1676,9 +1693,11 @@
 Package: liblsan\`'LSAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: liblsan'LSAN_SO\`-armel [armel], liblsan'LSAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: liblsan'LSAN_SO\`-armel [armel], liblsan'LSAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1691,8 +1710,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(lsan\`'LSAN_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: liblsan'LSAN_SO\`-dbg-armel [armel], liblsan'LSAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: liblsan'LSAN_SO\`-dbg-armel [armel], liblsan'LSAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: LeakSanitizer -- a memory leak detector (debug symbols)
  LeakSanitizer (Lsan) is a memory leak detector which is integrated
@@ -1853,9 +1874,11 @@
 Package: libtsan\`'TSAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libtsan'TSAN_SO\`-armel [armel], libtsan'TSAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libtsan'TSAN_SO\`-armel [armel], libtsan'TSAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -1868,8 +1891,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(tsan\`'TSAN_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libtsan'TSAN_SO\`-dbg-armel [armel], libtsan'TSAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libtsan'TSAN_SO\`-dbg-armel [armel], libtsan'TSAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: ThreadSanitizer -- a Valgrind-based detector of data races (debug symbols)
  ThreadSanitizer (Tsan) is a data race detector for C/C++ programs. 
@@ -2028,9 +2053,11 @@
 Package: libubsan\`'UBSAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libubsan'UBSAN_SO\`-armel [armel], libubsan'UBSAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libubsan'UBSAN_SO\`-armel [armel], libubsan'UBSAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2044,8 +2071,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(ubsan\`'UBSAN_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libubsan'UBSAN_SO\`-dbg-armel [armel], libubsan'UBSAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libubsan'UBSAN_SO\`-dbg-armel [armel], libubsan'UBSAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: UBSan -- undefined behaviour sanitizer (debug symbols)
  UndefinedBehaviorSanitizer can be enabled via -fsanitize=undefined.
@@ -2220,9 +2249,11 @@
 Package: libvtv\`'VTV_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libvtv'VTV_SO\`-armel [armel], libvtv'VTV_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libvtv'VTV_SO\`-armel [armel], libvtv'VTV_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2237,8 +2268,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(vtv\`'VTV_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libvtv'VTV_SO\`-dbg-armel [armel], libvtv'VTV_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libvtv'VTV_SO\`-dbg-armel [armel], libvtv'VTV_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GNU vtable verification library (debug symbols)
  Vtable verification is a new security hardening feature for GCC that
@@ -2427,9 +2460,11 @@
 Package: libcilkrts\`'CILKRTS_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libcilkrts'CILKRTS_SO\`-armel [armel], libcilkrts'CILKRTS_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libcilkrts'CILKRTS_SO\`-armel [armel], libcilkrts'CILKRTS_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2442,8 +2477,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(cilkrts\`'CILKRTS_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libcilkrts'CILKRTS_SO\`-dbg-armel [armel], libcilkrts'CILKRTS_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libcilkrts'CILKRTS_SO\`-dbg-armel [armel], libcilkrts'CILKRTS_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: Intel Cilk Plus language extensions (debug symbols)
  Intel Cilk Plus is an extension to the C and C++ languages to support
@@ -2604,9 +2641,11 @@
 Package: libbacktrace\`'BTRACE_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libbacktrace'BTRACE_SO\`-armel [armel], libbacktrace'BTRACE_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libbacktrace'BTRACE_SO\`-armel [armel], libbacktrace'BTRACE_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2619,8 +2658,10 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(backtrace\`'BTRACE_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libbacktrace'BTRACE_SO\`-dbg-armel [armel], libbacktrace'BTRACE_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libbacktrace'BTRACE_SO\`-dbg-armel [armel], libbacktrace'BTRACE_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: stack backtrace library (debug symbols)
  libbacktrace uses the GCC unwind interface to collect a stack trace,
@@ -2776,9 +2817,9 @@
 Package: libquadmath\`'QMATH_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -2792,8 +2833,8 @@
 Section: debug
 Priority: extra
 Depends: BASEDEP, libdep(quadmath\`'QMATH_SO,,=), \${misc:Depends}
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: GCC Quad-Precision Math Library (debug symbols)
  A library, which provides quad-precision mathematical functions on targets
@@ -2999,8 +3040,8 @@
 Section: libdevel
 Priority: optional
 Depends: BASEDEP, libdevdep(gcc\`'PV-dev,), libdep(objc\`'OBJC_SO,), \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: Runtime library for GNU Objective-C applications (development files)
  This package contains the headers and static library files needed to build
@@ -3077,10 +3118,12 @@
 Package: libobjc\`'OBJC_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libobjc'OBJC_SO\`-armel [armel], libobjc'OBJC_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 ifelse(OBJC_SO,\`2',\`Breaks: \${multiarch:breaks}
-',\`')')\`Provides: libobjc'OBJC_SO\`-armel [armel], libobjc'OBJC_SO\`-armhf [armhf]')
+',\`')')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',\`PRI(optional)')
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3090,8 +3133,10 @@
 Package: libobjc\`'OBJC_SO-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libobjc'OBJC_SO\`-dbg-armel [armel], libobjc'OBJC_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libobjc'OBJC_SO\`-dbg-armel [armel], libobjc'OBJC_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libdep(objc\`'OBJC_SO,,=), libdbgdep(gcc\`'GCC_SO-dbg,,>=,\${libgcc:Version}), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3283,8 +3328,8 @@
 Section: ifdef(\`TARGET',\`devel',\`libdevel')
 Priority: optional
 Depends: BASEDEP, libdevdep(gcc\`'PV-dev\`',), libdep(gfortran\`'FORTRAN_SO,), \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 BUILT_USING\`'dnl
 Description: Runtime library for GNU Fortran applications (development files)
  This package contains the headers and static library files needed to build
@@ -3361,10 +3406,12 @@
 Package: libgfortran\`'FORTRAN_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgfortran'FORTRAN_SO\`-armel [armel], libgfortran'FORTRAN_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libgfortran'FORTRAN_SO\`-armel [armel], libgfortran'FORTRAN_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',PRI(optional))
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3375,8 +3422,10 @@
 Package: libgfortran\`'FORTRAN_SO-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libgfortran'FORTRAN_SO\`-dbg-armel [armel], libgfortran'FORTRAN_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libgfortran'FORTRAN_SO\`-dbg-armel [armel], libgfortran'FORTRAN_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libdep(gfortran\`'FORTRAN_SO,,=), libdbgdep(gcc\`'GCC_SO-dbg,,>=,\${libgcc:Version}), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3587,9 +3636,11 @@
 Package: libgo\`'GO_SO\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`TARGET',\`',\`Provides: libgo'GO_SO\`-armel [armel], libgo'GO_SO\`-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-')\`Provides: libgo'GO_SO\`-armel [armel], libgo'GO_SO\`-armhf [armhf]')
+')\`'dnl
 Priority: ifdef(\`TARGET',\`extra',PRI(optional))
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 Replaces: libgo3\`'LS
@@ -3601,8 +3652,10 @@
 Package: libgo\`'GO_SO-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
-')\`Provides: libgo'GO_SO\`-dbg-armel [armel], libgo'GO_SO\`-dbg-armhf [armhf]')
+ifdef(\`TARGET',\`',\`Provides: libgo'GO_SO\`-dbg-armel [armel], libgo'GO_SO\`-dbg-armhf [armhf]
+')\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libdep(go\`'GO_SO,,=), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -3946,11 +3999,11 @@
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Priority: ifdef(\`TARGET',\`extra',PRI(important))
 Depends: BASEDEP, \${dep:libc}, \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`Provides: libstdc++CXX_SO-TARGET-dcv1',
+Provides: ifdef(\`TARGET',\`libstdc++CXX_SO-TARGET-dcv1',\`libstdc++'CXX_SO\`-armel [armel], libstdc++'CXX_SO\`-armhf [armhf]')
 ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
 Breaks: \${multiarch:breaks}
-')\`Provides: libstdc++'CXX_SO\`-armel [armel], libstdc++'CXX_SO\`-armhf [armhf]')
+')\`'dnl
 Conflicts: scim (<< 1.4.2-1)
 BUILT_USING\`'dnl
 Description: GNU Standard C++ Library v3\`'ifdef(\`TARGET)',\` (TARGET)', \`')
@@ -4122,8 +4175,8 @@
 ifenabled(\`c++dev',\`
 Package: libstdc++\`'PV-dev\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Section: ifdef(\`TARGET',\`devel',\`libdevel')
 Priority: ifdef(\`TARGET',\`extra',PRI(optional))
 Depends: BASEDEP, libdevdep(gcc\`'PV-dev,,=),
@@ -4151,8 +4204,8 @@
 
 Package: libstdc++\`'PV-pic\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`',ifdef(\`MULTIARCH', \`Multi-Arch: same
-'))\`'dnl
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Section: ifdef(\`TARGET',\`devel',\`libdevel')
 Priority: extra
 Depends: BASEDEP, libdep(stdc++CXX_SO,),
@@ -4177,10 +4230,9 @@
 Priority: extra
 Depends: BASEDEP, libdep(stdc++CXX_SO,),
  libdbgdep(gcc\`'GCC_SO-dbg,,>=,\${libgcc:Version}), \${shlibs:Depends}, \${misc:Depends}
-ifdef(\`TARGET',\`Provides: libstdc++CXX_SO-dbg-TARGET-dcv1',\`dnl
-ifdef(\`MULTIARCH', \`Multi-Arch: same',\`dnl')
-Provides: libstdc++'CXX_SO\`'PV\`-dbg-armel [armel], libstdc++'CXX_SO\`'PV\`-dbg-armhf [armhf]dnl
-')
+Provides: ifdef(\`TARGET',\`libstdc++CXX_SO-dbg-TARGET-dcv1',\`libstdc++'CXX_SO\`'PV\`-dbg-armel [armel], libstdc++'CXX_SO\`'PV\`-dbg-armhf [armhf]')
+ifdef(\`MULTIARCH', \`Multi-Arch: same
+')\`'dnl
 Recommends: libdevdep(stdc++\`'PV-dev,)
 Conflicts: libstdc++5-dbg\`'LS, libstdc++5-3.3-dbg\`'LS, libstdc++6-dbg\`'LS,
  libstdc++6-4.0-dbg\`'LS, libstdc++6-4.1-dbg\`'LS, libstdc++6-4.2-dbg\`'LS,
@@ -4511,9 +4563,9 @@
 Package: libgnat\`'-GNAT_V\`'LS
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: PRI(optional)
 Depends: BASEDEP, \${shlibs:Depends}, \${misc:Depends}
 BUILT_USING\`'dnl
@@ -4529,9 +4581,9 @@
 Package: libgnat\`'-GNAT_V-dbg\`'LS
 Section: debug
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: extra
 Depends: BASEDEP, libgnat\`'-GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
 BUILT_USING\`'dnl
@@ -4564,9 +4616,9 @@
 
 Package: libgnatvsn\`'GNAT_V\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: PRI(optional)
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Depends: BASEDEP, libgnat\`'-GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
@@ -4583,9 +4635,9 @@
 
 Package: libgnatvsn\`'GNAT_V-dbg\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: extra
 Section: debug
 Depends: BASEDEP, libgnatvsn\`'GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
@@ -4625,9 +4677,9 @@
 
 Package: libgnatprj\`'GNAT_V\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: PRI(optional)
 Section: ifdef(\`TARGET',\`devel',\`libs')
 Depends: BASEDEP, libgnat\`'-GNAT_V\`'LS (= \${gnat:Version}), libgnatvsn\`'GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
@@ -4647,9 +4699,9 @@
 
 Package: libgnatprj\`'GNAT_V-dbg\`'LS
 Architecture: ifdef(\`TARGET',\`CROSS_ARCH',\`any')
-ifdef(\`TARGET',\`dnl',ifdef(\`MULTIARCH', \`Multi-Arch: same
+ifdef(\`MULTIARCH', \`Multi-Arch: same
 Pre-Depends: multiarch-support
-'))\`'dnl
+')\`'dnl
 Priority: extra
 Section: debug
 Depends: BASEDEP, libgnatprj\`'GNAT_V\`'LS (= \${gnat:Version}), \${misc:Depends}
EOF
	fi # vim syntax deconfusion: '
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
	if test "$ENABLE_MULTILIB" = yes; then
		DEB_TARGET_ARCH=$HOST_ARCH DEB_STAGE=stage1 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends again after rewriting control
		DEB_TARGET_ARCH=$HOST_ARCH DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us
	else
		DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -T control
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends again after rewriting control
		DEB_TARGET_ARCH=$HOST_ARCH DEB_CROSS_NO_BIARCH=yes DEB_STAGE=stage1 dpkg-buildpackage -d -B -uc -us
	fi
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
ln -s ../include/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_MULTIARCH` /usr/`dpkg-architecture -a$HOST_ARCH -qDEB_HOST_GNU_TYPE`/sys-include

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
	if test "$ENABLE_MULTILIB" = yes; then
		dpkg-checkbuilddeps -B -a$HOST_ARCH -Pstage2 || : # tell unmet build depends
		DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d -Pstage2
	else
		dpkg-checkbuilddeps -B -a$HOST_ARCH -Pstage2,nobiarch || : # tell unmet build depends
		DEB_GCC_VERSION=-$GCC_VER dpkg-buildpackage -B -uc -us -a$HOST_ARCH -d -Pstage2,nobiarch
	fi
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
	rm -fv gcc-*-plugin-*.deb gcj-*.deb gdc-*.deb *gfortran*.deb *objc*.deb *-dbg_*.deb
	dpkg -i *.deb
	apt-get check || :
	apt-get --no-download update || : # work around #745036
	apt-get check || :
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

if test -d "$RESULT/pcre3"; then
	echo "skipping rebuild of pcre3"
else
	apt-get -y -a$HOST_ARCH --arch-only build-dep pcre3
	cd /tmp/buildd
	mkdir pcre3
	cd pcre3
	obtain_source_package pcre3
	cd pcre3-*
	echo "patching pcre3 to use host cc for jit detection #745222"
	patch -p1 <<EOF
diff -Nru pcre3-8.31/debian/rules pcre3-8.31/debian/rules
--- pcre3-8.31/debian/rules
+++ pcre3-8.31/debian/rules
@@ -28,7 +28,7 @@
 endif
 
 jit-test: debian/jit-test.c
-	\$(CC) $< -o \$@
+	\$(DEB_HOST_GNU_TYPE)-gcc $< -o \$@
 
 config.status: configure jit-test
 	dh_testdir
EOF
	dpkg-buildpackage -a$HOST_ARCH -B -uc -us
	cd ..
	ls -l
	test -d "$RESULT" && mkdir "$RESULT/pcre3"
	cd ..
	rm -Rf pcre3
fi
echo "progress-mark:8:pcre3 cross build"

if test -d "$RESULT/attr"; then
	echo "skipping rebuild of attr"
	dpkg -i "$RESULT/attr/"libattr*.deb
else
	apt-get -y install dpkg-dev debhelper autoconf automake gettext libtool
	cd /tmp/buildd
	mkdir attr
	cd attr
	obtain_source_package attr
	cd attr-*
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	dpkg-buildpackage -a$HOST_ARCH -B -d -uc -us
	cd ..
	ls -l
	dpkg -i libattr*.deb
	test -d "$RESULT" && mkdir "$RESULT/attr"
	test -d "$RESULT" && cp *.deb "$RESULT/attr/"
	cd ..
	rm -Rf attr
fi
echo "progress-mark:9:attr cross build"

if test -d "$RESULT/acl"; then
	echo "skipping rebuild of acl"
else
	apt-get -y install dpkg-dev debhelper autotools-dev autoconf automake gettext libtool
	cd /tmp/buildd
	mkdir acl
	cd acl
	obtain_source_package acl
	cd acl-*
	dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
	dpkg-buildpackage -a$HOST_ARCH -B -d -uc -us
	cd ..
	ls -l
	test -d "$RESULT" && mkdir "$RESULT/acl"
	test -d "$RESULT" && cp *.deb "$RESULT/acl/"
	cd ..
	rm -Rf acl
fi
echo "progress-mark:10:acl cross build"

if test -d "$RESULT/zlib"; then
	echo "skipping rebuild of zlib"
else
	apt-get -y install debhelper binutils dpkg-dev
	cd /tmp/buildd
	mkdir zlib
	cd zlib
	obtain_source_package zlib
	cd zlib-*
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
	if test "$ENABLE_MULTILIB" = yes; then
		dpkg-checkbuilddeps -a$HOST_ARCH || : # tell unmet build depends
		dpkg-buildpackage -a$HOST_ARCH -B -d -uc -us
	else
		dpkg-checkbuilddeps -a$HOST_ARCH -Pnobiarch || : # tell unmet build depends
		dpkg-buildpackage -a$HOST_ARCH -B -d -uc -us -Pnobiarch
	fi
	cd ..
	ls -l
	test -d "$RESULT" && mkdir "$RESULT/zlib"
	test -d "$RESULT" && cp *.deb "$RESULT/zlib/"
	cd ..
	rm -Rf zlib
fi
echo "progress-mark:11:zlib cross build"

if test -d "$RESULT/hostname"; then
	echo "skipping rebuild of hostname"
else
	apt-get -y -a$HOST_ARCH --arch-only build-dep hostname
	cd /tmp/buildd
	mkdir hostname
	cd hostname
	obtain_source_package hostname
	cd hostname-*
	dpkg-buildpackage -a$HOST_ARCH -B -uc -us
	cd ..
	ls -l
	test -d "$RESULT" && mkdir "$RESULT/hostname"
	test -d "$RESULT" && cp *.deb "$RESULT/hostname/"
	cd ..
	rm -Rf hostname
fi
echo "progress-mark:12:hostname cross build"

if test -d "$RESULT/libsepol"; then
	echo "skipping rebuild of libsepol"
else
	apt-get -y -a$HOST_ARCH --arch-only build-dep libsepol
	cd /tmp/buildd
	mkdir libsepol
	cd libsepol
	obtain_source_package libsepol
	cd libsepol-*
	dpkg-buildpackage -a$HOST_ARCH -B -uc -us
	cd ..
	ls -l
	test -d "$RESULT" && mkdir "$RESULT/libsepol"
	test -d "$RESULT" && cp *.deb "$RESULT/libsepol/"
	cd ..
	rm -Rf libsepol
fi
echo "progress-mark:13:libsepol cross build"

if test -d "$RESULT/gmp"; then
	echo "skipping rebuild of gmp"
	dpkg -i "$RESULT/gmp/"libgmp*.deb
else
	apt-get -y -a$HOST_ARCH --arch-only build-dep gmp
	cd /tmp/buildd
	mkdir gmp
	cd gmp
	obtain_source_package gmp
	cd gmp-*
	dpkg-buildpackage -a$HOST_ARCH -B -uc -us
	cd ..
	ls -l
	dpkg -i libgmp*.deb
	test -d "$RESULT" && mkdir "$RESULT/gmp"
	test -d "$RESULT" && cp *.deb "$RESULT/gmp/"
	cd ..
	rm -Rf gmp
fi
echo "progress-mark:14:gmp cross build"

if test -d "$RESULT/mpfr4"; then
	echo "skipping rebuild of mpfr4"
else
	apt-get -y -a$HOST_ARCH --arch-only build-dep mpfr4
	cd /tmp/buildd
	mkdir mpfr4
	cd mpfr4
	obtain_source_package mpfr4
	cd mpfr4-*
	dpkg-buildpackage -a$HOST_ARCH -B -uc -us
	cd ..
	ls -l
	test -d "$RESULT" && mkdir "$RESULT/mpfr4"
	test -d "$RESULT" && cp *.deb "$RESULT/mpfr4/"
	cd ..
	rm -Rf mpfr4
fi
echo "progress-mark:15:mpfr4 cross build"
