set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSROOT "$ENV{HOME}/ubuntu20.04-rootfs")

set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)

set(CMAKE_C_FLAGS "--sysroot=${CMAKE_SYSROOT} -isystem ${CMAKE_SYSROOT}/usr/include")
set(CMAKE_CXX_FLAGS "${CMAKE_C_FLAGS}")

set(CMAKE_EXE_LINKER_FLAGS "--sysroot=${CMAKE_SYSROOT} \
  -L${CMAKE_SYSROOT}/lib/x86_64-linux-gnu \
  -L${CMAKE_SYSROOT}/usr/lib/x86_64-linux-gnu \
  -Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2")
