cmake_minimum_required(VERSION 3.25)
project(MacRDPDependencyProbe LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(FREERDP REQUIRED IMPORTED_TARGET freerdp3>=3.32.2)
pkg_check_modules(FREERDP_CLIENT REQUIRED IMPORTED_TARGET freerdp-client3)
pkg_check_modules(WINPR REQUIRED IMPORTED_TARGET winpr3)
pkg_check_modules(SDL3 REQUIRED IMPORTED_TARGET sdl3>=3.4.18)

if(FREERDP_VERSION VERSION_GREATER_EQUAL 4)
    message(FATAL_ERROR "Review the bridge requirements before moving to FreeRDP 4")
endif()

add_executable(macrdp-dependency-probe Prototypes/dependency_probe.c)
target_compile_features(macrdp-dependency-probe PRIVATE c_std_11)
target_compile_options(macrdp-dependency-probe PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(macrdp-dependency-probe PRIVATE
    PkgConfig::FREERDP PkgConfig::FREERDP_CLIENT PkgConfig::WINPR PkgConfig::SDL3)
