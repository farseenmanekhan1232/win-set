#!/bin/bash
set -e

# Build configuration
APP_NAME="WinSet"
BUNDLE_ID="com.winset.app"
VERSION="${1:-1.0.0}"

echo "🔨 Building WinSet v$VERSION..."

# Clean and build release
swift build -c release --arch arm64 --arch x86_64

# Create app bundle structure
APP_BUNDLE="dist/${APP_NAME}.app"
rm -rf dist
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp .build/apple/Products/Release/WinSet "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist and update version
cp Resources/Info.plist "$APP_BUNDLE/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy icon if exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

echo "✅ App bundle created: $APP_BUNDLE"

# Verify
echo ""
echo "📋 Bundle contents:"
ls -la "$APP_BUNDLE/Contents/"
ls -la "$APP_BUNDLE/Contents/MacOS/"

echo ""
echo "🔍 Binary architecture:"
file "$APP_BUNDLE/Contents/MacOS/WinSet"

# Create ZIP for distribution
cd dist
zip -r "${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app"
echo ""
echo "📦 Created: dist/${APP_NAME}-${VERSION}.zip"

# Calculate SHA
SHA=$(shasum -a 256 "${APP_NAME}-${VERSION}.zip" | cut -d ' ' -f 1)
echo "🔐 SHA256: $SHA"
