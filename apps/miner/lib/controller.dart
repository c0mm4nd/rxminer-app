import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:rxminer/rxminer.dart';

import 'store.dart';

enum Phase { idle, mining, benchmark }

/// Owns the native session: starts it, polls its API and log, and stops it.
class MinerController extends ChangeNotifier {
  MinerController(this.store);
  final MinerStore store;

  bool loading = true;
  String? loadFailure;
  DeviceInfo? device;
  String? deviceError;

  Phase phase = Phase.idle;
  MinerState state = MinerState.idle;
  Summary? summary;

  /// Why the last session ended, or why it could not start.
  String? failure;

  /// 10-second hashrate, sampled once a second while running.
  final samples = <double>[];
  static const sampleLimit = 300;

  late LogTail log = LogTail(store.logFile);
  SessionPlan? plan;
  MinerApi? _api;
  int _port = 0;
  String _token = '';
  String? _sessionText;
  Timer? _timer;
  bool _polling = false;
  int _ticks = 0;
  bool busy = false;

  bool get running => state.running;
  bool get paused => summary?.paused ?? false;

  /// Whether this session's API accepts pause and resume.
  bool get canControl => plan?.api.control ?? false;

  /// Whether saving the configuration now reloads the running session.
  bool get liveReload => running && store.config['watch'] != false;

  /// A pool or a configured benchmark gives Start something to do.
  bool get canStart {
    final bench = store.config['benchmark'];
    return enabledPools.isNotEmpty ||
        (bench is Map && (bench['size'] != null || bench['seconds'] != null));
  }

  List<PoolEntry> get enabledPools => [
    for (final pool in store.pools)
      if (pool.enabled && pool.url.isNotEmpty && pool.user.isNotEmpty) pool,
  ];

  Future<void> load() async {
    try {
      await store.load();
    } catch (error) {
      loadFailure = 'Could not read the saved configuration: $error';
    }
    try {
      device = RxMiner.device();
    } catch (error) {
      deviceError = '$error';
    }
    try {
      state = RxMiner.state();
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  SessionPlan _plan(Map<String, Object?> config, {int? port, String? token}) =>
      planSession(
        config,
        port: port ?? _port,
        token: token ?? _token,
        logFile: store.logFile.path,
        allowJit: jitAllowed,
      );

  /// Checks [config] and [proxy] with the miner's own parser, exactly as a
  /// session would run them. Without a pool, mining options are checked
  /// through a one-second benchmark so the rest can still be validated.
  /// Throws [MinerException] with the miner's message.
  Future<CheckResult> check(
    Map<String, Object?> config, {
    ProxySettings? proxy,
    List<String> more = const [],
    bool forStart = false,
  }) async {
    final flags = [...(proxy ?? store.proxy).flags, ...more];
    await store.checkFile.writeAsString(
      jsonEncode(_plan(config, port: 1, token: 'check').config),
    );
    try {
      final run = ['-c', store.checkFile.path, ...flags];
      try {
        return RxMiner.check(run);
      } on MinerException catch (error) {
        if (forStart || !error.message.contains('pools[].user is required')) {
          rethrow;
        }
        RxMiner.check([...run, '--benchmark-seconds', '1']);
        return const CheckResult(threads: 0, benchmark: false);
      }
    } finally {
      if (await store.checkFile.exists()) await store.checkFile.delete();
    }
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _newToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 24; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  Future<void> _writeSession() async {
    final current = _plan(store.config);
    final text = jsonEncode(current.config);
    await MinerStore.write(store.sessionFile, text);
    _sessionText = text;
    plan = current;
  }

  /// Starts mining, or a benchmark when [benchmark] seconds are given or the
  /// configuration and arguments describe one.
  Future<void> start({int? benchmark}) async {
    if (running || busy) return;
    busy = true;
    failure = null;
    notifyListeners();
    try {
      final more = [
        if (benchmark != null) ...['--benchmark-seconds', '$benchmark'],
      ];
      final flags = [...store.proxy.flags, ...more];
      final checked = await check(store.config, more: more, forStart: true);
      _port = await _freePort();
      _token = _newToken();
      await _writeSession();
      final logFile = File(plan!.logFile);
      log = LogTail(logFile);
      if (logFile.path == store.logFile.path) {
        if (await logFile.exists()) await logFile.writeAsString('');
      } else {
        // The user's own log: show only what this session adds.
        await log.skipExisting();
      }
      samples.clear();
      summary = null;
      RxMiner.start(['-c', store.sessionFile.path, ...flags]);
      _api?.close();
      _api = MinerApi(plan!.api);
      phase = checked.benchmark ? Phase.benchmark : Phase.mining;
      state = RxMiner.state();
      _ticks = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    } on MinerException catch (error) {
      failure = error.message;
    } catch (error) {
      failure = 'Could not start the miner: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      state = RxMiner.state();
      if (state.running && !state.stopping) {
        try {
          summary = await _api?.summary();
          samples.add(summary?.hashrate.s10 ?? 0);
          if (samples.length > sampleLimit) samples.removeAt(0);
        } catch (_) {
          // The API listens once the session has prepared CPUs and memory.
        }
      }
      await log.poll();
      if (++_ticks % 5 == 0) await _syncAutosave();
      if (!state.running) {
        _timer?.cancel();
        _timer = null;
        _api?.close();
        _api = null;
        failure = state.error;
        phase = Phase.idle;
      }
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  /// Autosave writes the selected CPUs to cpu.rx in the file the miner was
  /// given. Carry that one value back to the user's configuration.
  Future<void> _syncAutosave() async {
    if (store.config['autosave'] == false) return;
    final file = store.sessionFile;
    if (!await file.exists()) return;
    final text = await file.readAsString();
    if (text == _sessionText) return;
    _sessionText = text;
    try {
      final rx = ((jsonDecode(text) as Map)['cpu'] as Map?)?['rx'];
      if (rx == null) return;
      final config = (jsonDecode(jsonEncode(store.config)) as Map)
          .cast<String, Object?>();
      final cpu = (config['cpu'] as Map?)?.cast<String, Object?>() ?? {};
      if (jsonEncode(cpu['rx']) == jsonEncode(rx)) return;
      config['cpu'] = {...cpu, 'rx': rx};
      await store.saveConfig(config);
    } catch (_) {
      // A half-written file is picked up on the next pass.
    }
  }

  void stop() {
    if (!running) return;
    RxMiner.stop();
    state = RxMiner.state();
    notifyListeners();
  }

  Future<void> setPaused(bool value) async {
    final api = _api;
    if (api == null) return;
    try {
      value ? await api.pause() : await api.resume();
      summary = await api.summary();
    } catch (error) {
      failure = 'The miner did not accept the request: $error';
    }
    notifyListeners();
  }

  /// Saves [config]. With reload on save, a running session picks it up.
  Future<void> saveConfig(Map<String, Object?> config) async {
    await store.saveConfig(config);
    if (liveReload) {
      await _writeSession();
      _api?.close();
      _api = MinerApi(plan!.api);
    }
    notifyListeners();
  }

  Future<void> savePools(List<PoolEntry> pools) => saveConfig({
    ...store.config,
    'pools': [for (final pool in pools) pool.json],
  });

  Future<void> setTheme(String value) async {
    store.theme = value;
    await store.saveSettings();
    notifyListeners();
  }

  Future<void> setProxy(ProxySettings value) async {
    store.proxy = value;
    await store.saveSettings();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.close();
    if (running) RxMiner.stop();
    super.dispose();
  }
}
