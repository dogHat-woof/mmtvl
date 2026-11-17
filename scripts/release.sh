#!/bin/zsh
# MR: a public release of MMTVL, signed Developer ID, notarized and stapled.
#
# Bumps CURRENT_PROJECT_VERSION by 1 in all four configurations (project.pbxproj), like scripts/test-build.sh: the
# bumped number is never reused, even when a later stage fails. Then archives Release, exports it signed Developer ID
# (scripts/ExportOptions.plist), checks the signature, the hardened runtime, the entitlements (an exact allowlist) and
# every embedded framework, notarizes, staples, checks Gatekeeper's verdict, and zips the app to
# build/release/MMTVL-<version>-build<N>.zip, printing its SHA-256 (for the release notes). Everything it makes is
# in build/release/ (logs too). The version (MARKETING_VERSION) is changed by hand. The bump is left uncommitted.
# It never tags, pushes or publishes anything: those steps are done by hand once the release is confirmed.
#
# Needs the "Developer ID Application" certificate of the team in ExportOptions.plist in the login keychain, and a
# notarytool keychain profile (default "mmtvl-notary"; another with NOTARY_PROFILE=<name>), saved once with
#   xcrun notarytool store-credentials mmtvl-notary --apple-id <Apple ID> --team-id <team>
# which asks for an app-specific password. Credentials stay in the Keychain; this script never reads or prints them.
#
# Refuses to run with uncommitted changes or when HEAD isn't on master. For dry runs only:
#   MMTVL_RELEASE_ALLOW_BRANCH=1   allow a branch other than master
#   MMTVL_RELEASE_ALLOW_DIRTY=1    allow uncommitted changes (the build is then not the committed state)
#
# Usage: scripts/release.sh            (from the repo root)
set -euo pipefail

cd "$(dirname "$0")/.."
project=MMTVL.xcodeproj/project.pbxproj
export_options=scripts/ExportOptions.plist
out=build/release
archive=$out/MMTVL.xcarchive
app=$out/export/MMTVL.app
profile=${NOTARY_PROFILE:-mmtvl-notary}
allowed_entitlements=(com.apple.security.automation.apple-events)

fail() { print -u2 -- "release.sh: $*"; exit 1; }

team=$(/usr/libexec/PlistBuddy -c 'Print teamID' "$export_options") || fail "Can't read teamID from ${export_options}."

# 1. Only the committed state of master is released.
branch=$(git symbolic-ref --quiet --short HEAD || echo "(detached HEAD)")
if [[ $branch != master ]]; then
    if [[ ${MMTVL_RELEASE_ALLOW_BRANCH:-} == 1 ]]; then
        echo "Dry run: HEAD is on ${branch}, not master (MMTVL_RELEASE_ALLOW_BRANCH=1)."
    else
        fail "HEAD is on ${branch}, not master. Releases are made from master (dry runs: MMTVL_RELEASE_ALLOW_BRANCH=1)."
    fi
fi
dirty=$(git status --porcelain)
if [[ -n $dirty ]]; then
    if [[ ${MMTVL_RELEASE_ALLOW_DIRTY:-} == 1 ]]; then
        echo "Dry run: building with uncommitted changes (MMTVL_RELEASE_ALLOW_DIRTY=1):"
        print -r -- "$dirty"
    else
        print -u2 -r -- "$dirty"
        fail "The working tree has uncommitted changes (listed above). Commit or stash them first."
    fi
fi

# 2. The next build number (the counter scripts/test-build.sh uses; never reset or reused).
current=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*;' "$project" | grep -o '[0-9]*') \
    || fail "No CURRENT_PROJECT_VERSION in ${project}."
next=$((current + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${next};/" "$project"
bumped=1
on_exit() {
    local rc=$?
    if (( rc != 0 && ${bumped:-0} )); then
        print -u2 -- "Stopped; the build number stays ${next} (never reused). Commit project.pbxproj: Build ${next}"
    fi
}
trap on_exit EXIT

settings=$(xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build \
    -showBuildSettings 2>/dev/null) || fail "xcodebuild -showBuildSettings failed."
version=$(print -r -- "$settings" | awk -F' = ' '/^ *MARKETING_VERSION = / && v == "" { v = $2 } END { print v }')
build=$(print -r -- "$settings" | awk -F' = ' '/^ *CURRENT_PROJECT_VERSION = / && v == "" { v = $2 } END { print v }')
[[ -n $version ]] || fail "No MARKETING_VERSION in the Release build settings."
[[ $build == "$next" ]] || fail "The Release build settings say build ${build}, expected ${next}."
echo "Releasing MMTVL ${version} build ${next} (team ${team}, notary profile ${profile})"

# 3. Archive and export, signed Developer ID.
rm -rf "$out"
mkdir -p "$out"

echo "Archiving (log: ${out}/archive.log)…"
if ! xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build \
    -archivePath "$archive" archive > "$out/archive.log" 2>&1; then
    grep -E ' error:' "$out/archive.log" || tail -20 "$out/archive.log"
    fail "Archive failed (log: ${out}/archive.log)."
fi

echo "Exporting with Developer ID (log: ${out}/export.log)…"
if ! xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$export_options" \
    -exportPath "$out/export" -allowProvisioningUpdates > "$out/export.log" 2>&1; then
    grep -E 'error|errSec' "$out/export.log" || tail -20 "$out/export.log"
    if grep -q errSecInternalComponent "$out/export.log"; then
        print -u2 -- "codesign can't use the Developer ID private key without asking. Sign anything once in Terminal with"
        print -u2 -- "the Developer ID identity and answer Always Allow (or allow codesign in the key's Access Control)."
    fi
    fail "Export failed (log: ${out}/export.log)."
fi
[[ -d $app ]] || fail "The export has no MMTVL.app (log: ${out}/export.log)."

# 4. Checks before anything goes to Apple.
built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
[[ $built == "$next" ]] || fail "The exported app says build ${built}, expected ${next}."
built_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ $built_version == "$version" ]] || fail "The exported app says version ${built_version}, expected ${version}."
echo "Info.plist: version ${built_version}, build ${built}"

echo "codesign --verify --deep --strict:"
verify=$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1) || { print -r -- "$verify"; fail "The signature doesn't verify."; }
print -r -- "$verify"

# Developer ID Application of the team, with the hardened runtime. $1: path, $2: name in messages.
check_signature() {
    local info line authority='' team_ok=0 runtime=0 flags=''
    info=$(codesign -dvv "$1" 2>&1) || fail "codesign can't read the signature of $2."
    for line in "${(@f)info}"; do
        if [[ -z $authority && $line == Authority=* ]]; then authority=${line#Authority=}; fi
        if [[ $line == "TeamIdentifier=${team}" ]]; then team_ok=1; fi
        if [[ $line == CodeDirectory* && $line =~ 'flags=0x[0-9a-f]+\(([a-z-]+,)*runtime(,[a-z-]+)*\)' ]]; then
            runtime=1
            flags=${MATCH}
        fi
    done
    [[ $authority == "Developer ID Application: "*"(${team})" ]] \
        || fail "$2 is signed by \"${authority:-nobody}\", not Developer ID Application (${team})."
    (( team_ok )) || fail "$2 isn't signed with TeamIdentifier=${team}."
    (( runtime )) || fail "$2 doesn't have the hardened runtime (flags runtime)."
    echo "  $2: Authority=${authority}, TeamIdentifier=${team}, ${flags}"
}

echo "Signatures:"
check_signature "$app" MMTVL.app
frameworks=("$app"/Contents/Frameworks/*.framework(N))
for fw in "${frameworks[@]}"; do
    check_signature "$fw" "${fw:t}"
done
echo "  ${#frameworks} frameworks checked"

codesign -d --entitlements - --xml "$app" > "$out/entitlements.plist" 2>/dev/null \
    || fail "codesign can't read the entitlements."
entitlements=$(python3 -I -c '
import plistlib, sys
data = open(sys.argv[1], "rb").read()
for key, value in sorted((plistlib.loads(data) if data.strip() else {}).items()):
    print(f"{key}={value!r}")
' "$out/entitlements.plist") || fail "Can't parse the entitlements."
echo "Entitlements:"
print -r -- "${entitlements:-  (none)}" | sed 's/^/  /'
keys=$(print -r -- "$entitlements" | sed -n 's/=.*//p' | sort)
expected=$(print -l -- "${allowed_entitlements[@]}" | sort)
[[ $keys == "$expected" ]] \
    || fail "The entitlements must be exactly: ${allowed_entitlements[*]} (no get-task-allow, no cs.* exception)."

# 5. Notarize (uploads the app to Apple's notary service) and staple.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
echo "Notarizing (waits for Apple's answer)…"
started=$SECONDS
xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$profile" --wait --output-format json \
    > "$out/notary.json" 2> "$out/notary.err" || true
took=$((SECONDS - started))
json_field() {
    python3 -I -c 'import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception:
    print("")' "$out/notary.json" "$1"
}
submission=$(json_field id)
notary_status=$(json_field status)
echo "Notarization: id ${submission:-?}, status ${notary_status:-?}, $((took / 60)) min $((took % 60)) s"
if [[ $notary_status != Accepted ]]; then
    [[ -s $out/notary.err ]] && cat "$out/notary.err" >&2
    [[ -n $submission ]] && print -u2 -- "Why: xcrun notarytool log ${submission} --keychain-profile ${profile}"
    fail "Notarization wasn't accepted."
fi

xcrun stapler staple "$app" || fail "Stapling failed."
xcrun stapler validate "$app" || fail "The stapled ticket doesn't validate."
assessment=$(spctl -a -vvv -t exec "$app" 2>&1) || { print -r -- "$assessment"; fail "Gatekeeper rejects the app."; }
print -r -- "$assessment"
[[ $assessment == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper doesn't say Notarized Developer ID."

# 6. The release zip.
zip=$out/MMTVL-${version}-build${next}.zip
ditto -c -k --keepParent "$app" "$zip"
sha=$(shasum -a 256 "$zip" | awk '{ print $1 }')
echo
echo "Release zip: ${zip}"
echo "SHA-256: ${sha}"
echo "Not tagged, pushed or published. Commit project.pbxproj: Build ${next}"
