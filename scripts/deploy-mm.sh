#!/bin/zsh
# Installs a test build on the Mac mini over SSH and relaunches MMTVL there.
#
# Copies the zip from scripts/test-build.sh (default: the newest ~/Desktop/MMTVL-*-build*.zip) to the mini's
# ~/Downloads, unzips and checks it there (signature, build number), stops the running MMTVL, replaces
# /Applications/MMTVL.app and opens it. Afterwards only the last 3 builds' zips are kept, on the mini (~/Downloads)
# and on this Mac (~/Desktop); older ones are deleted. The zips on the mini are what --rollback installs.
#
# Usage (from the repo root):
#   scripts/deploy-mm.sh                 the newest build zip on the Desktop
#   scripts/deploy-mm.sh <zip>           a given zip
#   scripts/deploy-mm.sh --rollback      install the newest kept build older than the installed one
#
# Needs SSH key login to the mini (Remote Login on). Override with MM_HOST=user@host and MM_KEY=<private key>.
set -euo pipefail

host=${MM_HOST:-user@mm.example}
key=${MM_KEY:-$HOME/.ssh/id_ed25519_example}
keep=3
opts=(-i "$key" -o IdentitiesOnly=yes -o ConnectTimeout=5)

# prune <dir> <n>: deletes all but the newest n MMTVL-*-build<N>.zip in dir, by build number. Used here and on the mini.
prune_fn=$(cat <<'FN'
prune() {
    local dir=$1 keep=$2 f n
    local -a lines old
    for f in "$dir"/MMTVL-*-build*.zip(N); do
        n=${f:t}; n=${n##*build}; n=${n%.zip}
        [[ "$n" == <-> ]] && lines+=("$n $f")
    done
    (( ${#lines} > keep )) || return 0
    old=("${(@f)$(print -rl -- "${lines[@]}" | sort -n | head -n $(( ${#lines} - keep )) | cut -d' ' -f2-)}")
    for f in "${old[@]}"; do
        echo "Removing ${f:t}"
        rm -f -- "$f"
    done
}
FN
)

# The steps on the mini. $1: "install" <zip name> <build> | "rollback". KEEP: how many zips to keep.
remote="$prune_fn"$'\n'$(cat <<'REMOTE'
set -euo pipefail
app=/Applications/MMTVL.app
downloads=~/Downloads

installed_build() {
    if [[ -d "$app" ]]; then
        /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist"
    else
        echo 0
    fi
}

stop_mmtvl() {
    pgrep -x MMTVL >/dev/null || return 0
    # SIGTERM, not a quit request: with the kiosk lock on, a quit request asks for the PIN on the TV.
    pkill -TERM -x MMTVL || true
    for _ in {1..50}; do pgrep -x MMTVL >/dev/null || return 0; sleep 0.2; done
    echo "MMTVL didn't stop; killing it"
    pkill -KILL -x MMTVL || true
    sleep 0.5
}

start_mmtvl() {
    open "$app"
    for _ in {1..25}; do
        if pgrep -x MMTVL >/dev/null; then
            echo "MMTVL $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist") build $(installed_build) is running"
            return 0
        fi
        sleep 0.2
    done
    echo "MMTVL didn't start (is someone logged in on the mini?)"
    exit 1
}

# install_zip <zip> <build>: unzips, checks the signature and the build number, and swaps the app in.
install_zip() {
    local zip=$1 expected=$2 built
    stage=$(mktemp -d "$downloads/mmtvl-deploy.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    ditto -x -k "$zip" "$stage"
    codesign --verify --deep --strict "$stage/MMTVL.app"
    built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$stage/MMTVL.app/Contents/Info.plist")
    [[ "$built" == "$expected" ]] || { echo "The unzipped app is build ${built}, expected ${expected}"; exit 1; }
    stop_mmtvl
    rm -rf "$app"
    mv "$stage/MMTVL.app" "$app"
    start_mmtvl
}

current=$(installed_build)
case "$1" in
install)
    # Keep the installed build's zip for --rollback if it isn't there yet (e.g. installed by hand).
    kept=("$downloads"/MMTVL-*-build"$current".zip(N))
    if [[ "$current" != 0 && "$current" != "$3" && ${#kept} -eq 0 ]]; then
        version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
        echo "Keeping the installed build ${current} as MMTVL-${version}-build${current}.zip"
        ditto -c -k --keepParent "$app" "$downloads/MMTVL-${version}-build${current}.zip"
    fi
    install_zip "$downloads/$2" "$3"
    prune "$downloads" "$KEEP"
    ;;
rollback)
    best=0; best_zip=""
    for f in "$downloads"/MMTVL-*-build*.zip(N); do
        n=${f:t}; n=${n##*build}; n=${n%.zip}
        if [[ "$n" == <-> ]] && (( n < current && n > best )); then best=$n; best_zip=$f; fi
    done
    [[ -n "$best_zip" ]] || { echo "No kept build older than build ${current} on the mini"; exit 1; }
    echo "Rolling back from build ${current} to ${best_zip:t}"
    install_zip "$best_zip" "$best"
    ;;
esac
REMOTE
)

if ! ssh "${opts[@]}" -o BatchMode=yes "$host" true 2>/dev/null; then
    echo "Can't log in to ${host} with an SSH key (is the mini awake, and is the key loaded?)."
    exit 1
fi

if [[ "${1:-}" == "--rollback" ]]; then
    ssh "${opts[@]}" "$host" "KEEP=$keep zsh -s rollback" <<< "$remote"
    exit 0
fi

zip=${1:-$(ls -t ~/Desktop/MMTVL-*-build*.zip 2>/dev/null | head -1)}
[[ -n "$zip" && -f "$zip" ]] || { echo "No build zip found (run scripts/test-build.sh first)"; exit 1; }
name=${zip:t}
[[ "$name" =~ 'build([0-9]+)\.zip$' ]] || { echo "Can't read the build number from ${name}"; exit 1; }
build=${match[1]}

echo "Installing ${name} on ${host}"
scp -q "${opts[@]}" "$zip" "${host}:Downloads/${name}"
ssh "${opts[@]}" "$host" "KEEP=$keep zsh -s install '${name}' '${build}'" <<< "$remote"

# This Mac: keep the last $keep build zips on the Desktop.
eval "$prune_fn"
prune ~/Desktop "$keep"
