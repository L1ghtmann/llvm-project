#!/usr/bin/env bash
## Cross-compiled toolchain
# REFS:
# https://github.com/ProcursusTeam/Procursus/tree/main/makefiles
# https://github.com/kabiroberai/darwin-tools-linux/blob/master/prepare-toolchain
# https://sonarsource.atlassian.net/browse/CPP-3285
# DEV:
# https://github.com/llvm/llvm-project/issues/45959
# https://github.com/ClangBuiltLinux/tc-build/issues/150
# https://twitter.com/noztol/status/1277354097788715009
# https://stackoverflow.com/questions/2725255/create-statically-linked-binary-that-uses-getaddrinfo
# https://github.com/tpoechtrager/cctools-port/pull/137#issuecomment-1710484561

if [[ -z $1 ]]; then
	echo "$0: please pass the target architecture as an argument (e.g., ./cc-toolchain.sh aarch64)"
	echo "$0: if you are not cross-compiling, please use host-toolchain.sh"
	exit 0
fi

echo "[!] Build prep"
# https://stackoverflow.com/a/44333806
if ! dpkg -l tzdata > /dev/null; then
	sudo ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
	sudo DEBIAN_FRONTEND=noninteractive apt install -y tzdata
	sudo dpkg-reconfigure --frontend noninteractive tzdata
fi

ARCH="$1"

sudo apt update || true
# this is very silly, but cctools-port
# treats the llvm-build ld as GNU
# and attempts to pass '-z', which
# apple's ld64 doesn't support
# so need GNU ld + clang for that
# also use for (lib)tapi build
sudo apt install -y build-essential \
	autoconf \
	automake \
	cmake \
	coreutils \
	clang \
	git \
	libssl-dev \
	libtool \
	make \
	ninja-build \
	pkg-config \
	python3 \
	gcc-$ARCH-linux-gnu \
	g++-$ARCH-linux-gnu || exit 1

# NOTE: change arch listed in section below depending on your target
# Unfortunately, dpkg arch is not always 1:1 with the standard name (e.g., aarch64 -> arm64)
sudo dpkg --add-architecture arm64

CODENAME="$(. /etc/os-release; echo ${VERSION_CODENAME/*, /})"

# need these as default --add-architecture links 404 :/
if [[ -z "$(cat /etc/apt/sources.list | grep arm64)" ]]; then
sudo tee -a /etc/apt/sources.list << EOF
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME main restricted
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates main restricted
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-backports main restricted universe multiverse
EOF

sudo apt update || true
sudo apt install -y libssl-dev:arm64 #libstdc++6:arm64
fi

PROC=$(nproc --all)
WDIR="$HOME/work"
LLVM="$PWD"

mkdir -pv $WDIR/{linux/iphone/,libplist/}

echo "[!] Prep build for release"
# build support tooling for host with support for targets
cmake -Wno-dev -B build-host -G "Ninja" \
	-DLLVM_ENABLE_PROJECTS=clang \
	-DLLVM_TARGETS_TO_BUILD="X86" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=Release \
	-S llvm
cmake --build build-host --target llvm-config llvm-tblgen clang-ast-dump clang-tblgen -- -j$PROC \
	|| { echo "[!] host LLVM build failure"; exit 1; }

# cross-compile llvm/clang for target plat with support for useful targets
cmake -Wno-dev -B build -G "Ninja" \
	-DCMAKE_SYSTEM_NAME="Linux" \
	-DCMAKE_SYSTEM_VERSION="12" \
	-DLLVM_TARGET_ARCH=$ARCH \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$ARCH-linux-gnu \
	-DLLVM_ENABLE_PROJECTS="clang" \
	-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
	-DLLVM_LINK_LLVM_DYLIB=ON \
	-DLLVM_ENABLE_LIBXML2=OFF \
	-DLLVM_ENABLE_ZLIB=OFF \
	-DLLVM_ENABLE_Z3_SOLVER=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DLLVM_NATIVE_TOOL_DIR="$PWD/build-host/bin/" \
	-DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_COMPILER="/usr/bin/$ARCH-linux-gnu-gcc" \
	-DCMAKE_CXX_COMPILER="/usr/bin/$ARCH-linux-gnu-g++" \
	-DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
	-S llvm
cmake --build build --target install -- -j$PROC \
	|| { echo "[!] LLVM build failure"; exit 1; }

# TODO
# echo "[!] Build compiler-rt"
# cross-compile compiler-rt for target plat with support for useful targets
# cmake -Wno-dev -B build-compiler-rt -G "Ninja" \
# 	-DCMAKE_SYSTEM_NAME="Linux" \
# 	-DCMAKE_SYSTEM_VERSION="12" \
# 	-DLLVM_TARGET_ARCH=$ARCH \
# 	-DLLVM_DEFAULT_TARGET_TRIPLE=$ARCH-linux-gnu \
# 	-DLLVM_ENABLE_PROJECTS="clang" \
# 	-DLLVM_ENABLE_RUNTIMES="compiler-rt" \
# 	-DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
#	-DLLVM_NATIVE_TOOL_DIR="$PWD/build-host/bin" \
# 	-DLLVM_INCLUDE_TESTS=OFF \
# 	-DCLANG_INCLUDE_TESTS=OFF \
# 	-DCOMPILER_RT_INCLUDE_TESTS=OFF \
# 	-DCOMPILER_RT_BUILD_CRT=OFF \
# 	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
# 	-DCOMPILER_RT_BUILD_PROFILE=OFF \
# 	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
# 	-DCOMPILER_RT_BUILD_XRAY=OFF \
# 	-DCOMPILER_RT_BUILD_BUILTINS=ON \
# 	-DBUILTINS_CMAKE_ARGS="-DCOMPILER_RT_ENABLE_IOS=ON -DCOMPILER_RT_ENABLE_WATCHOS=ON -DCOMPILER_RT_ENABLE_TVOS=ON" \
# 	-DCMAKE_BUILD_TYPE=MinSizeRel \
#	-DCMAKE_C_COMPILER="/usr/bin/$ARCH-linux-gnu-gcc" \
#	-DCMAKE_CXX_COMPILER="/usr/bin/$ARCH-linux-gnu-g++" \
# 	-DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
# 	-S llvm
# cmake --build build-compiler-rt --target install-compiler-rt -- -j$PROC \
#    || { echo "[!] compiler-rt build failure"; exit 1; }

cd $WDIR
echo "[!] Build libplist"
# doing this to get the static archive
git clone --depth=1 https://github.com/libimobiledevice/libplist lp
cd lp
./autogen.sh --prefix="$WDIR/libplist" \
			--without-cython \
			--enable-static \
			--disable-shared \
			--host=$ARCH-linux-gnu \
			CC=/usr/bin/$ARCH-linux-gnu-gcc \
			CXX=/usr/bin/$ARCH-linux-gnu-g++
make -j$PROC install \
	&& cp -av $WDIR/libplist/bin/plistutil $WDIR/linux/iphone/bin/; cd ../ \
	|| { echo "[!] libplist build failure"; exit 1; }

echo "[!] Build ldid"
git clone --depth=1 https://github.com/ProcursusTeam/ldid
cd ldid
make -j$PROC DESTDIR="$WDIR/linux/iphone/" \
			PREFIX="" \
			LIBCRYPTO_LIBS="-l:libcrypto.a -lpthread -ldl" \
			LIBPLIST_INCLUDES="-I$WDIR/libplist/include" \
			LIBPLIST_LIBS="$WDIR/libplist/lib/libplist-2.0.a" \
			CC=/usr/bin/$ARCH-linux-gnu-gcc \
			CXX=/usr/bin/$ARCH-linux-gnu-g++ \
			install \
				&& cd ../ \
				|| { echo "[!] ldid build failure"; exit 1; }

# clang cc config
TARGET_ARCH="$ARCH-linux-gnu"
GCC_VERSION=$(gcc -dumpversion)
SYSROOT_PATH="/usr/$TARGET_ARCH"

FLAGS="-Qunused-arguments"
FLAGS+=" --target=$TARGET_ARCH"
FLAGS+=" -I$SYSROOT_PATH/include/c++/$GCC_VERSION/$TARGET_ARCH"
FLAGS+=" -L$SYSROOT_PATH/lib -L/usr/lib/$TARGET_ARCH"
FLAGS+=" -L$SYSROOT_PATH/../lib/gcc-cross/$TARGET_ARCH/$GCC_VERSION"

echo "[!] Build tapi"
git clone --depth=1 https://github.com/tpoechtrager/apple-libtapi -b 1100.0.11
cd apple-libtapi
# build tapi-catered llvm/clang-tblgen for host with support for host and target
cmake -Wno-dev -B build-tblgens -G "Ninja" \
	-DLLVM_TARGETS_TO_BUILD="X86" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=Release \
	-S src/llvm
cmake --build build-tblgens --target llvm-tblgen clang-tblgen -- -j$PROC \
	|| { echo "[!] tapi tblgen build failure"; exit 1; }

# build tapi for target arch with support for useful targets
cmake -Wno-dev -B build -G "Ninja" \
	-DCMAKE_SYSTEM_NAME="Linux" \
	-DCMAKE_SYSTEM_VERSION="12" \
	-DLLVM_TARGET_ARCH=$ARCH \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$ARCH-linux-gnu \
	-DLLVM_ENABLE_PROJECTS="libtapi" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DTAPI_FULL_VERSION="$(cat $PWD/VERSION.txt | grep "tapi" | grep -o '[[:digit:]].*')" \
	-DLLVM_TABLEGEN="$PWD/build-tblgens/bin/llvm-tblgen" \
	-DCLANG_TABLEGEN="$PWD/build-tblgens/bin/clang-tblgen" \
	-DCLANG_TABLEGEN_EXE="$PWD/build-tblgens/bin/clang-tblgen" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_COMPILER="/usr/bin/clang" \
	-DCMAKE_CXX_COMPILER="/usr/bin/clang++" \
	-DCMAKE_C_FLAGS="$FLAGS" \
	-DCMAKE_CXX_FLAGS="-I$PWD/src/llvm/projects/clang/include/ -I$PWD/build/projects/clang/include/ $FLAGS" \
	-DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
	-S src/llvm
cmake --build build --target install-libtapi install-tapi-headers install-tapi -- -j$PROC \
	&& cd ../ \
	|| { echo "[!] (lib)tapi build failure"; exit 1; }

echo "[!] Build libdispatch"
git clone --depth=1 https://github.com/tpoechtrager/apple-libdispatch/ a-ld
cd a-ld
cmake -B build -G "Ninja" \
	-DCMAKE_C_COMPILER="/usr/bin/clang" \
	-DCMAKE_CXX_COMPILER="/usr/bin/clang++" \
	-DCMAKE_C_FLAGS="$FLAGS" \
	-DCMAKE_CXX_FLAGS="$FLAGS" \
	-DCMAKE_BUILD_TYPE=RELEASE \
	-DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
	.
cmake --build build --target install -- -j$PROC \
	&& cd ../ \
	|| { echo "[!] libdispatch build failure"; exit 1; }

echo "[!] Build cctools"
git clone --depth=1 https://github.com/tpoechtrager/cctools-port/
./cctools-port/cctools/configure --prefix="$WDIR/linux/iphone/" \
	--host=$ARCH-linux-gnu \
	--target=aarch64-apple-darwin14 \
	--enable-tapi-support \
	--with-libtapi="$WDIR/linux/iphone/" \
	--with-libdispatch="$WDIR/linux/iphone/" \
	--with-libblocksruntime="$WDIR/linux/iphone/" \
	--program-prefix="" \
	CC="/usr/bin/clang" \
	CXX="/usr/bin/clang++" \
	CFLAGS="$FLAGS" \
	CXXFLAGS="$FLAGS" \
	CXXABI_LIB="-l:libc++abi.a" \
	LDFLAGS="-Wl,-rpath,'\$\$ORIGIN/../lib' -Wl,-rpath,'\$\$ORIGIN/../lib64' -Wl,-z,origin" \
		|| { echo "[!] cctools-port configure failure"; cat config.log; exit 1; }
make -j$PROC install \
	&& cd $LLVM \
	|| { echo "[!] cctools-port build failure"; exit 1; }

echo "[!] Sanity check"
find $WDIR/linux/iphone/bin -type f -exec file {} \; > result
count="$(cat result | grep ELF | wc -l)"
num="$(cat result | grep $ARCH | wc -l)"
# check format of all bins
if [[ $num != $count ]]; then
	echo "[xx] Rip - have some non-$ARCH bins:"
	echo "$(cat result | grep ELF | grep -v $ARCH)"
	exit 1
fi

echo "[!] Prep build for release"
tar -cJvf $HOME/iOSToolchain.tar.xz -C $WDIR/ linux/iphone/ \
   && echo "[!!] Success!" \
   || echo "[xx] Failure!"
