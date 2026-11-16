import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';

/// Submitted, accepted and rejected shares for one pool connection.
class Shares {
  const Shares(this.submitted, this.accepted, this.rejected);
  factory Shares.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    return Shares(read('submitted'), read('accepted'), read('rejected'));
  }
  static const none = Shares(0, 0, 0);
  final int submitted, accepted, rejected;
}

/// Hashes per second over the miner's sliding windows.
class Hashrate {
  const Hashrate(this.s10, this.s60, this.m15, this.total);
  factory Hashrate.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    double read(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return Hashrate(read('10s'), read('60s'), read('15m'), read('total'));
  }
  static const zero = Hashrate(0, 0, 0, 0);
  final double s10, s60, m15, total;
}

/// The miner's `/summary` document.
class Summary {
  const Summary({
    required this.version,
    required this.uptime,
    required this.hashes,
    required this.paused,
    required this.hashrate,
    required this.shares,
    required this.devShares,
    required this.threads,
    required this.nodes,
    required this.hugeDatasets,
    required this.hugeScratchpads,
    required this.devFee,
    required this.devPhase,
    required this.poolUrl,
    required this.poolConnected,
    required this.devPoolUrl,
    required this.devPoolConnected,
  });
  factory Summary.fromJson(Map<String, Object?> json) {
    Map read(String key) => json[key] is Map ? json[key] as Map : const {};
    final huge = read('huge_pages'), fee = read('dev_fee');
    final pool = read('pool'), dev = read('dev_pool');
    return Summary(
      version: json['version'] as String? ?? '',
      uptime: Duration(
        milliseconds: (((json['uptime'] as num?) ?? 0) * 1000).round(),
      ),
      hashes: (json['hashes'] as num?)?.toInt() ?? 0,
      paused: json['paused'] == true,
      hashrate: Hashrate.fromJson(json['hashrate']),
      shares: Shares.fromJson(json['shares']),
      devShares: Shares.fromJson(json['dev_shares']),
      threads: (json['threads'] as num?)?.toInt() ?? 0,
      nodes: (json['nodes'] as num?)?.toInt() ?? 0,
      hugeDatasets: (huge['datasets'] as num?)?.toInt() ?? 0,
      hugeScratchpads: (huge['scratchpads'] as num?)?.toInt() ?? 0,
      devFee: fee['percent'] as String? ?? '',
      devPhase: fee['phase'] == 'dev',
      poolUrl: pool['url'] as String? ?? '',
      poolConnected: pool['connected'] == true,
      devPoolUrl: dev['url'] as String? ?? '',
      devPoolConnected: dev['connected'] == true,
    );
  }
  final String version;
  final Duration uptime;
  final int hashes;
  final bool paused;
  final Hashrate hashrate;
  final Shares shares, devShares;

  /// Running workers and NUMA nodes in use; zero until the dataset is ready.
  final int threads, nodes;
  final int hugeDatasets, hugeScratchpads;

  /// The developer fee as the miner states it, and whether it is mining it now.
  final String devFee;
  final bool devPhase;
  final String poolUrl, devPoolUrl;
  final bool poolConnected, devPoolConnected;
}

/// Client for a session's HTTP API.
class MinerApi {
  MinerApi(this.endpoint);
  final ApiEndpoint endpoint;
  late final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..findProxy = ((_) => 'DIRECT')
    // The API's own certificate is usually self-signed. Accept it only for
    // the machine itself, never across a network.
    ..badCertificateCallback = (_, host, _) =>
        host == '127.0.0.1' || host == '::1' || host == 'localhost';

  Future<(int, Object?)> _send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final request = await _client
        .openUrl(
          method,
          Uri(
            scheme: endpoint.secure ? 'https' : 'http',
            host: endpoint.host,
            port: endpoint.port,
            path: path,
          ),
        )
        .timeout(const Duration(seconds: 2));
    final token = endpoint.token;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 3));
    final text = await response.transform(utf8.decoder).join();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  Future<Summary> summary() async {
    final (status, json) = await _send('GET', '/summary');
    if (status != 200 || json is! Map<String, Object?>) {
      throw HttpException('summary returned $status');
    }
    return Summary.fromJson(json);
  }

  Future<void> _rpc(String method) async {
    final (status, json) = await _send('POST', '/json_rpc', {
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
    });
    if (status != 200 || json is! Map || json['error'] != null) {
      throw HttpException('$method was refused ($status)');
    }
  }

  Future<void> pause() => _rpc('pause');
  Future<void> resume() => _rpc('resume');

  void close() => _client.close(force: true);
}
