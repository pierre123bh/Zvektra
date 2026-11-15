cmake_minimum_required(VERSION 3.22.1)
project(zvektra_whisper LANGUAGES C CXX)

include(FetchContent)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_KLEIDIAI OFF CACHE BOOL "" FORCE)
FetchContent_Declare(whisper_cpp
    URL https://github.com/ggml-org/whisper.cpp/archive/a8d002cfd879315632a579e73f0148d06959de36.tar.gz)
FetchContent_MakeAvailable(whisper_cpp)

add_library(zvektra_whisper SHARED whisper_jni.cpp)
target_compile_features(zvektra_whisper PRIVATE cxx_std_17)
target_link_libraries(zvektra_whisper PRIVATE whisper android log)
