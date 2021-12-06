#!/bin/sh

## Derived from https://github.com/renard/emacs-build-macosx
## Patches from https://github.com/d12frosted/homebrew-emacs-plus
## See also https://github.com/jimeh/build-emacs-for-macos

# ======================================================
# Exit on non-zero status
# See https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# ======================================================
set -e

# ======================================================
# Set Variables
# ======================================================

ROOT_DIR="`pwd`"
BUILD_DIR=/tmp/emacs-build
SRC_DIR=emacs-git
GIT_VERSION=setup-emacs-git-version.el
SETUP=~/.emacs.d/setup-config

# ======================================================
# Use Homebrew libxml
# ======================================================

export LDFLAGS="-L/opt/homebrew/opt/libxml2/lib"
export CPPFLAGS="-I/opt/homebrew/opt/libxml2/include"

# ======================================================
# Start with a clean build
# ======================================================

rm -rf ${BUILD_DIR}
mkdir ${BUILD_DIR}

cd ${SRC_DIR}

# ======================================================
# Input for version otherwise default to master
# ======================================================

if test -n "$1"; then
    commit="$1"
else
    commit="origin/master"
    git checkout master
    git pull
fi

git archive --format tar $commit | tar -C ${BUILD_DIR} -xvf -

# ======================================================
# Set variables for git, time, & patches
# ======================================================

REV=`git log -n 1 --no-color --pretty='format:%h' ${commit}`
TIMESTAMP=`git log -n 1 --no-color --pretty='format:%at' ${commit}`
PATCH_LIST=`find ${ROOT_DIR}/patches/ -name '*.patch'`
cd ${BUILD_DIR}

echo "
# ======================================================
# Record Git SHA
# ======================================================
"

# This records the Git SHA to an elisp file and
# moves it to your preferred elisp setup dir

cp ${ROOT_DIR}/materials/${GIT_VERSION} ${BUILD_DIR}/
sed -e "s/@@GIT_COMMIT@@/$REV/" -i '' ${BUILD_DIR}/${GIT_VERSION}
mv -f ${BUILD_DIR}/${GIT_VERSION} ${SETUP}/${GIT_VERSION}

echo "DONE!"

echo "
# ======================================================
# Apply Patches
# ======================================================
"
# Note that this applies all patches in 'patches' dir
for f in ${PATCH_LIST}; do
    echo "Applying patch `basename $f`"
    patch -p1 -i $f
done

# ======================================================
# Info settings
# ======================================================

# Here we set infofiles and variables for versioning

STRINGS="
  nextstep/templates/Emacs.desktop.in
  nextstep/templates/Info-gnustep.plist.in
  nextstep/templates/Info.plist.in
  nextstep/templates/InfoPlist.strings.in"

DAY=`date -u -r $TIMESTAMP +"%Y-%m-%d_%H-%M-%S"`
ORIG=`grep ^AC_INIT configure.ac`
VNUM=`echo $ORIG | sed 's#^AC_INIT(\(.*\))#\1#; s/ //g' | cut -f2 -d,`
VERS="$DAY Git $REV"
DESCR="Emacs_Cocoa_${VNUM}_${DAY}_Git_${REV}"

echo "
# ======================================================
# Autogen/copy_autogen
# ======================================================
"

# Generate config files
./autogen.sh

# ======================================================
# Use Homebrew libxml pkgconfig
# ======================================================

export PKG_CONFIG_PATH="/opt/homebrew/opt/libxml2/lib/pkgconfig"

# ======================================================
# Set Compile Flags
# ======================================================

# Use Clang for slightly faster builds
# See https://leeifrankjaw.github.io/articles/clang_vs_gcc_for_emacs.html
# See https://alibabatech.medium.com/gcc-vs-clang-llvm-an-in-depth-comparison-of-c-c-compilers-899ede2be378

CFLAGS="-g -O2"
export CC=clang
export OBJC=clang

# ======================================================
# Inscribe Version in Info files
# ======================================================

for f in $STRINGS; do
    sed -e "s/@version@/@version@ $VERS/" -i '' $f
done

echo "
# ======================================================
# Configure emacs
# ======================================================
"

# Here we set config options for emacs
# For more info see config-options.txt

./configure \
    --with-ns \
    --with-native-compilation \
    --with-xwidgets \
    --with-mailutils \
    --with-json \
    --without-dbus \

echo "
# ======================================================
# Build and install everything
# ======================================================
"

## Check number of processors & use as many as we can!
NCPU=$(getconf _NPROCESSORS_ONLN)

## Send output to log file using tee
## See https://stackoverflow.com/a/60432203/6277148
make bootstrap -j$NCPU | tee bootstrap-log.txt || exit 1 && make install -j$NCPU | tee build-log.txt

echo "DONE!"

echo "
# ======================================================
# Delete old app & Move new app
# ======================================================
"
# close any emacs sessions
pkill -i emacs
# trash old emacs
trash /Applications/Emacs.app
# move build to applications folder
mv ${BUILD_DIR}/nextstep/Emacs.app /Applications

echo "DONE!"

echo "
# ======================================================
# Change icon
# ======================================================
"

# Copy new icon to emacs (currently using a big sur icon)
# See https://github.com/d12frosted/homebrew-emacs-plus/issues/419
cp ${ROOT_DIR}/materials/emacs-big-sur.icns /Applications/Emacs.app/Contents/Resources/Emacs.icns

echo "DONE!"

echo "
# ======================================================
# Copy C Source Code
# ======================================================
"

# Copy C source files to Emacs
cp -r ${ROOT_DIR}/${SRC_DIR}/src /Applications/Emacs.app/Contents/Resources/

echo "DONE!"

echo "
# ======================================================
# Cleanup
# ======================================================
"

# Make a directory for the build's log files and move them there
mkdir ${ROOT_DIR}/build-logs/${DESCR}
mv ${BUILD_DIR}/config.log ${ROOT_DIR}/build-logs/${DESCR}/${DESCR}-config.log
mv ${BUILD_DIR}/build-log.txt ${ROOT_DIR}/build-logs/${DESCR}/${DESCR}-build-log.txt
mv ${BUILD_DIR}/bootstrap-log.txt ${ROOT_DIR}/build-logs/${DESCR}/${DESCR}-bootstrap-log.txt

# Delete build dir

rm -rf ${BUILD_DIR}

echo "DONE!"

echo "
# ======================================================
# Open new emacs
# ======================================================
"

open /Applications/Emacs.app

echo "DONE!"
