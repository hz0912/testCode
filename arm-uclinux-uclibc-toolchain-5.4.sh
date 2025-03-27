#!/bin/sh
#
# arm-uclinux-toolchain.sh  -- build an arm-uclinux toolchain
#
# (C) Copyright 2013-2016,  Greg Ungerer <gerg@uclinux.org>
# (C) Copyright 2013,  David McCullough <ucdevel@gmail.com>
#

ARCH=arm
TARGET=arm-uclinuxeabi
PREFIX=/usr/local
PREFIX_TARGET=${PREFIX}/${TARGET}

BINUTILS_VERSION=2.26
GCC_VERSION=5.4.0
UCLIBC_VERSION=0.9.33.2
GDB_VERSION=7.6
LINUX_VERSION=4.4
ELF2FLT_VERSION=20160825

###########################################################################

extract()
{
	for i in "$@"
	do
		echo "Extracting $i..."
		case "$i" in
		*.tar.gz|*.tgz)   tar xzf "$i" ;;
		*.tar.bz2|*.tbz2) tar xjf "$i" ;;
		*.tar.xz|*.txz)   tar xJf "$i" ;;
		*.tar)            tar xf  "$i" ;;
		*)                echo "Unknown file format $i" >&2
		                  return 1 ;;
		esac
	done
	return 0
}

build_binutils()
{
	cd ${ROOTDIR}
	echo "BUILD: binutils-${BINUTILS_VERSION}"

	extract binutils-${BINUTILS_VERSION}.tar.*
	cd binutils-${BINUTILS_VERSION}

	mkdir ${TARGET}
	cd ${TARGET}

	../configure --target=${TARGET} --with-lib-path=${PREFIX_TARGET}/lib:${PREFIX_TARGET}/lib/be:${PREFIX_TARGET}/lib/be/soft-float:${PREFIX_TARGET}/lib/soft-float
	../configure --target=${TARGET}
	make || exit 1
	make install || exit 1
	return 0
}


build_linux_headers()
{
	cd ${ROOTDIR}
	echo "BUILD: linux-${LINUX_VERSION} headers"

	extract linux-${LINUX_VERSION}.tar.*
	cd linux-${LINUX_VERSION}
	make ARCH=${ARCH} defconfig || exit 1
	make ARCH=${ARCH} headers_install || exit 1
	cp -a usr/include ${PREFIX_TARGET}/
	return 0
}

build_package()
{
	PACKAGE=$1
	VERSION=$2

	cd ${ROOTDIR}
	echo "BUILD: ${PACKAGE}-${VERSION}"

	extract ${PACKAGE}-${VERSION}.tar.*
	cd ${PACKAGE}-${VERSION}
	./configure || exit 1
	make || exit 1
	make install || exit 1

	return 0
}

build_gcc()
{
	PASS=$1
	CFGOPTS=""

	cd ${ROOTDIR}
	echo "BUILD: gcc-${GCC_VERSION} (pass ${PASS})"

	if [ "${PASS}" = 1 ] ; then
		CFGOPTS="--enable-newlib \
			--disable-threads \
			--disable-libgomp \
			--disable-libmudflap \
			--disable-shared \
			--disable-libssp \
			--disable-libquadmath \
			--enable-languages=c"
	else
		CFGOPTS="--enable-languages=c,c++"
	fi

	extract gcc-${GCC_VERSION}.tar.*
	mv gcc-${GCC_VERSION} gcc-${GCC_VERSION}.pass-${PASS}
	cd gcc-${GCC_VERSION}.pass-${PASS}

	patch -p1 < ../gcc-5.4.0-arm-uclinux-multilib.patch

	chmod +x contrib/download_prerequisites
	contrib/download_prerequisites || exit 1

	mkdir ${TARGET}
	cd ${TARGET}

	../configure --target=${TARGET} \
		--with-float=hard \
		--enable-multilib \
		--with-system-zlib \
		--disable-libsanitizer \
		${CFGOPTS} \
		--prefix=${PREFIX} || exit 1
	make || [ $PASS -eq 1 ] || exit 1
	make install || [ $PASS -eq 1 ] || exit 1

	#if [ "${PASS}" = 1 ] ; then
	#	LIBGCC_DIR=${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}
	#	ln ${LIBGCC_DIR}/libgcc.a ${LIBGCC_DIR}/libgcc_eh.a
	#	ln ${LIBGCC_DIR}/be/libgcc.a ${LIBGCC_DIR}/be/libgcc_eh.a
	#	ln ${LIBGCC_DIR}/be/soft-float/libgcc.a ${LIBGCC_DIR}/be/soft-float/libgcc_eh.a
	#	ln ${LIBGCC_DIR}/soft-float/libgcc.a ${LIBGCC_DIR}/soft-float/libgcc_eh.a
	#fi

	return 0
}

build_uclibc()
{
	MULTILIB=$1
	CFLAGS=""
	AFLAGS=""
	LDFLAGS=""
	LIBDIR=""

	# Default to little-endian/float=softfp (compat fpu/soft)
	CFGENDIANSTR="ARCH_LITTLE_ENDIAN=y"
	CFGWANTSLTLSTR="ARCH_WANTS_LITTLE_ENDIAN=y"
	CFGWANTSBIGSTR="# ARCH_WANTS_BIG_ENDIAN is not set"
	CFGFPUSTR="UCLIBC_HAS_FPU=y"
	CFGSFSTR="# UCLIBC_HAS_SOFT_FLOAT is not set"

	cd ${ROOTDIR}
	echo "BUILD: uClibc-${UCLIBC_VERSION} (type ${MULTILIB})"

	case "$MULTILIB" in
	*big-endian*|*be*)
		CFLAGS="${CFLAGS} -mbig-endian"
		AFLAGS="${AFLAGS} -mbig-endian"
		LDFLAGS="${LDFLAGS} -EB"
		LIBDIR="${LIBDIR}/be"
		CFGENDIANSTR="ARCH_BIG_ENDIAN=y"
		CFGWANTSLTLSTR="# ARCH_WANTS_LITTLE_ENDIAN is not set"
		CFGWANTSBIGSTR="ARCH_WANTS_BIG_ENDIAN=y"
		;;
	*little-endian*|*le*)
		CFLAGS="${CFLAGS} -mlittle-endian"
		AFLAGS="${AFLAGS} -mlittle-endian"
		LDFLAGS="${LDFLAGS} -EL"
		LIBDIR="${LIBDIR}/le"
		CFGENDIANSTR="ARCH_LITTLE_ENDIAN=y"
		CFGWANTSLTLSTR="ARCH_WANTS_LITTLE_ENDIAN=y"
		CFGWANTSBIGSTR="# ARCH_WANTS_BIG_ENDIAN is not set"
		;;
	esac

	case "$MULTILIB" in
	*soft-float*|*sf*)
		CFLAGS="${CFLAGS} -mfloat-abi=soft"
		LIBDIR="${LIBDIR}/soft-float"
		CFGFPUSTR="# UCLIBC_HAS_FPU is not set"
		CFGSFSTR="UCLIBC_HAS_SOFT_FLOAT=y"
		;;
	*hard-float*|*hf*)
		CFLAGS="${CFLAGS} -mfloat-abi=hard"
		#LIBDIR="${LIBDIR}/hard-float"
		CFGFPUSTR="UCLIBC_HAS_FPU=y"
		CFGSFSTR="# UCLIBC_HAS_SOFT_FLOAT is not set"
		;;
	esac

	rm -rf uClibc-${UCLIBC_VERSION}.${MULTILIB}
	extract uClibc-${UCLIBC_VERSION}.tar.*
	mv uClibc-${UCLIBC_VERSION} uClibc-${UCLIBC_VERSION}.${MULTILIB}
	cd uClibc-${UCLIBC_VERSION}.${MULTILIB}

	patch -p2 < ../uClibc-0.9.33.2-types.patch || exit 1
	patch -p1 < ../uClibc-0.9.33.2-backtrace.patch || exit 1
	patch -p1 < ../uClibc-0.9.33.2-unwind-resume.patch || exit 1

	make ARCH=${ARCH} defconfig || exit 1

	KHDR=`echo ${PREFIX_TARGET}/include | sed -e 's/\//\\\\\//g'`
	PDIR=`echo ${PREFIX_TARGET} | sed -e 's/\//\\\\\//g'`
	DDIR=`echo ${PREFIX_TARGET}/usr/ | sed -e 's/\//\\\\\//g'`
	LDIR=`echo lib${LIBDIR} | sed -e 's/\//\\\\\//g'`

	cat .config | \
	sed -e "s/^# CONFIG_ARM_EABI.*$/CONFIG_ARM_EABI=y/" | \
	sed -e "s/^ARCH_BIG_ENDIAN.*$/${CFGENDIANSTR}/" | \
	sed -e "s/^ARCH_WANTS_BIG_ENDIAN.*$/${CFGWANTSBIGSTR}/" | \
	sed -e "s/^# ARCH_WANTS_LITTLE_ENDIAN.*$/${CFGWANTSLTLSTR}/" | \
	sed -e "s/^UCLIBC_HAS_FPU.*$/${CFGFPUSTR}\n${CFGSFSTR}/" | \
	sed -e "s/^KERNEL_HEADERS.*$/KERNEL_HEADERS=\"${KHDR}\"/" | \
	sed -e "s/^RUNTIME_PREFIX.*$/RUNTIME_PREFIX=\"${PDIR}\"/" | \
	sed -e "s/^DEVEL_PREFIX.*$/DEVEL_PREFIX=\"${PDIR}\"/" | \
	sed -e "s/^MULTILIB_DIR.*$/MULTILIB_DIR=\"${LDIR}\"/" | \
	sed -e "s/^CROSS_COMPILER_PREFIX.*$/CROSS_COMPILER_PREFIX=\"${TARGET}-\"/" | \
	sed -e "s/^UCLIBC_EXTRA_CFLAGS.*$/UCLIBC_EXTRA_CFLAGS=\"${CFLAGS}\"/" | \
	sed -e "s/ARCH_HAS_MMU=y/# ARCH_HAS_MMU is not set/" | \
	sed -e "s/DOPIC=y/# DOPIC is not set/" | \
	sed -e "/ARCH_USE_MMU=y/d" | \
	sed -e "/HAVE_SHARED=y/d" | \
	sed -e "/PTHREADS_DEBUG_SUPPORT/d" | \
	sed -e "/UCLIBC_SUSV4_LEGACY/d" | \
	sed -e "/UCLIBC_SUSV3_LEGACY/d" | \
	sed -e "/UCLIBC_SUSV3_LEGACY_MACROS/d" | \
	sed -e "/UCLIBC_HAS_BACKTRACE/d" | \
	sed -e "/UCLIBC_USE_NETLINK/d" | \
	sed -e "/UCLIBC_SUPPORT_AI_ADDRCONFIG/d" | \
	cat > /tmp/config
	echo "# UCLIBC_FORMAT_ELF is not set" >> /tmp/config
	echo "# UCLIBC_FORMAT_FDPIC_ELF is not set" >> /tmp/config
	echo "# UCLIBC_FORMAT_DSBT_ELF is not set" >> /tmp/config
	echo UCLIBC_FORMAT_FLAT=y >> /tmp/config
	echo "# UCLIBC_FORMAT_FLAT_SEP_DATA is not set" >> /tmp/config
	echo "# UCLIBC_FORMAT_SHARED_FLAT is not set" >> /tmp/config
	echo PTHREADS_DEBUG_SUPPORT=n >> /tmp/config
	echo UCLIBC_SUSV3_LEGACY=y >> /tmp/config
	echo UCLIBC_SUSV3_LEGACY_MACROS=y >> /tmp/config
	echo UCLIBC_SUSV4_LEGACY=y >> /tmp/config
	echo UCLIBC_HAS_BACKTRACE=y >> /tmp/config
	echo UCLIBC_USE_NETLINK=y >> /tmp/config
	echo UCLIBC_SUPPORT_AI_ADDRCONFIG=y >> /tmp/config
	echo "# UCLIBC_HAS_FTW is not set" >> /tmp/config

	cp /tmp/config .config

	make ARCH=${ARCH} oldconfig

	if [ "${MULTILIB}" = headers ] ; then
		make install_headers || exit 1
		return 0
	fi

	make || exit 1
	make install || exit 1

	return 0
}

build_gdb()
{
	cd ${ROOTDIR}
	echo "BUILD: gdb-${GDB_VERSION}"

	extract gdb-${GDB_VERSION}.tar.*
	cd gdb-${GDB_VERSION}

	mkdir ${TARGET}
	cd ${TARGET}

	../configure --target=${TARGET} || exit 1
	make || exit 1
	make install || exit 1

	return 0
}

build_elf2flt()
{
	cd ${ROOTDIR}
	echo "BUILD: elf2flt-${ELF2FLT_VERSION}"

	extract elf2flt-${ELF2FLT_VERSION}.tar.*
	#mv elf2flt elf2flt-${ELF2FLT_VERSION}
	cd elf2flt-${ELF2FLT_VERSION}

	./configure --target=${TARGET} \
		--with-libbfd=${ROOTDIR}/binutils-${BINUTILS_VERSION}/${TARGET}/bfd/libbfd.a \
		--with-libiberty=${ROOTDIR}/binutils-${BINUTILS_VERSION}/${TARGET}/libiberty/libiberty.a \
		--with-binutils-include-dir=${ROOTDIR}/binutils-${BINUTILS_VERSION}/include \
		--with-bfd-include-dir=${ROOTDIR}/binutils-${BINUTILS_VERSION}/${TARGET}/bfd || exit 1

	make || exit 1
	make install || exit 1

	return 0
}

build_tarball()
{
	DATE=`date +%Y%m%d`
	PACKAGE="${TARGET}-tools-${DATE}.tar.gz"

	echo "BUILD: packaging ${PACKAGE}"

	cd /
	strip ${PREFIX_TARGET}/bin/* 2> /dev/null || true
	strip ${PREFIX}/bin/${TARGET}-* 2> /dev/null || true
	strip ${PREFIX}/libexec/gcc/${TARGET}/${GCC_VERSION}/* 2> /dev/null || true
	tar cvzf ${ROOTDIR}/${PACKAGE} \
		${PREFIX_TARGET} \
		${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION} \
		${PREFIX}/libexec/gcc/${TARGET}/${GCC_VERSION} \
		${PREFIX}/bin/${TARGET}-*

	return 0
}

build_clean()
{
	echo "BUILD: cleaning up..."

	rm -rf gcc-${GCC_VERSION}.pass*
	rm -rf binutils-${BINUTILS_VERSION}
	rm -rf uClibc-${UCLIBC_VERSION}.headers
	rm -rf uClibc-${UCLIBC_VERSION}.
	rm -rf uClibc-${UCLIBC_VERSION}.big*
	rm -rf uClibc-${UCLIBC_VERSION}.soft*
	rm -rf gdb-${GDB_VERSION}
	rm -rf linux-${LINUX_VERSION}
	rm -rf elf2flt-${ELF2FLT_VERSION}
	rm -rf ${TARGET}-tools-*

	rm -rf ${PREFIX_TARGET}
	rm -rf ${PREFIX}/bin/${TARGET}-[a-zA-Z]*
	rm -rf ${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}
	rm -rf ${PREFIX}/libexec/gcc/${TARGET}/${GCC_VERSION}

	return 0
}

###########################################################################

ROOTDIR=`pwd`

if [ "$1" = clean ] ; then
	build_clean
	exit 0
fi
if [ "$1" = package ] ; then
	build_tarball
	exit $?
fi
if [ "$1" ] ; then
	build_$1 $2 $3 $4 $5 $6 $7 $8 $9
	exit $?
fi

echo "BUILD: target=${TARGET}"

# If anything fails we want the build to stop
set -e
ulimit -n 4096

mkdir -p ${PREFIX_TARGET}
chmod 777 ${PREFIX_TARGET}

build_binutils
build_linux_headers
build_uclibc headers
build_gcc 1
build_uclibc
build_uclibc soft-float
build_uclibc big-endian
build_uclibc big-endian+soft-float
build_gcc 2
build_gdb
build_elf2flt
build_tarball

exit 0
