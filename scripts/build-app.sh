#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Claudeer"
BUNDLE_ID="com.jhseo.claudeer"
PLIST_PATH=".claude-plugin/plugin.json"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"

VERSION=$(/usr/bin/python3 -c "import json; print(json.load(open('${PLIST_PATH}'))['version'])")

echo "==> Building release binary"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
EXEC_PATH="${BIN_PATH}/${APP_NAME}"

if [ ! -f "${EXEC_PATH}" ]; then
    echo "ERROR: executable not found at ${EXEC_PATH}" >&2
    exit 1
fi

echo "==> Creating ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"

echo "==> Copying binary"
cp "${EXEC_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo "==> Writing Info.plist"
cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo ""
echo "Built: ${APP_DIR}"
echo ""
echo "Run:    open ${APP_DIR}"
echo "Install: cp -R ${APP_DIR} /Applications/"
