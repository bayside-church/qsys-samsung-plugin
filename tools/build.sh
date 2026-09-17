#!/bin/sh
# Build the plugin and install it into Designer's user plugin folder.
# Usage: tools/build.sh [ver_dev|ver_fix|ver_min|ver_maj|ver_none]   (default ver_dev)
# Designer only reloads a plugin whose version changed, so bump by default.
set -e
cd "$(dirname "$0")/.."
sh ./plugincompile/compile_plugin.sh "${1:-ver_dev}" >/dev/null
./plugincompile/PLUGCC.exe qsys-samsung-plugin "$(cygpath -w "$PWD")\plugin.lua" | grep -iE "error|not found" && exit 1
dest="$USERPROFILE/Documents/QSC/Q-Sys Designer/Plugins/qsys-samsung-plugin"
mkdir -p "$dest"
cp qsys-samsung-plugin.qplug "$dest/"
echo "built and installed $(grep -o 'BuildVersion = "[^"]*"' info.lua)"
