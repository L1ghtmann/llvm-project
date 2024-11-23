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

sudo apt update || true
sudo apt install -y build-essential \
	autoconf \
	automake \
	cmake \
	coreutils \
	git \
	libssl-dev \
	libtool \
	make \
	ninja-build \
	pkg-config \
	python3 \
	gcc-$1-linux-gnu \
	g++-$1-linux-gnu || exit 1

sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/$1-linux-gnu-gcc 30
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/$1-linux-gnu-g++ 30
sudo update-alternatives --set cc /usr/bin/gcc
sudo update-alternatives --set c++ /usr/bin/g++

# NOTE: change arch listed in section below depending on your target
# Unfortunately, dpkg arch is not always 1:1 with the standard name (e.g., aarch64 -> arm64)
sudo dpkg --add-architecture arm64

CODENAME="$(. /etc/os-release; echo ${VERSION_CODENAME/*, /})"

# need these as default --add-architecture links 404 :/
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
sudo apt install -y libssl-dev:arm64

ARCH=$(uname -m)
PROC=$(nproc --all)
WDIR="$HOME/work"

mkdir -pv $WDIR/{linux/iphone/,libplist/}

echo "[!] Prep build for release"
# build clang & llvm/clang-tblgen for host with support for target
cmake -B build-host -G "Ninja" \
	-DCMAKE_C_COMPILER=/usr/bin/$ARCH-linux-gnu-gcc \
	-DCMAKE_CXX_COMPILER=/usr/bin/$ARCH-linux-gnu-g++ \
	-DLLVM_ENABLE_PROJECTS=clang \
	-DLLVM_TARGETS_TO_BUILD="X86" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=Release \
	-S llvm
cmake --build build-host --target llvm-tblgen clang-tblgen clang -- -j$PROC \
	|| (echo "[!] host LLVM build failure"; exit 1)

# cross-compile llvm/clang for target plat with support for useful targets
cmake -B build -G "Ninja" \
	-DCMAKE_CROSSCOMPILING=True \
	-DLLVM_TARGET_ARCH=$1 \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$1-linux-gnu \
	-DLLVM_ENABLE_PROJECTS="clang" \
	-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
	-DLLVM_LINK_LLVM_DYLIB=ON \
	-DLLVM_ENABLE_LIBXML2=OFF \
	-DLLVM_ENABLE_ZLIB=OFF \
	-DLLVM_ENABLE_Z3_SOLVER=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
	-DLLVM_TABLEGEN="$PWD/build-host/bin/llvm-tblgen" \
	-DCLANG_TABLEGEN="$PWD/build-host/bin/clang-tblgen" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
	-S llvm
cmake --build build --target install -- -j$PROC \
	|| (echo "[!] LLVM build failure"; exit 1)

# TODO
# echo "[!] Build compiler-rt"
# cross-compile compiler-rt for target plat with support for useful targets
# cmake -B build-compiler-rt -G "Ninja" \
#     -DCMAKE_CROSSCOMPILING=True \
#     -DLLVM_TARGET_ARCH=$1 \
#     -DLLVM_DEFAULT_TARGET_TRIPLE=$1-linux-gnu \
#     -DLLVM_ENABLE_PROJECTS="clang" \
#     -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
#     -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
#     -DLLVM_TABLEGEN="$PWD/build-host/bin/llvm-tblgen" \
#     -DCLANG_TABLEGEN="$PWD/build-host/bin/clang-tblgen" \
#     -DLLVM_INCLUDE_TESTS=OFF \
#     -DCLANG_INCLUDE_TESTS=OFF \
#     -DCOMPILER_RT_INCLUDE_TESTS=OFF \
#     -DCOMPILER_RT_BUILD_CRT=OFF \
#     -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
#     -DCOMPILER_RT_BUILD_PROFILE=OFF \
#     -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
#     -DCOMPILER_RT_BUILD_XRAY=OFF \
#     -DCOMPILER_RT_BUILD_BUILTINS=ON \
#     -DBUILTINS_CMAKE_ARGS="-DCOMPILER_RT_ENABLE_IOS=ON -DCOMPILER_RT_ENABLE_WATCHOS=ON -DCOMPILER_RT_ENABLE_TVOS=ON" \
#     -DCMAKE_BUILD_TYPE=MinSizeRel \
#     -DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
#     -S llvm
# cmake --build build-compiler-rt --target install-compiler-rt -- -j$PROC \
#    || (echo "[!] compiler-rt build failure"; exit 1)

cd $WDIR
echo "[!] Build libplist"
# doing this to get the static archive
git clone --depth=1 https://github.com/libimobiledevice/libplist lp
cd lp
./autogen.sh --prefix="$WDIR/libplist" --without-cython --enable-static --disable-shared --host=$1-linux-gnu
make -j$PROC install \
	&& cp -av $WDIR/libplist/bin/plistutil $WDIR/linux/iphone/bin/; cd ../ \
	|| (echo "[!] libplist build failure"; exit 1)

echo "[!] Build ldid"
git clone --depth=1 https://github.com/ProcursusTeam/ldid
cd ldid
make -j$PROC DESTDIR="$WDIR/linux/iphone/" \
	PREFIX="" \
	LIBCRYPTO_LIBS="-l:libcrypto.a -lpthread -ldl" \
	LIBPLIST_INCLUDES="-I$WDIR/libplist/include" \
	LIBPLIST_LIBS="$WDIR/libplist/lib/libplist-2.0.a" \
	install \
		&& cd ../ \
		|| (echo "[!] ldid build failure"; exit 1)

echo "[!] Build tapi"
git clone --depth=1 https://github.com/tpoechtrager/apple-libtapi -b 1100.0.11
cd apple-libtapi
# build tapi-catered llvm/clang-tblgen for host with support for host and target
cmake -B build-tblgens -G "Ninja" \
	-DCMAKE_C_COMPILER=/usr/bin/$ARCH-linux-gnu-gcc \
	-DCMAKE_CXX_COMPILER=/usr/bin/$ARCH-linux-gnu-g++ \
	-DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=Release \
	-S src/llvm
cmake --build build-tblgens --target llvm-tblgen clang-tblgen -- -j$PROC \
	|| (echo "[!] tapi tblgen build failure"; exit 1)

# build tapi for target arch with support for useful targets
cmake -B build -G "Ninja" \
	-DCMAKE_CROSSCOMPILING=True \
	-DLLVM_TARGET_ARCH=$1 \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$1-linux-gnu \
	-DLLVM_ENABLE_PROJECTS="libtapi" \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DTAPI_FULL_VERSION="$(cat $PWD/VERSION.txt | grep "tapi" | grep -o '[[:digit:]].*')" \
	-DLLVM_TABLEGEN="$PWD/build-tblgens/bin/llvm-tblgen" \
	-DCLANG_TABLEGEN="$PWD/build-tblgens/bin/clang-tblgen" \
	-DCLANG_TABLEGEN_EXE="$PWD/build-tblgens/bin/clang-tblgen" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_CXX_FLAGS="-I$PWD/src/llvm/projects/clang/include/ -I$PWD/build/projects/clang/include/" \
	-DCMAKE_INSTALL_PREFIX="$WDIR/linux/iphone/" \
	-S src/llvm
cmake --build build --target install-libtapi install-tapi-headers install-tapi -- -j$PROC \
	|| (echo "[!] (lib)tapi build failure"; exit 1)

echo "[!] Build cctools"
git clone --depth=1 https://github.com/tpoechtrager/cctools-port/ -b 986-ld64-711
./cctools-port/cctools/configure --prefix="$WDIR/linux/iphone/" \
	--build=$ARCH-linux-gnu \
	--host=$1-linux-gnu \
	--target=aarch64-apple-darwin14 \
	--enable-tapi-support \
	--with-libtapi="$WDIR/linux/iphone/" \
	--program-prefix="" \
	CC="$HOME/cc.sh" \
	CXX="$HOME/cc.sh" \
	CXXABI_LIB="-l:libc++abi.a" \
	LDFLAGS="-Wl,-rpath,'\$\$ORIGIN/../lib' -Wl,-z,origin" \
		|| (echo "[!] cctools-port configure failure"; cat config.log; exit 1)
make -j$PROC install \
	|| (echo "[!] cctools-port build failure"; exit 1)

echo "[!] Prep build for release"
tar -cJvf $HOME/iOSToolchain.tar.xz -C $WDIR/ linux/iphone/ \
   && echo "[!!] Success!" \
   || echo "[xx] Failure!"
