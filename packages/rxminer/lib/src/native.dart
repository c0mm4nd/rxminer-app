import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// Raised when the native miner rejects arguments or configuration.
class MinerException implements Exception {
  const MinerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// CPU and memory as the miner's own topology code sees them.
class DeviceInfo {
  const DeviceInfo({
    required this.logical,
    required this.selected,
    required this.nodes,
    required this.summary,
    required this.memory,
    required this.jit,
    required this.arch,
    required this.os,
  });
  factory DeviceInfo.fromJson(Map<String, Object?> json) => DeviceInfo(
    logical: json['logical'] as int,
    selected: json['selected'] as int,
    nodes: json['nodes'] as int,
    summary: json['summary'] as String,
    memory: json['memory'] as int?,
    jit: json['jit'] as bool,
    arch: json['arch'] as String,
    os: json['os'] as String,
  );

  /// Usable CPUs, and those chosen by default (physical cores).
  final int logical, selected;

  /// NUMA nodes.
  final int nodes;
  final String summary;

  /// Available memory in bytes, or null when the platform does not say.
  final int? memory;

  /// Whether this build has a RandomX JIT for the CPU architecture.
  final bool jit;
  final String arch, os;
}

/// What the miner would do with a set of arguments.
class CheckResult {
  const CheckResult({required this.threads, required this.benchmark});

  /// Worker threads it would start.
  final int threads;

  /// Whether it would run an offline benchmark instead of mining.
  final bool benchmark;
}

/// Lifecycle of the in-process session.
class MinerState {
  const MinerState({required this.running, required this.stopping, this.error});
  factory MinerState.fromJson(Map<String, Object?> json) => MinerState(
    running: json['running'] as bool,
    stopping: json['stopping'] as bool,
    error: json['error'] as String?,
  );
  static const idle = MinerState(running: false, stopping: false);
  final bool running, stopping;

  /// Why the last session ended, when it did not end cleanly.
  final String? error;
}

Map<String, Object?> _decode(Pointer<Utf8> result) {
  try {
    final json = jsonDecode(result.toDartString()) as Map<String, Object?>;
    final error = json['error'];
    if (error is String) throw MinerException(error);
    return json;
  } finally {
    rxminerFree(result);
  }
}

Map<String, Object?> _withArgs(
  List<String> args,
  Pointer<Utf8> Function(Pointer<Utf8>) action,
) {
  final text = jsonEncode(args).toNativeUtf8();
  try {
    return _decode(action(text));
  } finally {
    malloc.free(text);
  }
}

/// The native miner. One session runs at a time, in this process.
///
/// Arguments are RxMiner command-line flags without the program name, for
/// example `['-c', '/path/config.json']`. They are parsed by upstream code.
abstract final class RxMiner {
  static DeviceInfo device() => DeviceInfo.fromJson(_decode(rxminerDevice()));

  /// Validates like `--dry-run`.
  static CheckResult check(List<String> args) {
    final json = _withArgs(args, rxminerCheck);
    return CheckResult(
      threads: json['threads'] as int,
      benchmark: json['benchmark'] as bool,
    );
  }

  /// Starts mining or a benchmark on a native thread and returns at once.
  static void start(List<String> args) => _withArgs(args, rxminerStart);

  /// Asks the session to stop. Poll [state] until it is no longer running.
  static void stop() => _decode(rxminerStop());

  static MinerState state() => MinerState.fromJson(_decode(rxminerState()));
}
