#!/bin/bash

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

TOP="$(dirname "$0")"

SDL_SOURCE_DIR="SDL2"
SDL_VERSION=$(sed -n -e 's/^Version: //p' "$TOP/$SDL_SOURCE_DIR/SDL2.spec")

if [ -z "$AUTOBUILD" ] ; then
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

stage="$(pwd)"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/{debug,release}/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}

case "$AUTOBUILD_PLATFORM" in
    darwin*)
        # Setup osx sdk platform
        SDKNAME="macosx10.15"
        export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
        export MACOSX_DEPLOYMENT_TARGET=10.13

        # Setup build flags
        ARCH_FLAGS="-arch x86_64"
        SDK_FLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
        DEBUG_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Og -g -msse4.2 -fPIC -DPIC"
        RELEASE_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -O3 -flto -g -msse4.2 -fPIC -DPIC -fstack-protector-strong"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"
        DEBUG_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names -Wl,-macos_version_min,$MACOSX_DEPLOYMENT_TARGET"
        RELEASE_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names -Wl,-macos_version_min,$MACOSX_DEPLOYMENT_TARGET"

        mkdir -p "$stage/include/SDL2"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"

        PREFIX_DEBUG="$stage/temp_debug"
        PREFIX_RELEASE="$stage/temp_release"

        mkdir -p $PREFIX_DEBUG
        mkdir -p $PREFIX_RELEASE

        pushd "$TOP/$SDL_SOURCE_DIR"

        mkdir -p "build_debug"
        pushd "build_debug"
            CFLAGS="$DEBUG_CFLAGS" \
            CXXFLAGS="$DEBUG_CXXFLAGS" \
            CPPFLAGS="$DEBUG_CPPFLAGS" \
            LDFLAGS="$DEBUG_LDFLAGS" \
            cmake .. -GXcode -DCMAKE_BUILD_TYPE="Debug" \
                -DCMAKE_C_FLAGS="$DEBUG_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$DEBUG_CXXFLAGS" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                -DCMAKE_MACOSX_RPATH=YES -DCMAKE_INSTALL_PREFIX=$PREFIX_DEBUG

            cmake --build . --config Debug
            cmake --build . --config Debug --target install

            cp -a Debug/*.dSYM $stage/lib/debug
        popd

        mkdir -p "build_release"
        pushd "build_release"
            CFLAGS="$RELEASE_CFLAGS" \
            CXXFLAGS="$RELEASE_CXXFLAGS" \
            CPPFLAGS="$RELEASE_CPPFLAGS" \
            LDFLAGS="$RELEASE_LDFLAGS" \
            cmake .. -GXcode -DCMAKE_BUILD_TYPE="Release" \
                -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL=3 \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                -DCMAKE_MACOSX_RPATH=YES -DCMAKE_INSTALL_PREFIX=$PREFIX_RELEASE

            cmake --build . --config Release
            cmake --build . --config Release --target install

            cp -a Release/*.dSYM $stage/lib/release
        popd

        popd

        cp -a $PREFIX_RELEASE/include/SDL2/*.* $stage/include/SDL2

        cp -a $PREFIX_DEBUG/lib/*.dylib* $stage/lib/debug
        cp -a $PREFIX_DEBUG/lib/libSDL2maind.a $stage/lib/debug

        cp -a $PREFIX_RELEASE/lib/*.dylib* $stage/lib/release
        cp -a $PREFIX_RELEASE/lib/libSDL2main.a $stage/lib/release

        pushd "${stage}/lib/debug"
            fix_dylib_id "libSDL2d.dylib"
            strip -x -S libSDL2d.dylib
        popd

        pushd "${stage}/lib/release"
            fix_dylib_id "libSDL2.dylib"
            strip -x -S libSDL2.dylib
        popd
        ;;
    linux*)
        # Linux build environment at Linden comes pre-polluted with stuff that can
        # seriously damage 3rd-party builds.  Environmental garbage you can expect
        # includes:
        #
        #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
        #    DISTCC_LOCATION            top            branch      CC
        #    DISTCC_HOSTS               build_name     suffix      CXX
        #    LSDISTCC_ARGS              repo           prefix      CFLAGS
        #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
        #
        # So, clear out bits that shouldn't affect our configure-directed build
        # but which do nonetheless.
        #
        unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS
        
        # Default target per autobuild build --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
        DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
        RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"

        JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
        
        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi
        
        # Force static linkage to libz by moving .sos out of the way
        # (Libz is only packaging statics right now but keep this working.)
        trap restore_sos EXIT
        for solib in "${stage}"/packages/lib/{debug,release}/libz.so*; do
            if [ -f "$solib" ]; then
                mv -f "$solib" "$solib".disable
            fi
        done
        
        pushd "$TOP/$SDL_SOURCE_DIR"
        ./autogen.sh

        # do debug build of sdl
        PATH="$stage"/bin/:"$PATH" \
        CFLAGS="$DEBUG_CFLAGS" \
        CXXFLAGS="$DEBUG_CXXFLAGS" \
        CPPFLAGS="$DEBUG_CPPFLAGS" \
        LDFLAGS="$opts" \
        ./configure --with-pic \
        --prefix="$stage" --libdir="$stage/lib/debug" --includedir="$stage/include"
        make -j$JOBS
        make install
        
        # clean the build tree
        make distclean
        
        # do release build of sdl
        PATH="$stage"/bin/:"$PATH" \
        CFLAGS="$RELEASE_CFLAGS" \
        CXXFLAGS="$RELEASE_CXXFLAGS" \
        CPPFLAGS="$RELEASE_CPPFLAGS" \
        LDFLAGS="$opts" \
        ./configure --with-pic \
        --prefix="$stage" --libdir="$stage/lib/release" --includedir="$stage/include"
        make -j$JOBS
        make install
        
        # clean the build tree
        make distclean
        popd
    ;;
    
    *)
        exit -1
    ;;
esac


mkdir -p "$stage/LICENSES"
cp "$TOP/$SDL_SOURCE_DIR/COPYING.txt" "$stage/LICENSES/SDL2.txt"
echo "$SDL_VERSION" > "$stage/VERSION.txt"