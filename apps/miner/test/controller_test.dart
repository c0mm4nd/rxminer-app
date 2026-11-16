import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rxminer/rxminer.dart';
import 'package:rxminer_app/controller.dart';
import 'package:rxminer_app/store.dart';

/// Runs the real native miner, offline, through the controller.
void main() {
  late Directory dir;
  late MinerController c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rxminer-controller');
    c = MinerController(MinerStore(dir));
    await c.load();
  });
  tearDown(() async {
    c.stop();
    for (var i = 0; i < 100 && RxMiner.state().running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Stop polling before the files it reads are removed.
    c.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> until(bool Function() done, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue);
  }

  test('checks options without a pool and reports miner errors', () async {
    await c.check({...c.store.config, 'retries': 3});
    await expectLater(
      c.check({...c.store.config, 'retries': 0}),
      throwsA(
        isA<MinerException>().having(
          (e) => e.message,
          'message',
          contains('retries'),
        ),
      ),
    );
    // The proxy is checked with a pool, as the miner only parses it then.
    final withPool = {
      ...c.store.config,
      'pools': [
        {'url': 'pool.example.com:3333', 'user': 'wallet'},
      ],
    };
    await c.check(withPool, proxy: ProxySettings(proxy: '127.0.0.1:9050'));
    await expectLater(
      c.check(withPool, proxy: ProxySettings(proxy: 'ftp://127.0.0.1:21')),
      throwsA(isA<MinerException>()),
    );
  });

  test('moves settings from development builds into config.json', () async {
    final store = MinerStore(dir);
    await store.settingsFile.writeAsString(
      jsonEncode({
        'theme': 'dark',
        'args': {
          'threads': 2,
          'cpu-affinity': '0x3',
          'verbose': true,
          'proxy': '127.0.0.1:9050',
          'no-proxy': true,
          'extra': '',
        },
      }),
    );
    await store.load();
    expect((store.config['cpu'] as Map)['rx'], {
      'threads': 2,
      'affinity': '0x3',
    });
    expect(store.config['verbose'], 1);
    expect(store.proxy.proxy, '127.0.0.1:9050');
    expect(store.proxy.noProxy, isTrue);
    final saved = jsonDecode(await store.settingsFile.readAsString()) as Map;
    expect(saved.containsKey('args'), isFalse);
    expect(saved['theme'], 'dark');
    final config = jsonDecode(await store.configFile.readAsString()) as Map;
    expect((config['cpu'] as Map)['rx'], {'threads': 2, 'affinity': '0x3'});
  });

  test('a configured benchmark runs from Start with the user API, log and autosave', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final log = '${dir.path}/own.log';
    await File(log).writeAsString('old line\n');
    await c.saveConfig({
      // Upstream autosaves only without --threads or cpu.rx.
      'cpu': {'huge-pages': false, 'max-threads-hint': 1},
      'randomx': {'mode': 'light'},
      'benchmark': {'seconds': 60},
      'http': {
        'enabled': true,
        'host': '0.0.0.0',
        'port': port,
        'access-token': 'user-token',
        'restricted': false,
      },
      'log-file': log,
      'autosave': true,
      'watch': true,
    });
    expect(c.canStart, isTrue);
    await c.start();
    expect(c.failure, isNull);
    expect(c.phase, Phase.benchmark);
    expect(c.plan!.api.host, '127.0.0.1');
    expect(c.plan!.api.port, port);
    expect(c.canControl, isTrue);
    await until(() => c.summary != null);
    await until(() => c.log.lines.isNotEmpty);
    expect(c.log.lines, isNot(contains('old line')));
    // Autosave wrote cpu.rx into the session file; it reaches config.json.
    await until(() => (c.store.config['cpu'] as Map).containsKey('rx'));
    final saved = jsonDecode(await c.store.configFile.readAsString()) as Map;
    expect((saved['cpu'] as Map)['rx'], isA<List>());
    expect(saved.containsKey('http'), isTrue);
    // Saving with watch on rewrites the session file for live reload.
    expect(c.liveReload, isTrue);
    await c.saveConfig({...c.store.config, 'print-time': 5});
    final session = jsonDecode(await c.store.sessionFile.readAsString()) as Map;
    expect(session['print-time'], 5);
    c.stop();
    await until(() => !c.running);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the private API is used when the user has none', () async {
    await c.saveConfig({
      'cpu': {
        'huge-pages': false,
        'rx': {'threads': 1},
      },
      'randomx': {'mode': 'light'},
    });
    await c.start(benchmark: 60);
    expect(c.failure, isNull);
    expect(c.phase, Phase.benchmark);
    expect(c.plan!.logFile, c.store.logFile.path);
    expect(c.plan!.api.token, hasLength(48));
    await until(() => c.summary != null);
    expect(c.store.config.containsKey('http'), isFalse);
    c.stop();
    await until(() => !c.running);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
