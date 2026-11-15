cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(RUNNER_RESOURCE "Runner.rc")
if("$ENV{RYADOM_BUILD}" STREQUAL "1")
  get_filename_component(RYADOM_PRODUCT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
  configure_file("${RYADOM_PRODUCT_ROOT}/ryadom/windows/Runner.rc.in"
    "${CMAKE_CURRENT_BINARY_DIR}/Ryadom.rc" @ONLY)
  set(RUNNER_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/Ryadom.rc")
  if(DEFINED ENV{RYADOM_SIGNING_VERSION})
    set(RYADOM_SIGNING_VERSION "$ENV{RYADOM_SIGNING_VERSION}")
    string(REPLACE "." "," RYADOM_SIGNING_VERSION_COMMAS "${RYADOM_SIGNING_VERSION}")
    configure_file("${RYADOM_PRODUCT_ROOT}/ryadom/signing/Runner.rc.in"
      "${CMAKE_CURRENT_BINARY_DIR}/RyadomSigning.rc" @ONLY)
    set(RUNNER_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/RyadomSigning.rc")
  endif()
endif()

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_desktop.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "${RUNNER_RESOURCE}"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
