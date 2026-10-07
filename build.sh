#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/module-cache
# Build outside synced folders: file-provider Finder metadata invalidates signatures.
wing_staging=$(mktemp -d "${TMPDIR:-/tmp/}codex-radio.XXXXXX")
wing_app="$wing_staging/Codex Radio.app"
mkdir -p "$wing_app/Contents/MacOS" "$wing_app/Contents/Helpers" "$wing_app/Contents/Resources/Integration" "$wing_app/Contents/Resources/Audio" "$wing_app/Contents/Resources/Voices"
for radio_arch in arm64 x86_64; do
    swiftc -parse-as-library -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" -target "$radio_arch-apple-macosx13.0" HookCollector.swift -o "$wing_staging/hook-$radio_arch"
    swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" -target "$radio_arch-apple-macosx13.0" -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement -lsqlite3 Domain.swift ConversationActivity.swift ConversationCatalog.swift RecordedAudio.swift LiveEvents.swift Integration.swift IntegrationTests.swift Startup.swift StartupTests.swift App.swift Cockpit.swift Views.swift Tests.swift -o "$wing_staging/app-$radio_arch"
done
lipo -create "$wing_staging/app-arm64" "$wing_staging/app-x86_64" -output "$wing_app/Contents/MacOS/CodexRadio"
lipo -create "$wing_staging/hook-arm64" "$wing_staging/hook-x86_64" -output "$wing_app/Contents/Helpers/CodexRadioHook"
cp HookReview/collector.py HookReview/compaction_collector.py HookCollector.swift "$wing_app/Contents/Resources/Integration/"
cp -R Assets/SoundPacks "$wing_app/Contents/Resources/Audio/Packs"
mkdir -p "$wing_app/Contents/Resources/Licenses"
cp Assets/SoundSources/boeing/LICENSE "$wing_app/Contents/Resources/Licenses/Boeing-777-GPL-2.0.txt"
cp Assets/SoundSources/boeing/AUTHORS "$wing_app/Contents/Resources/Licenses/Boeing-777-Authors.txt"
cp Assets/SoundSources/airbus/README.md "$wing_app/Contents/Resources/Licenses/A320-Authors.md"
cp LICENSE "$wing_app/Contents/Resources/Licenses/Codex-Radio-GPL-2.0.txt"
cp THIRD_PARTY_NOTICES.md "$wing_app/Contents/Resources/Licenses/"
cp Assets/Voices/*.wav "$wing_app/Contents/Resources/Voices/"
cp '说明与来源.txt' "$wing_app/Contents/Resources/"
cp '接入边界.txt' "$wing_app/Contents/Resources/"
cp Assets/COPYING "$wing_app/Contents/Resources/"
cat > "$wing_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Codex Radio</string>
<key>CFBundleDisplayName</key><string>Codex Radio</string>
<key>CFBundleIdentifier</key><string>local.wingradio.menubar</string>
<key>CFBundleExecutable</key><string>CodexRadio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.10.0</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$wing_app/Contents/Helpers/CodexRadioHook"
codesign --force --sign - "$wing_app"
codesign --verify --deep --strict --verbose=2 "$wing_app"
"$wing_app/Contents/MacOS/CodexRadio" --self-test > build/verification.txt
python3 HookReview/test_collector.py >> build/verification.txt
python3 HookReview/test_compaction.py >> build/verification.txt
python3 HookReview/test_native_collector.py "$wing_app/Contents/Helpers/CodexRadioHook" >> build/verification.txt
python3 package.py "$wing_app"
print -r -- "$wing_app" > build/staged-app-path.txt
print -r -- "Verified app: $wing_app"
print -r -- "Release archive: $PWD/build/Codex Radio-0.10.0.zip"
zsh make-dmg.sh "$wing_app"
