import 'dart:convert';
import 'dart:io';

import 'package:rxminer/rxminer.dart';

bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// iOS gives apps no writable executable memory, so RandomX runs interpreted.
bool get jitAllowed => !Platform.isIOS;

/// The two miner options config.json has no key for. They are kept in the
/// app's settings and given to the miner with the configuration.
class ProxySettings {
  ProxySettings({this.proxy = '', this.noProxy = false});
  factory ProxySettings.fromJson(Map json) => ProxySettings(
    proxy: json['proxy'] as String? ?? '',
    noProxy: json['no-proxy'] as bool? ?? false,
  );

  /// SOCKS5 host:port or an http:// CONNECT URL for every pool, including
  /// the developer-fee pools. Empty uses pools[].socks5 or the environment.
  String proxy;

  /// Ignore ALL_PROXY and HTTPS_PROXY from the environment.
  bool noProxy;

  Map<String, Object?> toJson() => {'proxy': proxy, 'no-proxy': noProxy};

  List<String> get flags => [
    if (proxy.trim().isNotEmpty) ...['--proxy', proxy.trim()],
    if (noProxy) '--no-proxy',
  ];
}

/// Worker threads described by a cpu.rx value: a CPU list, an object with a
/// thread count, or null for automatic. A named profile reports null.
int? profileThreads(Object? rx) => switch (rx) {
  List list => list.length,
  Map map => (map['threads'] as num?)?.toInt(),
  _ => null,
};

/// One pool entry. Keys the app does not edit are kept as they were.
class PoolEntry {
  PoolEntry(this.json);
  PoolEntry.empty() : json = {'url': '', 'user': '', 'pass': 'x', 'tls': true};
  final Map<String, Object?> json;

  String _text(String key, [String fallback = '']) =>
      json[key] as String? ?? fallback;
  void _set(String key, Object? value) =>
      value == null || value == '' ? json.remove(key) : json[key] = value;

  String get url => _text('url');
  set url(String v) => json['url'] = v.trim();
  String get user => _text('user');
  set user(String v) => json['user'] = v.trim();
  String get pass => _text('pass', 'x');
  set pass(String v) => json['pass'] = v;
  String get rigId => _text('rig-id');
  set rigId(String v) => _set('rig-id', v.trim());
  String get fingerprint => _text('tls-fingerprint');
  set fingerprint(String v) => _set('tls-fingerprint', v.trim());
  bool get enabled => json['enabled'] as bool? ?? true;
  set enabled(bool v) => json['enabled'] = v;
  bool get tls => json['tls'] as bool? ?? false;
  set tls(bool v) => json['tls'] = v;
  bool get tlsVerify => json['tls-verify'] as bool? ?? false;
  set tlsVerify(bool v) => json['tls-verify'] = v;
  bool get nicehash => json['nicehash'] as bool? ?? false;
  set nicehash(bool v) => json['nicehash'] = v;

  /// The host and port, without any scheme, for display.
  String get host {
    final i = url.indexOf('://');
    return i < 0 ? url : url.substring(i + 3);
  }

  /// TLS is chosen by the flag or by a `stratum+ssl://` style scheme.
  bool get secure => tls || RegExp(r'^[a-z+]*(ssl|tls)://').hasMatch(url);

  PoolEntry copy() =>
      PoolEntry((jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>());
}

/// Files in the app's support directory. `config.json` is RxMiner's own
/// format and can be copied to and from the command-line miner unchanged.
class MinerStore {
  MinerStore(this.dir);
  final Directory dir;

  File get configFile => File('${dir.path}/config.json');
  File get settingsFile => File('${dir.path}/settings.json');
  File get sessionFile => File('${dir.path}/session.json');
  File get checkFile => File('${dir.path}/check.json');
  File get logFile => File('${dir.path}/miner.log');

  Map<String, Object?> config = initialConfig();
  String theme = 'system';
  ProxySettings proxy = ProxySettings();

  /// Starting point for new installations. Phones cannot report free memory
  /// to the miner, so they start in light mode instead of the 2.3 GiB dataset.
  static Map<String, Object?> initialConfig() {
    final config = defaultConfig();
    if (isMobile) {
      (config['randomx'] as Map)['mode'] = 'light';
      (config['cpu'] as Map)['huge-pages'] = false;
    }
    return config;
  }

  List<PoolEntry> get pools => [
    for (final pool in (config['pools'] as List? ?? const []))
      if (pool is Map) PoolEntry(pool.cast<String, Object?>()),
  ];

  Map<String, Object?> section(String name) {
    final value = config[name];
    if (value is Map<String, Object?>) return value;
    final created = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    config[name] = created;
    return created;
  }

  Future<void> load() async {
    await dir.create(recursive: true);
    if (await configFile.exists()) {
      final json = jsonDecode(await configFile.readAsString());
      if (json is! Map) {
        throw const FormatException('config.json is not an object');
      }
      config = json.cast<String, Object?>();
    }
    if (await settingsFile.exists()) {
      final json = jsonDecode(await settingsFile.readAsString()) as Map;
      theme = json['theme'] as String? ?? 'system';
      final saved = json['proxy'];
      if (saved is Map) proxy = ProxySettings.fromJson(saved);
      await _migrate(json);
    }
  }

  /// Settings from 0.1.0 development builds kept threads, CPU affinity and
  /// verbose outside config.json. Move them into it, without overriding keys
  /// the user already set there.
  Future<void> _migrate(Map json) async {
    final old = json['args'] is Map ? json['args'] as Map : json;
    if (old['proxy'] is String) proxy = ProxySettings.fromJson(old);
    final threads = old['threads'] as int?;
    final affinity = (old['cpu-affinity'] as String? ?? '').trim();
    final next = (jsonDecode(jsonEncode(config)) as Map)
        .cast<String, Object?>();
    var changed = false;
    final cpu = (next['cpu'] as Map?)?.cast<String, Object?>() ?? {};
    if (threads != null && cpu['rx'] == null) {
      cpu['rx'] = {
        'threads': threads,
        if (affinity.isNotEmpty) 'affinity': affinity,
      };
      next['cpu'] = cpu;
      changed = true;
    }
    if (old['verbose'] == true && next['verbose'] == null) {
      next['verbose'] = 1;
      changed = true;
    }
    if (changed) await saveConfig(next);
    if (json.containsKey('args') || json.containsKey('threads')) {
      await saveSettings();
    }
  }

  Future<void> saveConfig(Map<String, Object?> value) async {
    await write(configFile, const JsonEncoder.withIndent('  ').convert(value));
    config = value;
  }

  Future<void> saveSettings() => write(
    settingsFile,
    jsonEncode({'theme': theme, 'proxy': proxy.toJson()}),
  );

  /// Writes through a temporary file so a crash never leaves half a file.
  static Future<void> write(File file, String text) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  }
}
