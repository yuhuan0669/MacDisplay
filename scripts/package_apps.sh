#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Building MacDisplay in release mode..."
swift build -c release

BIN_DIR="$DIR/.build/release"
OUTPUT_DIR="$DIR/dist"
mkdir -p "$OUTPUT_DIR"

# 1. Package Sender.app
echo "==> Packaging MacDisplay Sender.app..."
SENDER_APP="$OUTPUT_DIR/MacDisplay Sender.app"
rm -rf "$SENDER_APP"
mkdir -p "$SENDER_APP/Contents/MacOS" "$SENDER_APP/Contents/Resources"
cp "$BIN_DIR/Sender" "$SENDER_APP/Contents/MacOS/MacDisplay Sender"

cat > "$SENDER_APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacDisplay Sender</string>
    <key>CFBundleIdentifier</key>
    <string>com.macdisplay.sender</string>
    <key>CFBundleName</key>
    <string>MacDisplay Sender</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MacDisplay needs screen recording permission to stream your display to the target Mac.</string>
</dict>
</plist>
EOF

# Sign with stable designated requirement so macOS TCC remembers permission across rebuilds
codesign --force --deep -s - -i "com.macdisplay.sender" --requirements '=designated => identifier "com.macdisplay.sender"' "$SENDER_APP"
codesign --verify --deep --strict "$SENDER_APP"

# 2. Package Receiver.app
echo "==> Packaging MacDisplay Receiver.app..."
RECEIVER_APP="$OUTPUT_DIR/MacDisplay Receiver.app"
rm -rf "$RECEIVER_APP"
mkdir -p "$RECEIVER_APP/Contents/MacOS" "$RECEIVER_APP/Contents/Resources"
cp "$BIN_DIR/Receiver" "$RECEIVER_APP/Contents/MacOS/MacDisplay Receiver"

cat > "$RECEIVER_APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacDisplay Receiver</string>
    <key>CFBundleIdentifier</key>
    <string>com.macdisplay.receiver</string>
    <key>CFBundleName</key>
    <string>MacDisplay Receiver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep -s - -i "com.macdisplay.receiver" --requirements '=designated => identifier "com.macdisplay.receiver"' "$RECEIVER_APP"
codesign --verify --deep --strict "$RECEIVER_APP"

echo "==> Applications packaged and signed successfully in $OUTPUT_DIR"

if [ "$1" = "--install-sender" ] || [ "$1" = "--install-all" ]; then
    echo "==> Installing MacDisplay Sender.app to /Applications and Desktop..."
    rm -rf "/Applications/MacDisplay Sender.app"
    cp -R "$SENDER_APP" /Applications/
    rm -rf "$HOME/Desktop/MacDisplay Sender.app"
    cp -R "$SENDER_APP" "$HOME/Desktop/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/MacDisplay Sender.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Desktop/MacDisplay Sender.app"
    echo "==> Sender installation verified."
fi

if [ "$1" = "--install-receiver" ] || [ "$1" = "--install-all" ]; then
    echo "==> Installing MacDisplay Receiver.app to /Applications and Desktop..."
    rm -rf "/Applications/MacDisplay Receiver.app"
    cp -R "$RECEIVER_APP" /Applications/
    rm -rf "$HOME/Desktop/MacDisplay Receiver.app"
    cp -R "$RECEIVER_APP" "$HOME/Desktop/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/MacDisplay Receiver.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Desktop/MacDisplay Receiver.app"
    echo "==> Receiver installation verified."
fi
