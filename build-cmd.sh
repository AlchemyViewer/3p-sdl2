#!/usr/bin/env bash

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about undefined vars
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

TOP="$(dirname "$0")"

SDL_SOURCE_DIR="SDL2"
SDL_VERSION="2.30.0" # $(sed -n -e 's/^Version: //p' "$TOP/$SDL_SOURCE_DIR/SDL2.spec")

stage="$(pwd)"

# load autbuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/{debug,release}/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}

pushd "$TOP/$SDL_SOURCE_DIR"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        load_vsvars

        mkdir -p "$stage/include/SDL2"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"

        mkdir -p "build"
        pushd "build"
            cmake .. -G "Ninja Multi-Config" -DCMAKE_INSTALL_PREFIX=$(cygpath -m $stage)/release -DBUILD_SHARED_LIBS=ON
        
            cmake --build . --config Debug
            cmake --build . --config Release

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Debug
                ctest -C Release
            fi
    
            cp Debug/*.dll $stage/lib/debug/
            cp Debug/*.lib $stage/lib/debug/
            cp Release/*.dll $stage/lib/release/
            cp Release/*.lib $stage/lib/release/
            cp include/SDL2/*.h $stage/include/SDL2/
        popd
    ;;
    darwin*)
        export MACOSX_DEPLOYMENT_TARGET=11.0

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
        DEBUG_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names"
        RELEASE_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names"

        mkdir -p "$stage/include/SDL2"
        mkdir -p "$stage/lib/release"

        PREFIX_RELEASE="$stage/temp_release"
        mkdir -p $PREFIX_RELEASE

        mkdir -p "build"
        pushd "build"
            CFLAGS="$RELEASE_CFLAGS" \
            CXXFLAGS="$RELEASE_CXXFLAGS" \
            CPPFLAGS="$RELEASE_CPPFLAGS" \
            LDFLAGS="$RELEASE_LDFLAGS" \
            cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$PREFIX_RELEASE

            cmake --build . --config Release
            cmake --install . --config Release
        popd

        cp -a $PREFIX_RELEASE/include/SDL2/*.* $stage/include/SDL2

        cp -a $PREFIX_RELEASE/lib/*.dylib* $stage/lib/release
        cp -a $PREFIX_RELEASE/lib/libSDL2main.a $stage/lib/release

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

        mkdir -p "$stage/include/SDL2"
        mkdir -p "$stage/lib/debug"
        mkdir -p "$stage/lib/release"

        PREFIX_DEBUG="$stage/temp_debug"
        PREFIX_RELEASE="$stage/temp_release"

        mkdir -p $PREFIX_DEBUG
        mkdir -p $PREFIX_RELEASE

        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi
        
        mkdir -p "build"
        pushd "build"
            CFLAGS="$RELEASE_CFLAGS" \
            CXXFLAGS="$RELEASE_CXXFLAGS" \
            CPPFLAGS="$RELEASE_CPPFLAGS" \
            cmake .. -GNinja -DCMAKE_BUILD_TYPE="Release" \
                -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                -DCMAKE_INSTALL_PREFIX=$PREFIX_RELEASE

            cmake --build . --config Release
            cmake --install . --config Release
        popd

        cp -a $PREFIX_RELEASE/include/SDL2/*.* $stage/include/SDL2

        cp -a $PREFIX_DEBUG/lib/*.so* $stage/lib/debug
        cp -a $PREFIX_DEBUG/lib/libSDL2maind.a $stage/lib/debug

        cp -a $PREFIX_RELEASE/lib/*.so* $stage/lib/release
        cp -a $PREFIX_RELEASE/lib/libSDL2main.a $stage/lib/release
    ;;
    
    *)
        exit -1
    ;;
esac
popd


mkdir -p "$stage/LICENSES"
cp "$TOP/$SDL_SOURCE_DIR/LICENSE.txt" "$stage/LICENSES/SDL2.txt"
echo "$SDL_VERSION" > "$stage/VERSION.txt"
