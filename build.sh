#!/bin/bash

# Configuration
IDENTITY="Apple Development: Mohammad Farseen Manekhan (48A578U846)"
BINARY_PATH=".build/debug/winset"

echo "🔨 Building WinSet..."
swift build

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "🔐 Signing binary..."
codesign --force --sign "$IDENTITY" \
    --entitlements "Entitlements.plist" \
    --options runtime \
    --timestamp \
    "$BINARY_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Code signing failed"
    exit 1
fi

echo "✅ Build and signing successful!"
echo "➡️  Run with: $BINARY_PATH"
