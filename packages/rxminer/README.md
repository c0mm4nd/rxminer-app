# rxminer

Embeds the [RxMiner](https://github.com/c0mm4nd/rxminer) RandomX miner in Dart
and Flutter apps. The package has no application dependency.

The native library is a thin FFI crate (`native/`) over the upstream `rxminer`
crate, pinned to commit `6882dfb`. Mining, Stratum, configuration parsing and
the HTTP API are upstream code; the crate only owns one session thread. It is
built by a Dart build hook with `native_toolchain_rust`, so `rustup` must be
installed. Toolchain 1.100.0 and its targets are pinned in
`native/rust-toolchain.toml`.

```dart
RxMiner.device();                       // CPU and memory as the miner sees them
RxMiner.check(['-c', path]);            // like --dry-run: threads, benchmark
RxMiner.start(['-c', path]);            // returns at once; one session at a time
RxMiner.state();                        // running, stopping, last error
RxMiner.stop();                         // poll state() until it ends
```

Arguments are the command-line miner's flags without the program name.
`planSession` turns a user configuration into the file a session runs with:
every key passes through, except that a private API on 127.0.0.1 is added when
`http` is not enabled and a log file when `log-file` is unset. It returns the
API endpoint to read (the user's own, if configured) and the log to follow.
Pass `allowJit: false` on iOS, where apps cannot map executable memory.
`MinerApi` reads `/summary` and sends pause and resume; `LogTail` follows the
log.

The miner keeps its developer fee of under 1%, mined to fixed endpoints in
upstream `src/developer.rs`. Platform limits are upstream's: battery pause,
1 GiB pages and MSR tuning need Linux, and Android and iOS do not report free
memory, so `auto` memory mode selects the 2.3 GiB dataset there.

Tests: `dart test` (runs a short native benchmark).
