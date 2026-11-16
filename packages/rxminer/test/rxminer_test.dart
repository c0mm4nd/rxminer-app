import 'dart:convert';
import 'dart:io';

import 'package:rxminer/rxminer.dart';
import 'package:test/test.dart';

void main() {
  group('Summary', () {
    test('reads the upstream summary document', () {
      final summary = Summary.fromJson({
        'version': '0.2.0',
        'uptime': 12.5,
        'hashes': 4096,
        'paused': false,
        'hashrate': {'10s': 812.4, '60s': 790, '15m': 0, 'total': 650.1},
        'shares': {'submitted': 3, 'accepted': 2, 'rejected': 1},
        'dev_shares': {'submitted': 0, 'accepted': 0, 'rejected': 0},
        'threads': 8,
        'nodes': 1,
        'huge_pages': {'size_kib': 2048, 'datasets': 1, 'scratchpads': 8},
        'dev_fee': {'percent': '<1%', 'phase': 'user', 'address': '4…'},
        'pool': {'url': 'stratum+ssl://pool.example:443', 'connected': true},
        'dev_pool': {'url': '', 'connected': false},
      });
      expect(summary.uptime, const Duration(milliseconds: 12500));
      expect(summary.hashrate.s10, 812.4);
      expect(summary.hashrate.s60, 790);
      expect(summary.shares.rejected, 1);
      expect(summary.hugeScratchpads, 8);
      expect(summary.devPhase, isFalse);
      expect(summary.poolConnected, isTrue);
    });

    test('tolerates missing sections', () {
      final summary = Summary.fromJson({});
      expect(summary.hashrate.total, 0);
      expect(summary.shares.submitted, 0);
      expect(summary.poolUrl, '');
    });
  });

  group('planSession', () {
    test('adds a loopback API and log when the user has none', () {
      final user = defaultConfig()
        ..['randomx'] = {'mode': 'light', 'jit': true}
        ..['tls'] = {'enabled': true, 'cert': 'c.pem'};
      final plan = planSession(
        user,
        port: 4321,
        token: 'abc',
        logFile: '/tmp/x.log',
        allowJit: false,
      );
      final http = plan.config['http'] as Map;
      expect(http['host'], '127.0.0.1');
      expect(http['restricted'], isFalse);
      expect(http['access-token'], 'abc');
      expect((plan.config['tls'] as Map)['enabled'], isFalse);
      expect(plan.api.port, 4321);
      expect(plan.api.control, isTrue);
      expect(plan.logFile, '/tmp/x.log');
      expect((plan.config['randomx'] as Map)['jit'], isFalse);
      expect((plan.config['randomx'] as Map)['mode'], 'light');
      expect((user['randomx'] as Map)['jit'], isTrue);
      expect(user.containsKey('http'), isFalse);
    });

    test('keeps the user API, log and every other key', () {
      final user = {
        ...defaultConfig(),
        'http': {
          'enabled': true,
          'host': '0.0.0.0',
          'port': 8080,
          'access-token': 'mine',
          'restricted': true,
        },
        'tls': {'enabled': true},
        'log-file': '/var/log/rxminer.log',
        'watch': true,
        'autosave': true,
        'colors': true,
      };
      final plan = planSession(user, port: 1, token: 't', logFile: '/x');
      expect(plan.config['http'], user['http']);
      expect(plan.api.host, '127.0.0.1');
      expect(plan.api.port, 8080);
      expect(plan.api.token, 'mine');
      expect(plan.api.secure, isTrue);
      expect(plan.api.control, isFalse);
      expect(plan.logFile, '/var/log/rxminer.log');
      for (final key in ['watch', 'autosave', 'colors']) {
        expect(plan.config[key], isTrue);
      }
    });
  });

  test('log tail returns only complete appended lines', () async {
    final dir = await Directory.systemTemp.createTemp('rxminer-log');
    final file = File('${dir.path}/miner.log');
    final tail = LogTail(file, limit: 3);
    expect(await tail.poll(), isFalse);
    await file.writeAsString('one\ntwo\npart');
    expect(await tail.poll(), isTrue);
    expect(tail.lines, ['one', 'two']);
    await file.writeAsString('ial\nthree\nfour\n', mode: FileMode.append);
    await tail.poll();
    expect(tail.lines, ['partial', 'three', 'four']);
    await file.writeAsString('fresh\n');
    await tail.poll();
    expect(tail.lines, ['fresh']);
    await file.delete();
    expect(await tail.poll(), isFalse);
    await dir.delete(recursive: true);
  });

  group('native', () {
    test('describes the device', () {
      final device = RxMiner.device();
      expect(device.logical, greaterThan(0));
      expect(device.selected, inInclusiveRange(1, device.logical));
      expect(device.summary, isNotEmpty);
    });

    test('rejects invalid arguments with the upstream message', () {
      expect(
        () => RxMiner.check(['--no-such-flag']),
        throwsA(isA<MinerException>()),
      );
    });

    test('checks a configuration file', () async {
      final dir = await Directory.systemTemp.createTemp('rxminer-check');
      final file = File('${dir.path}/config.json');
      await file.writeAsString(
        jsonEncode(
          defaultConfig()
            ..['pools'] = [
              {'url': 'pool.example.com:3333', 'user': 'wallet'},
            ],
        ),
      );
      final result = RxMiner.check(['-c', file.path, '-t', '1']);
      expect(result.threads, 1);
      expect(result.benchmark, isFalse);
      expect(
        RxMiner.check(['-c', file.path, '--benchmark-seconds', '5']).benchmark,
        isTrue,
      );
      await file.writeAsString('{"pools": 1}');
      expect(
        () => RxMiner.check(['-c', file.path]),
        throwsA(isA<MinerException>()),
      );
      await dir.delete(recursive: true);
    });

    test('runs and stops an offline benchmark with its API', () async {
      final dir = await Directory.systemTemp.createTemp('rxminer-bench');
      final config = File('${dir.path}/session.json');
      final log = '${dir.path}/miner.log';
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final plan = planSession(
        defaultConfig()..['randomx'] = {'mode': 'light'},
        port: port,
        token: 'test-token',
        logFile: log,
      );
      await config.writeAsString(jsonEncode(plan.config));
      RxMiner.start([
        '-c',
        config.path,
        '-t',
        '1',
        '--benchmark-seconds',
        '60',
      ]);
      expect(RxMiner.state().running, isTrue);
      expect(
        () => RxMiner.start(['-c', config.path, '--benchmark-seconds', '1']),
        throwsA(isA<MinerException>()),
      );
      final api = MinerApi(plan.api);
      Summary? summary;
      for (var i = 0; i < 50 && summary == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        try {
          summary = await api.summary();
        } on Object {
          // The API starts once topology and memory are prepared.
        }
      }
      expect(summary, isNotNull);
      expect(summary!.version, isNotEmpty);
      api.close();
      RxMiner.stop();
      for (var i = 0; i < 300 && RxMiner.state().running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(RxMiner.state().running, isFalse);
      expect(RxMiner.state().error, isNull);
      expect(await File(log).readAsString(), contains('RxMiner'));
      await dir.delete(recursive: true);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
