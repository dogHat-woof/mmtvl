#!/bin/zsh
# M7c L28: a Release build for testing on the Mac mini, with the next build number.
#
# Bumps CURRENT_PROJECT_VERSION by 1 in all four configurations (project.pbxproj), builds Release, checks the
# signature and zips the app to ~/Desktop/MMTVL-<version>-build<N>.zip. The version (MARKETING_VERSION) is changed
# by hand. Development-signed, not notarized (M8's scripts/release.sh makes public releases).
#
# Usage: scripts/test-build.sh            (from the repo root)
set -euo pipefail

cd "$(dirname "$0")/.."
project=MMTVL.xcodeproj/project.pbxproj

current=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*;' "$project" | grep -o '[0-9]*')
next=$((current + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${next};/" "$project"
version=$(grep -m1 -o 'MARKETING_VERSION = [^;]*;' "$project" | sed 's/MARKETING_VERSION = //; s/;//')
echo "Building MMTVL ${version} build ${next}"

if ! xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build build \
    > build/test-build.log 2>&1; then
    grep -E ' error:' build/test-build.log || tail -20 build/test-build.log
    echo "Build failed (log: build/test-build.log); the build number stays ${next}."
    exit 1
fi

app=build/Build/Products/Release/MMTVL.app
codesign --verify --deep --strict "$app"
built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
[[ "$built" == "$next" ]] || { echo "The built app says build ${built}, expected ${next}"; exit 1; }

zip=~/Desktop/MMTVL-${version}-build${next}.zip
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "$zip"
