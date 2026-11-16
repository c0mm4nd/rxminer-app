# RxMiner App

A graphical interface for [RxMiner](https://github.com/c0mm4nd/rxminer) on
multiple devices: one Flutter app for Windows, macOS, Linux, Android and iOS.
The interface uses a single monospace family, a VS Code-inspired palette,
square panels, tree-style sections and a status bar.

The miner runs as a library inside the app process, not as a separate
command-line process. `packages/rxminer/` is a standalone Dart package: a Rust
FFI crate depends on a pinned upstream `rxminer` commit and is compiled by a
Dart build hook; mining, Stratum, configuration parsing and the HTTP API are all
upstream code. The app reads hashrate and shares, pauses and resumes through the
miner's own HTTP API, and follows its log file.

## Launch configuration

The miner is embedded in the app process and has no command line, so every
launch option is edited in the app's interface. Before every save the app checks
the configuration with rxminer's own parser, exactly as the session would run
(equivalent to `--dry-run`), and shows rxminer's error unchanged.

- **Settings › All configuration options**: lists every `config.json` key,
  grouped by CPU, RandomX, connection, HTTP API, HTTP API TLS, logging and
  runtime, and benchmarking. Each row shows the name, default value and allowed
  range and can be reset individually; options the current system does not
  support (such as Linux-only 1 GiB pages, MSR and battery pause) are marked.
  Thread count and CPU affinity live in `cpu.rx`, for example
  `{"threads": 4, "affinity": "0xF"}`; the Worker threads shortcut on the
  settings page writes there too.
- **Pools**: every pool option, including the SOCKS5 proxy, CA certificate file
  and keepalive.
- **Settings › Edit config.json**: edit the raw file directly.

`config.json` uses the same format as the command-line rxminer, and files can be
copied between the two. Only two options have no `config.json` key: a proxy
shared by all pools (`--proxy`, also used for developer-fee connections) and
"ignore proxy environment variables" (`--no-proxy`). Both live in the Connection
group, are stored in the app's own settings and are passed to the miner at
start. Options upstream requires to stay at their defaults (`cpu.enabled`,
`randomx.cache_qos`, and each pool's daemon / self-select / submit-to-origin)
are not in the form but remain visible in the raw JSON.

Every key reaches the miner unchanged. The app adds only two things: when `http`
is not enabled in the configuration, a private API bound to 127.0.0.1 with a
random port and token for each launch; and when `log-file` is unset, its own
log. When the user enables their own API, the app connects to it directly
(`0.0.0.0` is rewritten to 127.0.0.1, and a self-signed certificate is accepted
for loopback only); the pause button is disabled while `http.restricted` is
true. With `watch` enabled, saving the configuration while mining makes the
miner reload it; the `cpu.rx` file written by `autosave` is synced back into
`config.json`.

`background` has no effect in the app (the miner runs in the app process);
battery pause, 1 GiB pages and MSR are Linux only.

## Platforms

| Platform | Release file | Notes |
| --- | --- | --- |
| Windows 10+ x64 | `RxMiner-<version>-windows-x64.zip` | Unzip and run `RxMiner.exe` |
| macOS (Apple silicon and Intel) | `RxMiner-<version>-macos-universal.zip` | Not notarized; right-click to open the first time, or remove the quarantine attribute |
| Linux x64 / arm64 | `RxMiner-<version>-linux-<arch>.tar.gz` | Requires GTK 3; run `rxminer-app` |
| Android | `RxMiner-<version>-android-<ABI>.apk` | Most phones use `arm64-v8a` |
| iOS | `RxMiner-<version>-ios-unsigned.ipa` | Unsigned; sign with your own Apple ID using AltStore, SideStore or Sideloadly |

Phones do not report available memory to the miner, and `auto` would select the
2.3 GiB dataset, so Android and iOS default to light mode with huge pages off.
Mining runs only while the app is open; there is no background service. Neither
Google Play nor the App Store allows apps that mine on device, so mobile builds
are distributed through GitHub Releases only.

The upstream miner keeps a developer fee below 1%, mined to pool.hashvault.pro,
pool.hashvault.sh and xmr-hk.kryptex.network. The app lists these hosts before
mining starts.

### iOS limitations

- **Sideloading only.** App Store Review Guideline 2.4.2 prohibits apps that
  mine on device, and TestFlight requires the same review. Released IPA files
  are unsigned and must be signed with your own Apple ID using AltStore,
  SideStore or Sideloadly; free-account signatures expire after 7 days and need
  periodic re-signing.
- **No JIT.** iOS does not allow ordinary apps to create executable memory, so
  the app always disables `randomx.jit` and RandomX runs in the interpreter.
  Measured on an Apple-silicon Mac in light mode with 2 threads: 7.3 H/s
  interpreted versus 110.6 H/s with JIT, roughly 15 times slower.
- **Memory and background.** The system terminates apps that use too much
  memory, so light mode is the default; a few seconds after the app goes to the
  background its process is suspended and mining pauses.

The iOS build has been launched in the simulator with the native library
loaded, but mining has not yet been verified on a physical device.

## Building

Flutter 3.50 and rustup are required (the build hook installs 1.100.0 and the
targets from `rust-toolchain.toml`).

```sh
cd packages/rxminer && dart test          # includes one real native benchmark
cd apps/miner && flutter analyze && flutter test
flutter build macos --release             # or windows / linux / apk / ios --no-codesign
```

## Versioning

The version is `<rxminer version>.<app revision>`, for example `0.2.0.1`: the
first three parts always match the embedded rxminer version, and the fourth is
the app's own release number for that rxminer version, restarting at 1 when
rxminer is upgraded. The single source of truth is `version: 0.2.0+1` in
`apps/miner/pubspec.yaml`. `scripts/version.py check` verifies it against the
rxminer version locked in `Cargo.lock`, the version shown in the interface and
the commit hash; CI runs it on every push.

To publish a new version:

```sh
# 1. Bump the version in pubspec.yaml (when upgrading rxminer, also change the
#    rev in Cargo.toml, run cargo update -p rxminer, and update brand.dart)
python3 scripts/version.py check
git commit -am "Release 0.2.0.2"
git tag v0.2.0.2 && git push origin main v0.2.0.2
```

## Releases

After a tag is pushed, `.github/workflows/release.yml` first checks that the tag
matches the version, then builds on GitHub-hosted runners for Windows, macOS
(macOS and iOS), Linux x64, Linux arm64 and Ubuntu (Android). When every build
succeeds it publishes the Release automatically with `SHA256SUMS`. The release
body combines the rxminer version line, `docs/RELEASE_NOTES.md` and an
automatically generated changelist; tags containing `-` (such as
`v0.2.0.2-beta.1`) are published as pre-releases. Running the workflow manually
builds the artifacts without publishing. `ci.yml` runs the version check,
analysis and tests on every push and pull request.

Android's versionCode is derived from the version (`0.2.0.1` → 200001) and only
increases across rxminer versions, so upgrades can overwrite earlier installs.

Android releases need signing keys in the repository Secrets; without a key,
tagged builds fail instead of publishing a debug-signed APK that cannot be
upgraded:

```sh
keytool -genkeypair -v -keystore release.jks -alias rxminer -keyalg RSA -keysize 4096 -validity 10000
base64 -i release.jks | pbcopy     # paste into ANDROID_KEYSTORE_BASE64
```

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | base64-encoded `release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | for example `rxminer` |
| `ANDROID_KEY_PASSWORD` | key password |

Back up `release.jks`: if it is lost, existing users cannot upgrade to new
versions.
