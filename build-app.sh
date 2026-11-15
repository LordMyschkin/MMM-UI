#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
cd "$root"
export CLANG_MODULE_CACHE_PATH="$root/.build/clang-cache"
export XDG_CACHE_HOME="$root/.build/cache"

swift build -c release --product s-mpc
binary="$(swift build -c release --show-bin-path)/s-mpc"
app="$root/dist/MMM-UI.app"
old_app="$root/dist/s-mpc.app"
if pgrep -f "$app/Contents/MacOS/s-mpc" >/dev/null 2>&1 ||
   pgrep -f "$old_app/Contents/MacOS/s-mpc" >/dev/null 2>&1; then
    echo "Close $app before rebuilding it." >&2
    exit 1
fi
if [ -d "$old_app" ] && [ ! -e "$app" ]; then
    mv "$old_app" "$app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/s-mpc"

icon="$root/Resources/MMM-UI.icns"
if [ ! -f "$icon" ]; then
    swift "$root/Tools/make-icon.swift" "$root" "$icon"
fi
cp "$icon" "$app/Contents/Resources/MMM-UI.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MMM-UI</string>
  <key>CFBundleDisplayName</key><string>MMM-UI</string>
  <key>CFBundleIdentifier</key><string>org.lordmyschkin.smpc</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>s-mpc</string>
  <key>CFBundleIconFile</key><string>MMM-UI.icns</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built: $app"
