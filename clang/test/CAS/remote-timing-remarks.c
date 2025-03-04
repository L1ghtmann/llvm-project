// REQUIRES: remote-cache-service

// Need a short path for the unix domain socket (and unique for this test file).
// RUN: rm -f %{remote-cache-dir}/%basename_t
// RUN: rm -rf %t && mkdir -p %t

// RUN: llvm-remote-cache-test -socket-path=%{remote-cache-dir}/%basename_t -cache-path=%t/cache -- \
// RUN: env LLVM_CACHE_CAS_PATH=%t/cas %clang-cache \
// RUN:   %clang -target x86_64-apple-macos11 -c %s -o %t/t.o -Rcompile-job-cache -Rcompile-job-cache-timing 2>&1 | FileCheck %s --check-prefix=CACHE-MISS
// RUN: llvm-remote-cache-test -socket-path=%{remote-cache-dir}/%basename_t -cache-path=%t/cache -- \
// RUN: env LLVM_CACHE_CAS_PATH=%t/cas %clang-cache \
// RUN:   %clang -target x86_64-apple-macos11 -c %s -o %t/t.o -Rcompile-job-cache -Rcompile-job-cache-timing 2>&1 | FileCheck %s --check-prefix=CACHE-HIT

// CACHE-MISS: remark: compile job dependency scanning time:
// CACHE-MISS: remark: compile job cache backend key query time:
// CACHE-MISS: remark: compile job cache miss
// CACHE-MISS: remark: compile job cache backend store artifacts time:
// CACHE-MISS: remark: compile job cache backend key update time:

// CACHE-HIT: remark: compile job dependency scanning time:
// CACHE-HIT: remark: compile job cache backend key query time:
// CACHE-HIT: remark: compile job cache hit
// CACHE-HIT: remark: compile job cache backend load artifacts time:
