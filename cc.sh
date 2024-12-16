#!/usr/bin/env bash
# need a bit of special configuration for cross-compiling cctools-port ...
# https://github.com/tpoechtrager/cctools-port/pull/137#issuecomment-1710484561

# modify as desired
TARGET_ARCH="aarch64-linux-gnu"

GCC_VERSION=$(gcc -dumpversion)
SYSROOT_PATH="$(which gcc)/../$TARGET_ARCH"

CC="/usr/bin/clang"
CXX="/usr/bin/clang++"

FLAGS="-Qunused-arguments"
FLAGS+=" --target=$TARGET_ARCH"
FLAGS+=" --sysroot $SYSROOT_PATH/sysroot"
FLAGS+=" -isystem $SYSROOT_PATH/include/c++/$GCC_VERSION/"
FLAGS+=" -isystem $SYSROOT_PATH/include/c++/$GCC_VERSION/bits"
FLAGS+=" -isystem $SYSROOT_PATH/include/c++/$GCC_VERSION/debug"
FLAGS+=" -isystem $SYSROOT_PATH/include/c++/$GCC_VERSION/$TARGET_ARCH"

FLAGS+=" -Wl,--sysroot=$SYSROOT_PATH/sysroot -L$SYSROOT_PATH/sysroot/usr/lib"
FLAGS+=" -L $SYSROOT_PATH/../lib/gcc/$TARGET_ARCH/$GCC_VERSION"

# Check whether clang or clang++ is called
case $(basename "$1") in
	*clang)
		COMPILER="$CC"
		shift
		;;
	*clang++)
		COMPILER="$CXX"
		shift
		;;
	*)
		echo "Unknown compiler. Use clang or clang++."
		exit 1
		;;
esac

exec "$COMPILER" $FLAGS "$@"
