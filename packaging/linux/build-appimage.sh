#!/usr/bin/env bash
# Build Wordloom-x86_64.AppImage from a release build.
#
# Needs: Qt 6 with qmake on PATH (or QMAKE set), plus linuxdeploy and
# linuxdeploy-plugin-qt (downloaded into ./.appimage-tools if missing).
# Run from the repository root:  packaging/linux/build-appimage.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
tools="$root/.appimage-tools"
appdir="$root/target/AppDir"
here="$root/packaging/linux"

mkdir -p "$tools"
fetch() {
    [ -x "$tools/$1" ] && return
    curl -fsSL -o "$tools/$1" "$2"
    chmod +x "$tools/$1"
}
fetch linuxdeploy-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-qt-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage

cargo build --release -p wordloom

rm -rf "$appdir"
install -Dm644 "$here/io.github.generalkael.Wordloom.metainfo.xml" \
    "$appdir/usr/share/metainfo/io.github.generalkael.Wordloom.metainfo.xml"

# The Qt plugin finds QML imports (Controls, Dialogs, Layouts, Shapes, Pdf…)
# by scanning our QML sources.
export QML_SOURCES_PATHS="$root/crates/wordloom-app/qml"
export QMAKE="${QMAKE:-$(command -v qmake6 || command -v qmake)}"
# Platforms besides the default xcb: offscreen (headless runs and the CI
# smoke test) and Wayland when this Qt has it.
platforms="libqoffscreen.so"
if [ -f "$("$QMAKE" -query QT_INSTALL_PLUGINS)/platforms/libqwayland-generic.so" ]; then
    platforms="$platforms;libqwayland-generic.so"
fi
export EXTRA_PLATFORM_PLUGINS="$platforms"
# SVG images (the sample map, imported .svg research files).
export EXTRA_QT_MODULES="svg"
export PATH="$tools:$PATH"
# linuxdeploy is itself an AppImage; this lets it run without FUSE (e.g. in CI).
export APPIMAGE_EXTRACT_AND_RUN=1
export OUTPUT="Wordloom-x86_64.AppImage"

"$tools/linuxdeploy-x86_64.AppImage" \
    --appdir "$appdir" \
    --executable target/release/wordloom \
    --desktop-file "$here/wordloom.desktop" \
    --icon-file "$here/wordloom.svg" \
    --plugin qt \
    --output appimage

echo "Built $root/$OUTPUT"
