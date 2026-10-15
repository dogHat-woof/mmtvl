# M8 — Release & distribution

| | |
|---|---|
| Status | Planned |
| Depends on | M7b (code complete; its hardware checks, now M7d, can run in parallel) |
| Master plan decisions used | D4, D9, D10, D13, D15, D19, D22, D24, D28; new **D33** (Developer ID + notarized releases on GitHub, no Homebrew, no App Store), **D34** (open source: MIT, notices, scrubbed public history) |
| Planned | 2026-10-06 |

## Goal

Anyone can download MMTVL from the repo's GitHub Releases page (a zip). It opens after only macOS's standard "downloaded from the Internet" confirmation, because it is signed with the user's **Developer ID** and **notarized**. The source is public at `github.com/dwolcot1/mmtvl` under the **MIT** license. The history is rewritten so it doesn't name the user's IPTV provider or show the user's personal email. The app carries the license notices for every bundled library, and Settings has a **Licenses** page you can read from the couch (a QR code per component). A release is one script run (`scripts/release.sh`) plus a GitHub release. On the Mac mini, upgrading from the development-signed 1.0 to the first notarized release (**1.0.1**) needs a one-time Accessibility re-grant, which the README and the release notes explain.

## Out of scope

- **Mac App Store.** The App Sandbox would remove the core of MMTVL: the event tap and Accessibility (global Home, D4/D17), synthetic key and mouse events to other apps (D24, D31), AX full screen of other apps (D15), managing Reflector (D32). The YouTube TV approach (D5/D21) would likely fail App Review. Master plan §2 already lists App Store distribution and sandboxing as non-goals.
- **Homebrew** (a tap or the official `homebrew/cask`): not wanted (user choice 2026-10-06); the app lives on GitHub only. Notarization keeps the door open: Homebrew requires it anyway.
- Automatic updates inside the app (Sparkle). Users download the new zip from Releases. Possible later.
- CI release builds (GitHub Actions with signing secrets). Releases are built on the user's Mac with `scripts/release.sh`.
- DMG packaging. The release asset is a zip (L6).
- Changing app behavior or defaults for new users (first-run wizard, casting off by default). Possible later.
- M7b's hardware checks (steps 5, 7, 8, 10, 12 of that plan) moved to M7d (2026-10-14) and stay there.

## Research & findings

### Current state (verified 2026-10-06)

- Signing: `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "Apple Development"`, `DEVELOPMENT_TEAM = H846CY8RB4` in all four target configurations (app and tests, Debug and Release). The only code-signing identity on the dev Mac is `Apple Development: Derek Wolcott (93R37R2L88)` (certificate OU `H846CY8RB4`, expires 2027-09-23). **No Developer ID Application certificate yet.** The user says the account is a **paid** Apple Developer Program membership; CLAUDE.md calls H846CY8RB4 a "personal team". Whether H846CY8RB4 *is* the paid team is **unverified** (step 1).
- `ENABLE_HARDENED_RUNTIME = NO`, `ENABLE_APP_SANDBOX = NO` on the app target. No `.entitlements` file exists.
- Version: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` (all four configurations). Tag `v1.0` (development-signed, installed on the Mac mini by hand).
- The repo `dwolcot1/mmtvl` is **private**; there is **no LICENSE and no README**. `.gitignore` ignores `build/`.
- The Release `.app` is universal (x86_64 + arm64), 105 MB (41 MB zipped), minimum macOS 26.0.
- App data the app creates (dev Mac): `~/Library/Application Support/MMTVL`, `~/Library/Caches/MMTVL`, `~/Library/Caches/dev.mmtvl.launcher`, `~/Library/HTTPStorages/dev.mmtvl.launcher` (+ `.binarycookies`), `~/Library/Preferences/dev.mmtvl.launcher.plist`, `~/Library/WebKit/dev.mmtvl.launcher`. Keychain items: legacy login keychain, service `dev.mmtvl.launcher` (CLAUDE.md).
- No AppleScript/Apple Events anywhere in `MMTVL/` (checked with grep), so no `com.apple.security.automation.apple-events` entitlement is needed.

### Embedded frameworks (`MMTVL.app/Contents/Frameworks`, Release build of 2026-10-06)

`gmp, gnutls, hogweed, lcms2, Libass, Libavcodec, Libavdevice, Libavfilter, Libavformat, Libavutil, Libbluray, Libcrypto, Libdav1d, Libdovi, Libfreetype, Libfribidi, Libharfbuzz, Libluajit, Libmpv, Libplacebo, Libshaderc_combined, Libssl, Libswresample, Libswscale, Libuavs3d, Libuchardet, Libunibreak, nettle` (28). They are already re-signed by Xcode with the app's identity (`TeamIdentifier=H846CY8RB4` on `Libmpv.framework`), so library validation under the hardened runtime is satisfied without `disable-library-validation`. GRDB is linked statically (no framework).

### Licenses (MPVKit 1.0.0 build script, `Sources/BuildScripts/XCFrameworkBuild/main.swift` at tag `1.0.0`, read with `gh api`)

- MPVKit README: "`MPVKit` source alone is licensed under the LGPL v3.0. `MPVKit` bundles (`frameworks`, `xcframeworks`), which include both `libmpv` and `FFmpeg` libraries, are also licensed under the LGPL v3.0" (the non-`-GPL` product, which MMTVL uses). [MPVKit](https://github.com/mpvkit/MPVKit), LICENSE = LGPL-3.0.
- FFmpeg is configured with `--enable-version3` and without `--enable-gpl`, so FFmpeg is **LGPL-3.0-or-later** ([FFmpeg legal](https://ffmpeg.org/legal.html)).
- Versions in that build script: mpv `v0.41.0`, FFmpeg `n8.1.2`, OpenSSL `3.3.5`, gnutls/nettle/gmp from `mpvkit/gnutls-build` release `3.8.11`, libass/libunibreak/freetype/fribidi/harfbuzz from `mpvkit/libass-build` release `0.17.5`, dav1d `1.5.3`, lcms2 `2.17.0`, libplacebo `7.360.1`, libdovi `3.3.2`, shaderc `2025.5.0`, uchardet `0.0.8`, libbluray `1.4.0`, LuaJIT `2.1.0-fix`, uavs3d `1.2.1-fix`. (The build-repo release tags are MPVKit's names, not always the library's own version: step 3 records each library's real version from its build repo.) Libsmbclient (GPL product only), MoltenVK and Vulkan are **not** embedded.
- The planner's understanding of each component's license (**verify each one in step 3** from the upstream `COPYING`/`LICENSE` at the shipped version): mpv LGPL-2.1-or-later (LGPL build); FFmpeg LGPL-3.0-or-later; GnuTLS LGPL-2.1-or-later; Nettle/hogweed and GMP dual LGPL-3.0-or-later / GPL-2.0-or-later; OpenSSL 3 Apache-2.0; libass ISC; libunibreak zlib; FreeType FTL or GPL-2.0 (choose FTL); FriBidi LGPL-2.1-or-later; HarfBuzz MIT ("Old MIT"); Little CMS MIT; libplacebo LGPL-2.1-or-later; dav1d BSD-2-Clause; libdovi MIT; shaderc Apache-2.0 (with glslang and SPIRV-Tools notices); uchardet MPL-1.1 / GPL-2.0-or-later / LGPL-2.1-or-later; libbluray LGPL-2.1-or-later; LuaJIT MIT; uavs3d **unverified** (BSD-style); GRDB MIT ([GRDB](https://github.com/groue/GRDB.swift)).
- LGPL obligations that matter here (not legal advice; this is the common reading): ship the LGPL and GPL texts (LGPL-3.0 incorporates GPL-3.0); give each library's copyright notice; give the user the corresponding source (or a written offer) for the LGPL libraries; let users replace the libraries. The frameworks are separate dynamic libraries, and a user can replace one and re-sign the app ad hoc (`codesign --force --deep -s - MMTVL.app`), which the notices explain.

### Hardened runtime

- Xcode has build settings for the hardened-runtime exceptions: `RUNTIME_EXCEPTION_ALLOW_JIT`, `RUNTIME_EXCEPTION_ALLOW_UNSIGNED_EXECUTABLE_MEMORY`, `RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION`, `RUNTIME_EXCEPTION_DISABLE_EXECUTABLE_PAGE_PROTECTION`, `RUNTIME_EXCEPTION_ALLOW_DYLD_ENVIRONMENT_VARIABLES`, `RUNTIME_EXCEPTION_DEBUGGING_TOOL` (found in Xcode 27's `CoreBuildSystem.xcspec`). With `ENABLE_HARDENED_RUNTIME = YES` they generate the entitlements, so **no entitlements file is needed**.
- mpv embeds **LuaJIT** (`Libluajit.framework`) for its built-in Lua scripts. Under the hardened runtime, JIT memory needs `MAP_JIT` plus `com.apple.security.cs.allow-jit` ([Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime), [Apple forum on allow-jit vs allow-unsigned-executable-memory](https://developer.apple.com/forums/thread/776290)). IINA (an mpv player, notarized) uses `allow-unsigned-executable-memory` and `disable-library-validation` ([IINA.entitlements](https://github.com/iina/iina/blob/develop/iina/IINA.entitlements)); IINA loads plugins, MMTVL doesn't. **Unverified:** whether LuaJIT on **Intel** needs `allow-unsigned-executable-memory` (no Intel Mac to test; master plan Q16). If LuaJIT can't get JIT memory it aborts the trace and keeps interpreting (LuaJIT behavior), so the expected worst case is slower Lua, not a crash.
- Event taps, Accessibility, `CGEvent.post`, `WKWebView`, Network.framework listeners and BSD sockets need no hardened-runtime entitlement.
- Changing the **runtime flag** doesn't change the app's designated requirement, so Debug builds keep their Accessibility grant (step 2). Changing the **certificate** (Apple Development → Developer ID) does change it.

### Notarization and export (Xcode 27, verified with `xcodebuild -help` and `xcrun notarytool --help`)

- `-exportOptionsPlist` `method` values: `app-store-connect, release-testing, enterprise, debugging, developer-id, mac-application, validation`. Use **`developer-id`**.
- `xcrun notarytool store-credentials <profile>` saves credentials to the Keychain (interactive prompts for anything not given). `xcrun notarytool submit <zip> --keychain-profile <profile> --wait`; `notarytool log <id> --keychain-profile <profile>` explains a rejection. Then `xcrun stapler staple MMTVL.app` and `xcrun stapler validate MMTVL.app`. `spctl -a -vvv -t exec MMTVL.app` should say `source=Notarized Developer ID`.
- Credentials are an Apple ID **app-specific password** (appleid.apple.com → Sign-In and Security) or an App Store Connect API key. They never go in the repo.

### Gatekeeper and downloads

- Files downloaded with a browser get the quarantine attribute; Gatekeeper then checks the app on first launch. A notarized app with a stapled ticket opens after the standard "downloaded from the Internet" confirmation, even offline. A development-signed or un-notarized app is blocked (Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine`), which is what the user hit with the 1.0 zip.

### Secrets scan and history rewrite

- **gitleaks** (v8.24.x, maintenance mode): `gitleaks git -v --redact <repo>` scans all history through `git log -p`; `gitleaks dir -v <path>` scans files; `--config` takes a `.gitleaks.toml` with `[extend] useDefault = true` plus extra rules; `--report-path`/`--report-format json` ([gitleaks](https://github.com/gitleaks/gitleaks)). Not installed on the dev Mac (`brew install gitleaks`).
- **git-filter-repo** (`brew install git-filter-repo`, not installed): `--replace-text <file>` rewrites file contents in every commit (lines `literal==>replacement` or `regex:pattern==>replacement`), `--replace-message <file>` does the same for commit messages, `--mailmap <file>` rewrites author/committer identities. It wants a fresh clone and removes `origin`.
- Planner's survey of the history (2026-10-06): no real tokens found. Playlist and stream URLs appear only as placeholders (`https://iptv.example/app2/<18-char token>`, test value `abc`). But the docs and two test files name the provider (`the provider`, `iptv.example`, 24 matches) and its stream CDN (`stream-cdn.example`, 1 match in `docs/plans/archive/M4-live-tv.md`). LAN addresses in tests are fixtures (`192.168.1.x`, `*.plex.direct`). 27 commits have author email `user@example.com`; 15 use `57643254+dwolcot1@users.noreply.github.com`.
- **GitHub keeps every pull request's commits** (`refs/pull/<n>/head`), and they can't be deleted by the repo owner. Force-pushing rewritten history into the existing repo and making it public would still expose the old commits through PRs #1–#15. Hence L13: publish the rewritten history to a **new** repository.

## Design

### New and changed files

| File | Responsibility |
|---|---|
| `MMTVL.xcodeproj/project.pbxproj` | Build settings only: hardened runtime + allow-jit (step 2); version 1.0.1 / build 2 (step 11); team ID only if step 1 says so. |
| `MMTVL/Settings/ThirdPartyLicenses.swift` (new) | `ThirdPartyComponent` data: every shipped component, its version, license, copyright, URL and frameworks. |
| `MMTVL/Licenses/THIRD_PARTY_NOTICES.md` (new, bundled) | MMTVL's own MIT license, then each component's notice and full license texts, LGPL source and relinking notes. Ships in `Contents/Resources` (synchronized group). |
| `LICENSE` (new, repo root) | MIT, `Copyright (c) 2026 Derek Wolcott`. |
| `README.md` (new, repo root) | What MMTVL is, install, first run, permissions, upgrading, unofficial YouTube TV and IPTV notes, trademarks, building from source, licenses. |
| `MMTVL/Settings/SettingsTypes.swift` | `SettingsPage.licenses`, `.license(id: String)`. |
| `MMTVL/Settings/SettingsModel+Pages.swift` | Root row *Licenses*; the two pages. |
| `scripts/release.sh` (new) | Archive, export with Developer ID, verify, notarize, staple, zip, checksum. |
| `scripts/ExportOptions.plist` (new) | `method = developer-id`, team, automatic signing. |
| `scripts/gitleaks.toml` (new) | Default rules + rules for IPTV-style URLs, Plex tokens and the user's real hosts (supplied at run time, never committed). |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | Signing, release process, licenses, the public repo. |

`scripts/` is outside the synchronized `MMTVL/` folder, so nothing there is bundled into the app.

### Key types

```swift
// Settings/ThirdPartyLicenses.swift
nonisolated struct ThirdPartyComponent: Identifiable, Hashable, Sendable {
    /// Stable id, e.g. "mpv", "ffmpeg", "grdb"; used in SettingsPage.license(id:) and row ids.
    var id: String
    /// Display name, e.g. "FFmpeg".
    var name: String
    /// The shipped version, e.g. "8.1.2".
    var version: String
    /// SPDX-style expression, e.g. "LGPL-3.0-or-later".
    var license: String
    /// One line, e.g. "Copyright © 2000–2026 the FFmpeg developers".
    var copyright: String
    /// https URL of the source / license (shown as a QR code).
    var url: String
    /// Embedded framework names without ".framework" that belong to this component; [] for static code.
    var frameworks: [String]
}

nonisolated enum ThirdPartyLicenses {
    /// Bundled notices file (Contents/Resources/THIRD_PARTY_NOTICES.md).
    static let noticesResource = "THIRD_PARTY_NOTICES"
    static let noticesExtension = "md"
    /// MMTVL itself (MIT), listed first on the Licenses page.
    static let mmtvl: ThirdPartyComponent
    /// MMTVL first, then the others sorted by name (case-insensitive).
    static let all: [ThirdPartyComponent]
    static func component(id: String) -> ThirdPartyComponent?
}
```

Components (ids and frameworks; versions and licenses verified in step 3):

| id | name | frameworks |
|---|---|---|
| `mmtvl` | MMTVL | — |
| `grdb` | GRDB | — |
| `mpvkit` | MPVKit | — |
| `mpv` | mpv | Libmpv |
| `ffmpeg` | FFmpeg | Libavcodec, Libavdevice, Libavfilter, Libavformat, Libavutil, Libswresample, Libswscale |
| `openssl` | OpenSSL | Libcrypto, Libssl |
| `gnutls` | GnuTLS | gnutls |
| `nettle` | Nettle | nettle, hogweed |
| `gmp` | GMP | gmp |
| `libass` | libass | Libass |
| `libunibreak` | libunibreak | Libunibreak |
| `freetype` | FreeType | Libfreetype |
| `fribidi` | FriBidi | Libfribidi |
| `harfbuzz` | HarfBuzz | Libharfbuzz |
| `lcms2` | Little CMS | lcms2 |
| `libplacebo` | libplacebo | Libplacebo |
| `dav1d` | dav1d | Libdav1d |
| `libdovi` | libdovi | Libdovi |
| `shaderc` | shaderc | Libshaderc_combined |
| `uchardet` | uchardet | Libuchardet |
| `libbluray` | libbluray | Libbluray |
| `luajit` | LuaJIT | Libluajit |
| `uavs3d` | uavs3d | Libuavs3d |

### Settings → Licenses (TV-friendly)

- Root page, section `system`: a new row `licenses` "Licenses", `showsDisclosure`, action `.push(.licenses)`, **after** `exit`. The footer stays.
- `.licenses`: title "Licenses", image `.symbol("doc.text")`, hint "Select: choose · Back: return". One section `licenses`, one row per `ThirdPartyLicenses.all` entry: id `license.<id>`, title `name`, value `license`, detail `"Version \(version)"`, `showsDisclosure`, action `.push(.license(id: id))`. Footer: "Full license texts and source links are in THIRD_PARTY_NOTICES.md inside MMTVL.app and at github.com/dwolcot1/mmtvl."
- `.license(id:)`: title = the component's name ("License" if unknown), image `.qrCode(component.url)` (scan it with a phone), hint "Scan the code to read the license · Back: return". Section `license` with info rows `license.version` "Version", `license.license` "License", `license.copyright` (title = the copyright line, no value), `license.source` "Source" (value = the URL without `https://`), then the action row `license.done` "Done" (`.pop`). An unknown id shows only the Done row.

### Release flow

`scripts/release.sh` (run from the repo root; zsh; `set -euo pipefail`):

1. Read `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -showBuildSettings` (first match of each).
2. Refuse to run if `git status --porcelain` lists anything outside `MMTVL.xcodeproj/xcshareddata/xcschemes/` (the user keeps a local scheme tweak) or if HEAD isn't on `master`; print why.
3. `rm -rf build/release && mkdir -p build/release`.
4. `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -archivePath build/release/MMTVL.xcarchive archive`.
5. `xcodebuild -exportArchive -archivePath build/release/MMTVL.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/release/export -allowProvisioningUpdates`.
6. Checks on `build/release/export/MMTVL.app` (each failure stops the script with a message):
   - `codesign --verify --deep --strict --verbose=2`;
   - `codesign -dvv` output contains `Authority=Developer ID Application` and `TeamIdentifier=<team>` and `flags=0x10000(runtime)`;
   - `codesign -d --entitlements - --xml` contains `com.apple.security.cs.allow-jit` and **not** `com.apple.security.get-task-allow`;
   - every framework in `Contents/Frameworks` has `Authority=Developer ID Application`.
7. `ditto -c -k --keepParent <app> build/release/notarize.zip`; `xcrun notarytool submit build/release/notarize.zip --keychain-profile "${NOTARY_PROFILE:-mmtvl-notary}" --wait --output-format json > build/release/notary.json`; stop unless `status` is `Accepted` (parse with `plutil -extract status raw` after converting, or `python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])'`); on failure print the `id` and the `notarytool log` command.
8. `xcrun stapler staple <app>`; `xcrun stapler validate <app>`; `spctl -a -vvv -t exec <app>` must mention `Notarized Developer ID`.
9. `ditto -c -k --keepParent <app> build/release/MMTVL-<version>.zip`; print `shasum -a 256` of it (for the release notes).

The script never tags, pushes or creates releases: those are outward steps done by hand (step 11) after the user confirms.

`scripts/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>H846CY8RB4</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
```

### Local decisions

- **L1 — Team.** Keep `DEVELOPMENT_TEAM = H846CY8RB4` if step 1 shows it is the paid team (it already owns the Apple Development certificate). If the paid membership has another team ID, switch all four configurations, `ExportOptions.plist` and the docs to it. That is a new signing identity for Debug too, so the dev Mac re-grants Accessibility once.
- **L2 — Debug vs Release identity.** Debug builds stay `Apple Development` (daily development keeps its Accessibility grant and Keychain access); only exported releases are `Developer ID Application`. *Pitfall:* running a release build and a Debug build on the **same** Mac flips Accessibility and Keychain access between them. The dev Mac runs Debug; the mini runs releases.
- **L3 — Hardened runtime for both configurations,** so Debug behaves like a release and entitlement problems show up during development. Only exception: `RUNTIME_EXCEPTION_ALLOW_JIT = YES` (LuaJIT). No `disable-library-validation` (frameworks are re-signed by the team) and no `allow-unsigned-executable-memory` unless step 2 or Intel users show a need (Q16).
- **L4 — Build settings, not an entitlements file** (Xcode generates the entitlements from them).
- **L5 — Release from the dev Mac by script,** no CI (signing secrets stay in the user's Keychain).
- **L6 — Zip, not DMG.** `ditto -c -k --keepParent` of the stapled app. GitHub Releases serves it as is; a stapled app inside a zip passes Gatekeeper offline.
- **L7 — First public release is 1.0.1 (build 2).** Same features as the development-signed 1.0, but a new signature; the tag `v1.0` stays as the milestone tag. Every release bumps `CURRENT_PROJECT_VERSION` by 1.
- **L8 — License: MIT** for MMTVL's code (user choice 2026-10-06), `Copyright (c) 2026 Derek Wolcott`.
- **L9 — Notices file** inside the app at `MMTVL/Licenses/THIRD_PARTY_NOTICES.md` (bundled automatically), linked from the README. It starts with MMTVL's MIT license, then one section per component (name, version, license, copyright, source URL), then the full texts of each distinct license once (GPL-3.0, LGPL-3.0, LGPL-2.1, Apache-2.0, MPL-1.1, BSD-2-Clause, ISC, zlib, FTL, MIT variants), then the LGPL section (L10).
- **L10 — LGPL compliance text:** where the exact source is (MPVKit tag `1.0.0` and each build repo's release, plus the upstream project at that version), a written offer to send the source on request for three years (contact: the GitHub issues of `dwolcot1/mmtvl`), and how to replace a framework: copy the rebuilt `.framework` into `MMTVL.app/Contents/Frameworks`, then `codesign --force --deep -s - MMTVL.app` (ad hoc), then re-grant Accessibility.
- **L11 — Licenses page with QR codes** (*Design*): long license text isn't readable on a TV; the QR code hands it to a phone.
- **L12 — History rewrite (user choice 2026-10-06):** keep every commit, but replace the provider name, its URL pattern host and its CDN host with neutral text (`git filter-repo --replace-text` and `--replace-message`), and rewrite `user@example.com` to `57643254+dwolcot1@users.noreply.github.com` (`--mailmap`). Future commits use the noreply address (`git config user.email` in this repo).
- **L13 — Publish to a new repository.** Rename the current private repo to `dwolcot1/mmtvl-private` (kept private as the archive, with its PRs), create a new **private** `dwolcot1/mmtvl`, push the rewritten history there, and make it **public** only at the end (step 12). *Why:* GitHub keeps old PR commits reachable (*Research*).
- **L14 — Gitleaks with extra rules,** plus the user's real hosts supplied through an uncommitted local file, so the scan looks for the exact things that must not leak without writing them into the repo.
- **L15 — Defaults unchanged.** YouTube casting stays on and Reflector auto-start stays on (it only acts when Reflector is installed). The README says which ports MMTVL opens (8765/8766 phone remote, 8770 DIAL, UDP 1900) and how to switch each off.
- **L16 — Upgrade notes.** Release notes and the README say: after upgrading from a development-signed build (only the user's mini), remove MMTVL from Privacy & Security → Accessibility with "−" and add it again (or `tccutil reset Accessibility dev.mmtvl.launcher` and grant again), allow Local Network again if asked, and answer "Always Allow" to Keychain prompts, or remove the old items and enter the settings again.

## Implementation steps

Work on a branch first: `git switch -c m8-release`. Build after every app change (`xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build`) and run the step's tests. Steps marked **(with the user)** need the user's accounts or confirmation; never push, rename repos, change visibility or publish releases without the user's explicit OK in that moment.

- [ ] **1. Team and Developer ID certificate (with the user)**: no files unless L1 switches the team
  - Ask the user to open developer.apple.com → Account → Membership details and confirm the **Team ID** of the paid membership and that they are the **Account Holder** (only the Account Holder can create Developer ID certificates).
  - If it isn't `H846CY8RB4`: change `DEVELOPMENT_TEAM` in all four configurations of `project.pbxproj` (L1) and note it under *Deviations*.
  - The user creates the certificate: Xcode → Settings → Accounts → the team → Manage Certificates → **+** → **Developer ID Application**.
  - Install the tools: `brew install gitleaks git-filter-repo`.
  - Done when: `security find-identity -v -p codesigning` lists `Developer ID Application: … (<team>)`, and `gitleaks version` and `git filter-repo --version` print versions.

- [ ] **2. Hardened runtime**: `MMTVL.xcodeproj/project.pbxproj` (build settings only)
  - In the app target's Debug and Release configurations (`AA…42`, `AA…43`): `ENABLE_HARDENED_RUNTIME = YES;` and add `RUNTIME_EXCEPTION_ALLOW_JIT = YES;`. Don't touch the test target.
  - Build, run all tests.
  - Check: `codesign -dvv build/Build/Products/Debug/MMTVL.app 2>&1 | grep flags` shows `runtime`; `codesign -d --entitlements - --xml build/Build/Products/Debug/MMTVL.app` contains `com.apple.security.cs.allow-jit`.
  - Manual smoke test in `-windowed` mode and then kiosk mode (with the user, on the dev Mac): Live TV plays and rewinds (mpv); Multiview opens; YouTube loads and plays; the phone remote connects and controls another app (synthetic events); global Home works from another app (kiosk); Prime Video/a browser goes full screen (AX); a DIAL `curl` (CLAUDE.md) answers. Watch `log stream … category == "MPV"` for errors mentioning `lua`, `jit` or `mcode`.
  - If mpv logs JIT/Lua failures or crashes in LuaJIT: add `RUNTIME_EXCEPTION_ALLOW_UNSIGNED_EXECUTABLE_MEMORY = YES;`, retest, and record it under *Deviations* and in D33.
  - Done when: tests pass, the checks above hold, and the smoke test passes.

- [ ] **3. Licenses data and notices**: `MMTVL/Settings/ThirdPartyLicenses.swift` (new), `MMTVL/Licenses/THIRD_PARTY_NOTICES.md` (new), `LICENSE` (new), `MMTVLTests/ThirdPartyLicensesTests.swift` (new)
  - For each component in the *Design* table, find its real version and license at what MPVKit 1.0.0 ships: the build script names the build repo release (*Research*); each `mpvkit/<lib>-build` repo's build script or README names the upstream version. Read the upstream `COPYING`/`LICENSE` at that version (`gh api repos/<owner>/<repo>/contents/<file>?ref=<tag> -H "Accept: application/vnd.github.raw"`, or the project's site for non-GitHub projects). Fill `ThirdPartyComponent` values; where a license differs from *Research*, use the verified one and note it under *Deviations*.
  - `LICENSE`: the standard MIT text with `Copyright (c) 2026 Derek Wolcott`.
  - `THIRD_PARTY_NOTICES.md` per L9 and L10. Copy license texts verbatim from their official sources (gnu.org for GPL/LGPL, apache.org, opensource.org, the FreeType FTL from freetype.org, LuaJIT's COPYRIGHT). Don't paraphrase licenses.
  - Tests: ids unique; `all.first?.id == "mmtvl"` and the rest sorted by name; every `url` starts with `https://`; **every framework in `Bundle.main.privateFrameworksURL` (names without `.framework`) appears in exactly one component's `frameworks`** (drift guard: a new MPVKit version with a new library fails this test); `component(id:)` finds each; `Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")` exists, and its text contains every component's `name` and the strings `GNU LESSER GENERAL PUBLIC LICENSE` and `GNU GENERAL PUBLIC LICENSE`.
  - Done when: tests pass, and `ls build/Build/Products/Debug/MMTVL.app/Contents/Resources/THIRD_PARTY_NOTICES.md` exists after a build.

- [ ] **4. Settings → Licenses**: `MMTVL/Settings/SettingsTypes.swift`, `MMTVL/Settings/SettingsModel+Pages.swift`, `MMTVLTests/SettingsLicensesTests.swift` (new)
  - Add `SettingsPage.licenses` and `.license(id: String)`; fill `sections`, `pageTitle`, `pageImage` and `hint` per *Design*. Add the root row. No `SettingsEnvironment` change (static data).
  - Tests: the root row exists after `exit` and pushes `.licenses`; the Licenses page has one focusable row per component in order, with the license as value; Select on a row pushes `.license(id:)`; the detail page's image is `.qrCode(url)`, its only focusable row is `license.done`, and Select on it pops back to `.licenses`; an unknown id shows only Done; Back returns.
  - Done when: tests pass, and in `-windowed` mode Settings → Licenses → FFmpeg shows a QR code that a phone camera opens to the FFmpeg URL.

- [ ] **5. README and CLAUDE.md**: `README.md` (new), `CLAUDE.md`
  - README sections, in this order:
    1. One-paragraph description and a feature list (home screen, YouTube TV, Live TV with guide and Multiview, phone remote with trackpad, casting, Plex top shelf).
    2. Requirements: macOS 26 (Tahoe) or later; a Mac connected to a TV; Accessibility permission (global Home, controlling other apps); Local Network permission (Plex, casting).
    3. Install: download `MMTVL-<version>.zip` from the latest GitHub Release, unzip it, move `MMTVL.app` to Applications and open it. To update, quit MMTVL and replace the app the same way (settings stay).
    4. First run: kiosk mode, Exit to Desktop, ⌘Q, `-windowed`, where settings live (`~/Library/Application Support/MMTVL`), the Keychain items (service `dev.mmtvl.launcher`) and how to delete them.
    5. Network: ports 8765/8766 (phone remote), 8770 and UDP 1900 (YouTube casting), and the Settings switches for each (L15).
    6. Upgrading: L16's notes.
    7. **Unofficial and unaffiliated:** YouTube runs YouTube's TV web app (`youtube.com/tv`) with a TV user agent; it is not an official YouTube or Google app, may break when YouTube changes, and users are responsible for following YouTube's terms. MMTVL provides no TV channels: Live TV plays playlists and guides the user supplies, and users are responsible for using sources they're entitled to. Names such as YouTube, Plex, Prime Video, AirPlay and Reflector belong to their owners.
    8. Building from source: Xcode 27, `xcodebuild` commands from CLAUDE.md; set your own team (or sign ad hoc with `CODE_SIGN_IDENTITY=-`; then Accessibility must be granted again after each build).
    9. License: MIT (`LICENSE`), third-party notices (`MMTVL/Licenses/THIRD_PARTY_NOTICES.md`).
  - CLAUDE.md: in *Project setup notes*, the signing paragraph gains: hardened runtime with the allow-jit exception (L3); Debug = Apple Development, releases = Developer ID (L2); the release command `scripts/release.sh` and notary profile `mmtvl-notary`; the Licenses data/notices files and the drift test; the public repo and `mmtvl-private` (after step 10).
  - Done when: both files read correctly, and every command in the README works on the dev Mac.

- [ ] **6. Release tooling and a dry run (with the user)**: `scripts/release.sh`, `scripts/ExportOptions.plist` (new)
  - Write both per *Release flow*. `chmod +x scripts/release.sh`.
  - The user stores notarization credentials once: `xcrun notarytool store-credentials mmtvl-notary --apple-id <their Apple ID> --team-id <team>` and pastes an app-specific password when asked. Never echo or log it.
  - Run `scripts/release.sh` on the branch's committed state (version still 1.0). The guard rejects a non-`master` branch: for this dry run only, allow it with `MMTVL_RELEASE_ALLOW_BRANCH=1` (implement that override; document it in the script's header comment).
  - Done when: the script ends with an `Accepted` notarization, `stapler validate` passes, `spctl` reports `Notarized Developer ID`, and it prints a SHA-256. Keep `build/release/MMTVL-1.0.zip` for step 7; it isn't published.

- [ ] **7. Upgrade check on the Mac mini (with the user)**: no files (results in *Deviations* and L16 if they differ)
  - The mini runs the development-signed 1.0 (2026-10-06). The user quits it, replaces `/Applications/MMTVL.app` with the step 6 app (copied from the zip, so it's quarantined like a download) and launches it.
  - Record: does Gatekeeper open it with only the standard "downloaded from the Internet" prompt? Does the global Home key still work, or does Accessibility need removing and re-adding? Does macOS ask about Local Network again? Do Keychain prompts appear for the playlist URL, guides, PIN, Plex tokens and phones (how many, and does "Always Allow" stop them)? Does Launch at Login still start it after a restart?
  - Done when: the answers are recorded under *Deviations* (titled "Upgrade 1.0 → Developer ID"), L16's wording in the README matches what happened, and the mini runs the Developer ID build normally.

- [ ] **8. Secrets scan (with the user)**: `scripts/gitleaks.toml` (new)
  - `scripts/gitleaks.toml`: `[extend] useDefault = true` and rules:
    - `iptv-playlist-url`: `(?i)https?://[^\s"'<>]+/(get\.php|player_api\.php|xmltv\.php|app\d*/)[^\s"'<>]{8,}`;
    - `m3u-stream-token`: `(?i)https?://[^\s"'<>]+/[A-Za-z0-9_-]{32,}/[^\s"'<>]*\.(m3u8?|ts)`;
    - `credential-query`: `(?i)[?&](username|password|token|api_key|apikey)=[^&\s"'<>]{6,}`;
    - `plex-token`: `(?i)(X-Plex-Token|plex-token|accessToken)["'=:\s]+[A-Za-z0-9_-]{16,}`.
    - An `[allowlist]` for the test placeholders (`abc`, `tok\d+`, `example`, `<18-char token>`, `<43-char token>`).
  - Ask the user for their **real** playlist host, guide hosts, Plex server name and LAN subnet. Put them in an **uncommitted** file outside the repo (`$TMPDIR/mmtvl-private-terms.txt`, one per line). Never write them into the repo, a plan or a log.
  - Run:
    - `gitleaks git -v --redact --config scripts/gitleaks.toml --report-format json --report-path $TMPDIR/gitleaks-history.json .`
    - `gitleaks dir -v --redact --config scripts/gitleaks.toml .`
    - `git log --all -p | grep -n -i -F -f $TMPDIR/mmtvl-private-terms.txt | cut -c1-160`
  - Review each finding with the user. Placeholders and test fixtures are fine (add them to the allowlist). Any **real** secret (token, password, the real playlist path): stop and ask. The fix is to add it to step 9's replacement file **and** rotate it at the provider (a rewritten history doesn't un-leak a secret that was ever pushed to GitHub, even privately, so rotating is the safe default).
  - Done when: both scans report nothing outside the allowlist, the private-terms grep finds nothing except what step 9 will replace, and the user agrees. Commit `scripts/gitleaks.toml` only.

- [ ] **9. Rewrite the history in a fresh clone**: no files in the working copy (the rewrite happens in `$TMPDIR/mmtvl-public`)
  - Merge `m8-release` into `master` locally first (or finish the branch and merge its PR into the private repo), so the rewritten history contains M8's work so far.
  - `git clone --no-local /Users/user/Developer/mmtvl $TMPDIR/mmtvl-public` (a fresh clone, as filter-repo wants), then in it, for every remote branch you need, `git branch --track <name> origin/<name>` (at least `master`), and `git fetch origin 'refs/tags/*:refs/tags/*'`.
  - `$TMPDIR/replacements.txt` (order matters: longest first):
    ```
    regex:(?i)<CDN host>==>stream-cdn.example
    regex:(?i)<provider host>==>iptv.example
    regex:<provider name>==>the IPTV provider
    regex:(?i)\b<provider>\b==>the provider
    ```
    plus one line per real term from step 8 that must go (each `literal==>neutral`).
  - `$TMPDIR/mailmap.txt`: `Derek Wolcott <57643254+dwolcot1@users.noreply.github.com> <user@example.com>`
  - `git filter-repo --replace-text $TMPDIR/replacements.txt --replace-message $TMPDIR/replacements.txt --mailmap $TMPDIR/mailmap.txt`
  - Verify in `$TMPDIR/mmtvl-public`:
    - `git log --all -p | grep -c -i the provider` → 0; same for `fastly`, `protonmail` and every private term (`grep -i -F -f`);
    - `git log --all --format='%ae %ce' | sort -u` shows only the noreply address, `noreply@anthropic.com` (co-author trailers are in messages, not authors) and GitHub's `noreply@github.com` (merge commits);
    - read the rewritten wording in `docs/plans/MASTER_PLAN.md` §3 and `docs/plans/archive/M4-live-tv.md`: if a sentence reads badly ("the provider TV"), fix it in a normal commit after step 10, not by rewriting again;
    - build and run all tests there (`xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`); the test fixtures that used the provider host now use `iptv.example` and must still pass;
    - re-run step 8's gitleaks commands there: clean.
  - Done when: all checks pass. Nothing has been pushed.

- [ ] **10. Switch to the new repository (with the user)**: no files
  - Confirm each command with the user before running it:
    1. `gh repo rename mmtvl-private -R dwolcot1/mmtvl` (stays private; PRs stay there).
    2. `gh repo create dwolcot1/mmtvl --private --description "Full-screen TV launcher for a Mac driven by a remote, keyboard or phone"`.
    3. In `$TMPDIR/mmtvl-public`: `git remote add origin https://github.com/dwolcot1/mmtvl.git`, `git push -u origin master`, `git push origin --tags`.
  - Repoint the working copy (it holds the old history):
    1. `git stash push MMTVL.xcodeproj/xcshareddata/xcschemes/MMTVL.xcscheme` (the user's local scheme tweak) if it's still modified;
    2. `git remote set-url origin https://github.com/dwolcot1/mmtvl.git`; add the archive as `git remote add private https://github.com/dwolcot1/mmtvl-private.git`;
    3. `git fetch origin --prune --tags --force`; `git switch master`; `git reset --hard origin/master`; delete local branches that only exist in the old history;
    4. `git stash pop`;
    5. `git config user.email 57643254+dwolcot1@users.noreply.github.com` (this repo only).
  - Done when: `git log -1` in the working copy matches the new remote, `git log --all -p | grep -c -i the provider` is 0 in the working copy (after `git stash pop` no ref points into the old history; if a stash or old tag remains, drop it), a Debug build and all tests pass, and `gh repo view dwolcot1/mmtvl --json visibility` says `PRIVATE`.

- [ ] **11. Version 1.0.1 and the release build (with the user)**: `MMTVL.xcodeproj/project.pbxproj` (build settings only)
  - `MARKETING_VERSION = 1.0.1;` and `CURRENT_PROJECT_VERSION = 2;` in all four configurations (L7). Commit on `master` ("Version 1.0.1"), push after the user confirms.
  - `scripts/release.sh` → `build/release/MMTVL-1.0.1.zip` and its SHA-256.
  - Tag and draft release (confirm first): `git tag -a v1.0.1 -m "MMTVL 1.0.1"`, `git push origin v1.0.1`, `gh release create v1.0.1 build/release/MMTVL-1.0.1.zip --draft --title "MMTVL 1.0.1" --notes-file <notes>`. Notes: first signed and notarized release; install lines; L16's upgrade notes; checksum.
  - Done when: the draft release has the zip, and a download of the asset (`gh release download v1.0.1 -D $TMPDIR/dl`) has the printed SHA-256.

- [ ] **12. Go public (with the user)**: no files
  - Last checks before the switch: step 8's scans are clean on `origin/master` of the new repo; README and LICENSE are present; the draft release is ready.
  - Confirm, then `gh repo edit dwolcot1/mmtvl --visibility public --accept-visibility-change-consequences`, then `gh release edit v1.0.1 --draft=false`.
  - Verify the public download without touching the dev Mac's Debug setup (L2): in a private browser window (signed out of GitHub), open `https://github.com/dwolcot1/mmtvl/releases/latest`, download the zip, and check `shasum -a 256` matches step 11's. Don't run it on the dev Mac.
  - On the Mac mini (with the user): download the zip from the release page in a browser (so it's quarantined like any user's download), quit MMTVL, replace `/Applications/MMTVL.app`, open it. It opens after only the standard "downloaded from the Internet" confirmation and keeps its grants (same Developer ID identity as step 7).
  - Done when: the repo and release are public, the anonymous download's checksum matches, and the mini runs the downloaded 1.0.1.

- [ ] **13. Docs and status**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - CLAUDE.md: the repo is public at `dwolcot1/mmtvl` (archive `mmtvl-private`); the release checklist in four lines (bump version and build → commit → `scripts/release.sh` → tag + `gh release create` with the zip and checksum); commit email is the noreply address.
  - Master plan: §3 *Distribution* row → "Developer ID + notarized zip on GitHub Releases; Debug builds Apple Development (D33)"; M8 → `Done`; resolve Q16 if step 2 or a user report answered it, Q17 with step 7's findings, Q5 (the public name is MMTVL).
  - Done when: the docs match what was done.

## Tests

- New: `MMTVLTests/ThirdPartyLicensesTests.swift` (data integrity, the framework drift guard, the bundled notices file), `MMTVLTests/SettingsLicensesTests.swift` (root row, list page, detail page, QR image, Done/Back).
- Every app change: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test` (all tests; they must pass with the hardened runtime on, step 2).
- One suite: `-only-testing:'MMTVLTests/ThirdPartyLicensesTests'`.
- Release checks are in `scripts/release.sh` itself (signature, entitlements, notarization, stapling, Gatekeeper).

## Manual verification

- [ ] Debug build with the hardened runtime: Live TV, Multiview, rewind, YouTube, phone remote (keys, text, trackpad), global Home, AX full screen of an external app and DIAL casting all work; no LuaJIT/JIT errors in the MPV log.
- [ ] Settings → Licenses lists every component; each detail page's QR code opens the right page on a phone; Done and Back return.
- [ ] `MMTVL.app/Contents/Resources/THIRD_PARTY_NOTICES.md` exists in the release build and reads correctly.
- [ ] `scripts/release.sh` produces a notarized, stapled zip; `spctl` says `Notarized Developer ID`.
- [ ] Mini upgrade 1.0 → Developer ID: Gatekeeper, Accessibility, Local Network, Keychain prompts and Launch at Login recorded (step 7), README matches.
- [ ] Secrets scans clean; the public history has no provider name, CDN host, personal email or private terms.
- [ ] `github.com/dwolcot1/mmtvl` is public with README and LICENSE; `mmtvl-private` is private and keeps the old PRs.
- [ ] The 1.0.1 zip downloaded from the public release page opens on the mini after only the standard "downloaded from the Internet" confirmation.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| H846CY8RB4 is the free personal team and the paid membership is a different team | Step 1: Membership shows another Team ID, or no Developer ID option | Switch the team (L1); one Accessibility re-grant on the dev Mac. |
| The user isn't the Account Holder | Developer ID option greyed out | The Account Holder creates the certificate, or uses Xcode cloud-managed Developer ID signing during export (`-allowProvisioningUpdates`). |
| LuaJIT fails or crashes under the hardened runtime | Step 2: MPV log errors, crash in `Libluajit` | Add `RUNTIME_EXCEPTION_ALLOW_UNSIGNED_EXECUTABLE_MEMORY` (IINA's choice); record in D33. |
| Another hardened-runtime problem (WKWebView, a framework) | Step 2 smoke test | Add only the specific exception the crash or log names; never `disable-library-validation` without a reason recorded in D33. |
| Notarization rejected | `status: Invalid` | `xcrun notarytool log <id> --keychain-profile mmtvl-notary`; typical causes: an unsigned or non-timestamped framework, `get-task-allow` present (a Debug export). Fix and re-run. |
| Keychain prompts after the identity change are hard to answer from the couch | Step 7: several prompts at launch | "Always Allow" once with a keyboard; or delete the items (CLAUDE.md commands) and re-enter the settings. Record in Q17 and the README. |
| Accessibility shows MMTVL as enabled but Home doesn't work | Step 7 | Remove MMTVL with "−" in Privacy & Security → Accessibility and add it again; or `tccutil reset Accessibility dev.mmtvl.launcher`. Already in L16. |
| A real secret is found in history | Step 8 | Stop; rotate it at the provider; add it to the replacements; rescan. |
| The rewrite breaks tests (a replacement changed code meaning) | Step 9 tests fail | Narrow the replacement (more specific regex) and redo step 9 from a fresh clone. |
| An old commit leaks via forks or caches of the private repo | — | The private repo was never public; L13 keeps its PRs private. |
| A user on Intel reports Lua or playback problems | GitHub issue | Q16: add `allow-unsigned-executable-memory` in a point release. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
- **2026-10-09, from M7c step 27 (question for when M8 starts):** M7c set `MARKETING_VERSION = 1.1.0`, and every test build for the mini bumps `CURRENT_PROJECT_VERSION` (`scripts/test-build.sh`), so by M8 the build number will be well past 2. L7 (1.0.1, build 2) and step 11 need new numbers: probably the version at that time (1.1.x) and the next build number. `scripts/release.sh` should keep incrementing the same counter, never reset it.
