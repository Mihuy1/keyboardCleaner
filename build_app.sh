#!/bin/bash
set -e

echo "🔨 Building KeyCleaner swift package..."
swift build -c release

echo "📦 Creating KeyCleaner.app bundle..."
mkdir -p build/KeyCleaner.app/Contents/MacOS
mkdir -p build/KeyCleaner.app/Contents/Resources

cp .build/release/KeyCleaner build/KeyCleaner.app/Contents/MacOS/KeyCleaner
cp Info.plist build/KeyCleaner.app/Contents/Info.plist

chmod +x build/KeyCleaner.app/Contents/MacOS/KeyCleaner

echo "🚀 Installing KeyCleaner.app to /Applications..."
rm -rf /Applications/KeyCleaner.app
cp -R build/KeyCleaner.app /Applications/KeyCleaner.app

echo "🔏 Signing /Applications/KeyCleaner.app..."
codesign --force --deep --sign - /Applications/KeyCleaner.app

echo "✅ KeyCleaner.app built, installed, and signed successfully at /Applications/KeyCleaner.app"
