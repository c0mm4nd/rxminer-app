Desktop and mobile builds of the RxMiner app. Check downloads against `SHA256SUMS`.

| File | System |
| --- | --- |
| `RxMiner-*-windows-x64.zip` | Windows 10 or later, x64. Unzip and run `RxMiner.exe`. |
| `RxMiner-*-macos-universal.zip` | macOS, Apple silicon and Intel. |
| `RxMiner-*-linux-x64.tar.gz`, `linux-arm64` | Linux with GTK 3. Extract and run `rxminer-app`. |
| `RxMiner-*-android-arm64-v8a.apk` | Most Android phones. `armeabi-v7a` and `x86_64` are for older phones and emulators. |
| `RxMiner-*-ios-unsigned.ipa` | iOS, sideloaded with AltStore, SideStore or Sideloadly. iOS allows no JIT, so hashing is much slower. |

The macOS app is not notarized. After unzipping, run
`xattr -dr com.apple.quarantine RxMiner.app` or open it once with Control-click › Open.
Windows SmartScreen may warn about an unsigned app.

The miner keeps its developer fee of under 1% of hashing time, mined to
pool.hashvault.pro, pool.hashvault.sh and xmr-hk.kryptex.network.
