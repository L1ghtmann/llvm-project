set(LLVM_LINK_COMPONENTS
  Support
  )

add_clang_unittest(BasicTests
  CharInfoTest.cpp
  DarwinSDKInfoTest.cpp
  DiagnosticTest.cpp
  FileEntryTest.cpp
  FileManagerTest.cpp
  LineOffsetMappingTest.cpp
  SanitizersTest.cpp
  SarifTest.cpp
  SourceManagerTest.cpp
  )

clang_target_link_libraries(BasicTests
  PRIVATE
  clangBasic
  clangLex
  )

target_link_libraries(BasicTests
  PRIVATE
  LLVMCAS
  LLVMTestingSupport
)
