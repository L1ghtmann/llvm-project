#!/usr/bin/env bash

if [[ -z $1 ]]; then
    echo "Please pass build type (e.g., host, aarch64, etc) to $0."
    exit 1
fi

type=$1

if [[ $type != host ]]; then
    if [[ -x $(command -v apt) ]]; then
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
EOF

            sudo apt update || true
            sudo apt install -y libssl-dev:arm64
        fi
    elif [[ -x $(command -v pacman) ]]; then
        sudo pacman -Syu aarch64-linux-gnu-openssl
    elif [[ -x $(command -v dnf) ]]; then
        sudo dnf install openssl-libs.aarch64
        sudo dnf install openssl-devel.aarch64
    else
        echo "Sorry - distro unidentifiable."
        exit 1
    fi
fi

echo "[!] Build prep"

if [[ -x $(command -v apt) ]]; then
    # https://stackoverflow.com/a/44333806
    if ! dpkg -l tzdata > /dev/null; then
        sudo ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
        sudo DEBIAN_FRONTEND=noninteractive apt install -y tzdata
        sudo dpkg-reconfigure --frontend noninteractive tzdata
    fi

    sudo apt update || true
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
    if ! pacman -Qs tzdata > /dev/null; then
        sudo ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
        sudo pacman -Syu --noconfirm tzdata
    fi

    sudo pacman -Syu --noconfirm base-devel \
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
            $type-linux-gnu-g++ || exit 1
    fi
elif [[ -x $(command -v dnf) ]]; then
    if ! rpm -q tzdata > /dev/null; then
        sudo ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
        sudo dnf install -y tzdata
        sudo timedatectl set-timezone America/New_York
    fi

    sudo dnf update -y
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
        python3 || exit 1

    if [[ $type != host ]]; then
        sudo dnf install -y \
            gcc-$type-linux-gnu \
            g++-$type-linux-gnu || exit 1
    fi
fi
