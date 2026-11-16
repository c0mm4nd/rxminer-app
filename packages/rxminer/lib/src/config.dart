import 'dart:convert';

/// The configuration a new installation starts from, in RxMiner's format.
Map<String, Object?> defaultConfig() => {
  'pools': <Object?>[],
  'cpu': {'enabled': true, 'huge-pages': true, 'max-threads-hint': 100},
  'randomx': {'mode': 'auto'},
};

/// Where an embedded session's HTTP API can be reached from this process.
class ApiEndpoint {
  const ApiEndpoint({
    required this.host,
    required this.port,
    this.token,
    this.secure = false,
    this.control = true,
  });
  final String host;
  final int port;
  final String? token;

  /// HTTPS, when the configuration enables the API's own TLS.
  final bool secure;

  /// Whether pause and resume are allowed (`http.restricted` is false).
  final bool control;
}

/// The file a session runs with, and how to observe it.
class SessionPlan {
  const SessionPlan({
    required this.config,
    required this.api,
    required this.logFile,
  });
  final Map<String, Object?> config;
  final ApiEndpoint api;
  final String logFile;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

/// Plans a session from the user's [config] without changing it.
///
/// The user's own HTTP API and log file are kept when configured; otherwise
/// the session gets an unrestricted API on loopback for [token] at [port], and
/// [logFile]. Every other key passes through. With [allowJit] false (iOS,
/// where apps cannot map executable memory) RandomX runs interpreted.
SessionPlan planSession(
  Map<String, Object?> config, {
  required int port,
  required String token,
  required String logFile,
  bool allowJit = true,
}) {
  final copy = _map(jsonDecode(jsonEncode(config)));
  final http = _map(copy['http']);
  final ApiEndpoint api;
  if (http['enabled'] == true) {
    final host = http['host'] as String? ?? '127.0.0.1';
    api = ApiEndpoint(
      host: switch (host) {
        '0.0.0.0' || '' => '127.0.0.1',
        '::' => '::1',
        _ => host,
      },
      port: (http['port'] as num?)?.toInt() ?? 0,
      token: http['access-token'] as String?,
      secure: _map(copy['tls'])['enabled'] == true,
      control: http['restricted'] == false,
    );
  } else {
    copy['http'] = {
      'enabled': true,
      'host': '127.0.0.1',
      'port': port,
      'access-token': token,
      'restricted': false,
    };
    // The API's TLS settings apply to the one server; keep it plain here.
    final tls = _map(copy['tls']);
    if (tls['enabled'] == true) copy['tls'] = {...tls, 'enabled': false};
    api = ApiEndpoint(host: '127.0.0.1', port: port, token: token);
  }
  final userLog = copy['log-file'];
  final log = userLog is String && userLog.isNotEmpty ? userLog : logFile;
  copy['log-file'] = log;
  if (!allowJit) copy['randomx'] = {..._map(copy['randomx']), 'jit': false};
  return SessionPlan(config: copy, api: api, logFile: log);
}
