import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxminer/rxminer.dart';
import 'package:rxminer_app/controller.dart';
import 'package:rxminer_app/main.dart';
import 'package:rxminer_app/ui/theme.dart';
import 'package:rxminer_app/store.dart';
import 'package:rxminer_app/ui/pages/config_page.dart';

Future<void> loadFonts() async {
  final loader = FontLoader('RxMono');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/JetBrainsMono-$w.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)),
    );
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((b) => ByteData.view(b.buffer)),
    );
  await icons.load();
}

/// A fixed session so screenshots do not depend on this machine.
class SampleController extends MinerController {
  SampleController(super.store);
  @override
  Future<void> load() async {
    await store.load();
    device = const DeviceInfo(
      logical: 10,
      selected: 8,
      nodes: 1,
      summary: '8 threads (node0:8)',
      memory: 17179869184,
      jit: true,
      arch: 'aarch64',
      os: 'macos',
    );
    loading = false;
    notifyListeners();
  }

  void mining() {
    phase = Phase.mining;
    state = const MinerState(running: true, stopping: false);
    samples
      ..clear()
      ..addAll([
        for (var i = 0; i < 180; i++)
          2400 + (i % 17) * 25.0 + (i < 20 ? -2000 + i * 100 : 0),
      ]);
    summary = Summary.fromJson({
      'version': '0.2.0',
      'uptime': 3725.0,
      'hashes': 8812345,
      'paused': false,
      'hashrate': {
        '10s': 2731.4,
        '60s': 2702.9,
        '15m': 2688.0,
        'total': 2601.2,
      },
      'shares': {'submitted': 41, 'accepted': 40, 'rejected': 1},
      'threads': 8,
      'nodes': 1,
      'huge_pages': {'datasets': 0, 'scratchpads': 0},
      'dev_fee': {'percent': '<1%', 'phase': 'user'},
      'pool': {
        'url': 'stratum+ssl://pool.supportxmr.com:443',
        'connected': true,
      },
      'dev_pool': {'url': '', 'connected': false},
    });
    notifyListeners();
  }
}

void main() {
  late Directory dir;
  setUpAll(loadFonts);
  // The same path on every machine, because the settings screenshot shows it.
  setUp(() async {
    dir = Directory('/tmp/rxminer-app-test');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<SampleController> pump(
    WidgetTester tester, {
    Size size = const Size(400, 860),
    bool pools = true,
    String theme = 'dark',
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = MinerStore(dir)..theme = theme;
    if (pools) {
      store.config['pools'] = [
        {
          'url': 'stratum+ssl://pool.supportxmr.com:443',
          'user': '46fca3jxDH5RxoRkAg2DcCPYWyMGFLYQgRZrYTR7qyd2GLqLq8hvSiMSRQ5YWcZ5QBfYB1nCBb2J2aiww7bP7YHC21wZecJ',
          'tls': true,
          'tls-verify': true,
        },
        {
          'url': 'pool.hashvault.pro:3333',
          'user': '46fca3jxDH5RxoRk…ZecJ',
          'enabled': false,
        },
      ];
    }
    final c = SampleController(store);
    await tester.runAsync(() => c.load());
    await tester.pumpWidget(MinerApp(controller: c));
    await tester.pump();
    return c;
  }

  testWidgets('idle dashboard discloses the pools it will contact', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Start'), findsOneWidget);
    expect(find.textContaining('pool.supportxmr.com:443'), findsWidgets);
    expect(find.textContaining('pool.hashvault.pro:443'), findsOneWidget);
    await expectLater(
      find.byType(MinerApp),
      matchesGoldenFile('goldens/idle.png'),
    );
  });

  testWidgets('start is disabled until a pool exists', (tester) async {
    await pump(tester, pools: false, theme: 'light');
    expect(find.text('Add a pool'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump();
    await expectLater(
      find.byType(MinerApp),
      matchesGoldenFile('goldens/no_pool_light.png'),
    );
  });

  testWidgets('mining dashboard shows the session', (tester) async {
    final c = await pump(tester);
    c.mining();
    await tester.pump();
    expect(find.text('2731.4 H/s'), findsWidgets);
    expect(find.text('40 accepted, 1 rejected of 41'), findsOneWidget);
    await expectLater(
      find.byType(MinerApp),
      matchesGoldenFile('goldens/mining.png'),
    );
    c.state = MinerState.idle;
  });

  testWidgets('wide layout uses the activity bar', (tester) async {
    final c = await pump(tester, size: const Size(1200, 760));
    c.mining();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-Pools')));
    await tester.pump();
    expect(find.text('TLS, verified'), findsOneWidget);
    expect(find.text('Plain TCP'), findsOneWidget);
    await expectLater(
      find.byType(MinerApp),
      matchesGoldenFile('goldens/pools_wide.png'),
    );
    c.state = MinerState.idle;
  });

  testWidgets('settings page', (tester) async {
    await pump(tester, size: const Size(400, 1400));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Memory mode'), findsOneWidget);
    await expectLater(
      find.byType(MinerApp),
      matchesGoldenFile('goldens/settings.png'),
    );
  });
  testWidgets('every configuration key can be edited', (tester) async {
    final c = await pump(tester, size: const Size(420, 1500));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: ConfigPage(c: c),
      ),
    );
    await tester.tap(find.text('CPU'));
    await tester.pump();
    expect(find.text('Key cpu.max-threads-hint, default 100'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '100'), '150');
    await tester.pump();
    expect(find.text('Enter 1 to 100.'), findsOneWidget);
    expect(find.text('Fix 1 field first'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '150'), '50');
    await tester.pump();
    expect(find.text('Check and save'), findsOneWidget);
    await expectLater(
      find.byType(ConfigPage),
      matchesGoldenFile('goldens/config.png'),
    );
  });

  testWidgets('the proxy sits with the connection options', (tester) async {
    final c = await pump(tester, size: const Size(420, 1500));
    c.store.proxy = ProxySettings(proxy: '127.0.0.1:9050');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: ConfigPage(c: c),
      ),
    );
    // The proxy counts as a setting of the Connection group.
    final connection = find.ancestor(
      of: find.text('CONNECTION'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: connection.first, matching: find.text('1 set')),
      findsOneWidget,
    );
    await tester.tap(find.text('CONNECTION'));
    await tester.pump();
    expect(find.text('Proxy for every pool'), findsOneWidget);
    expect(find.text('127.0.0.1:9050'), findsOneWidget);
    expect(
      find.text('Kept in the app’s settings, not in config.json'),
      findsOneWidget,
    );
    expect(find.textContaining('command'), findsNothing);
    await expectLater(
      find.byType(ConfigPage),
      matchesGoldenFile('goldens/connection.png'),
    );
  });
}
