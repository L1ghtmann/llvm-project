#!/usr/bin/env bash

if [[ -z $1 ]]; then
    echo "Please pass build type (e.g., host, aarch64, etc) to $0."
    exit 1
fi

type=$1

echo "[!] Build prep"

if [[ -x $(command -v apt) ]]; then
    apt update
    apt install -y sudo

    # https://stackoverflow.com/a/44333806
    if ! dpkg -l tzdata > /dev/null; then
        sudo ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
        sudo DEBIAN_FRONTEND=noninteractive apt install -y tzdata
        sudo dpkg-reconfigure --frontend noninteractive tzdata
    fi

    # this is very silly, but cctools-port
    # treats the llvm-build ld as GNU
    # and attempts to pass '-z', which
    # apple's ld64 doesn't support
    # so need GNU ld + clang for that
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
        python3 || exit 1

    if [[ $type != host ]]; then
        sudo apt install -y \
            gcc-$type-linux-gnu \
            g++-$type-linux-gnu || exit 1
    fi
elif [[ -x $(command -v pacman) ]]; then
    pacman -Syu sudo
    sudo pacman -Syy --noconfirm --needed base-devel \
        autoconf \
        automake \
        cmake \
        coreutils \
        clang \
        git \
        openssl \
        libtool \
        make \
        ninja \
        pkg-config \
        python3 || exit 1

    if [[ $type != host ]]; then
        sudo pacman -Syy --noconfirm \
        $type-linux-gnu-gcc \
        lib32-glibc || exit 1 #gnu/stubs-32.h
    fi
elif [[ -x $(command -v dnf) ]]; then
    dnf update -y
    dnf install -y sudo
    sudo dnf install -y @development-tools \
        autoconf \
        automake \
        cmake \
        coreutils \
        clang \
        git \
        openssl-devel \
        libtool \
        make \
        ninja-build \
        pkgconfig \
        python3 \
        which || exit 1

    if [[ $type != host ]]; then
        # modify as needed
        sudo dnf install -y dnf-plugins-core || exit 1
        dnf copr enable lantw44/aarch64-linux-gnu-toolchain || exit 1
        sudo dnf install -y \
            gcc-$type-linux-gnu \
            gcc-c++-$type-linux-gnu \
            $type-linux-gnu-glibc || exit 1
    fi
fi

# if [[ $type != host ]]; then
#     if [[ -x $(command -v apt) ]]; then
#         apt update
#         apt install -y sudo
#         # NOTE: change arch listed in section below depending on your target
#         # Unfortunately, dpkg arch is not always 1:1 with the standard name (e.g., aarch64 -> arm64)
#         sudo dpkg --add-architecture arm64

#         CODENAME="$(. /etc/os-release; echo ${VERSION_CODENAME/*, /})"

#         # need these as default --add-architecture links 404 :/
#         if [[ -z "$(cat /etc/apt/sources.list | grep arm64)" ]]; then
# sudo tee -a /etc/apt/sources.list << EOF
#     deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME main restricted
#     deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates main restricted
#     deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME universe
#     deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates universe
# EOF

#             sudo apt update || true
#             sudo apt install -y libssl-dev:arm64
#         fi
#     fi
# fi

# Build libcrypto.a (3.3) + install headers
if [[ $type == host && -z "$(find /usr/ -name libcrypto.a)" ]] || \
   [[ $type != host && -z "$(find /usr/lib/$type-linux-gnu/ -name libcrypto.a)" ]]; then
    # allow static libs on Arch
    sed -i 's/!staticlibs/staticlibs/g' /etc/makepkg.conf &> /dev/null || true
    # fix perl's bin not being in $PATH on Arch
    source /etc/profile &> /dev/null || true
    # fix perl's bin not being in $PATH on Fedora
    source /etc/bashrc &> /dev/null || true
    git clone --depth=1 https://github.com/openssl/openssl -b openssl-3.3
    cd openssl
    if [[ $type == host ]]; then
        ./config && make -j$(nproc --all) install_sw || exit 1 #build_libs
    else
        ./config && CC="$type-linux-gnu-gcc" CXX="$type-linux-gnu-g++" make -j$(nproc --all) install_sw || exit 1 #build_libs
    fi
    # mkdir -p /usr/local/lib
    # cp -v libcrypto.a /usr/local/lib || exit 1
    cd ../ && rm -rf openssl
else
    echo "libcrypto.a exists. Skipping..."
fi
