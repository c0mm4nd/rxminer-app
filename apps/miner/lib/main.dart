import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'controller.dart';
import 'store.dart';
import 'ui/brand.dart';
import 'ui/format.dart';
import 'ui/pages/log_page.dart';
import 'ui/pages/miner_page.dart';
import 'ui/pages/pools_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/fonts/OFL-JetBrainsMono.txt'));
  });
  final dir = await getApplicationSupportDirectory();
  runApp(MinerApp(controller: MinerController(MinerStore(dir))));
}

class MinerApp extends StatefulWidget {
  const MinerApp({required this.controller, super.key});
  final MinerController controller;
  @override
  State<MinerApp> createState() => _MinerAppState();
}

class _MinerAppState extends State<MinerApp> {
  MinerController get c => widget.controller;
  late final AppLifecycleListener lifecycle;

  @override
  void initState() {
    super.initState();
    // Stop the native session before the process goes away.
    lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        c.stop();
        return AppExitResponse.exit;
      },
      onDetach: c.stop,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => c.load());
  }

  @override
  void dispose() {
    lifecycle.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (c.store.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: RootGate(c: c),
    ),
  );
}

class RootGate extends StatelessWidget {
  const RootGate({required this.c, super.key});
  final MinerController c;
  @override
  Widget build(BuildContext context) {
    if (c.loading) {
      return const Scaffold(body: Center(child: RxMark(height: 56)));
    }
    if (c.loadFailure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text(appName)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Notice(
                    c.loadFailure!,
                    tone: Tone.danger,
                    icon: Icons.error_outline,
                  ),
                  const SizedBox(height: 12),
                  Text(c.store.configFile.path, style: mono(size: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AppShell(c: c);
  }
}

typedef _Tab = ({String label, IconData icon});
const _tabs = <_Tab>[
  (label: 'Miner', icon: Icons.memory_rounded),
  (label: 'Pools', icon: Icons.dns_outlined),
  (label: 'Log', icon: Icons.notes_rounded),
];

class AppShell extends StatefulWidget {
  const AppShell({required this.c, super.key});
  final MinerController c;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  MinerController get c => widget.c;

  void settings() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => SettingsPage(c: c)));

  Widget header() {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: p.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const RxMark(height: 18),
                  const SizedBox(width: 8),
                  Text(
                    appName,
                    style: mono(
                      size: 14,
                      weight: FontWeight.w700,
                      color: p.strong,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: dark ? 'Light theme' : 'Dark theme',
                    onPressed: () => c.setTheme(dark ? 'light' : 'dark'),
                    icon: Icon(
                      dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: settings,
                    icon: const Icon(Icons.settings_outlined, size: 20),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            statusBar(),
          ],
        ),
      ),
    );
  }

  /// The session at a glance; green while hashing, amber while paused.
  Widget statusBar() {
    final p = Palette.of(context);
    final s = c.summary;
    final color = !c.running
        ? p.status
        : c.paused || c.state.stopping
        ? p.warning
        : p.success;
    final style = mono(size: 11, color: p.onStatus);
    final String left, right;
    if (!c.running) {
      left = c.failure != null ? 'Stopped with an error' : 'Stopped';
      right = c.device == null
          ? ''
          : '${c.device!.selected} cores  ${c.enabledPools.length} pool${c.enabledPools.length == 1 ? '' : 's'}';
    } else {
      left = c.state.stopping
          ? 'Stopping'
          : c.paused
          ? 'Paused'
          : s == null || s.threads == 0
          ? 'Starting'
          : hashrate(s.hashrate.s10);
      right = c.phase == Phase.benchmark
          ? 'Benchmark  ${duration(s?.uptime ?? Duration.zero)}'
          : s == null
          ? ''
          : '${s.shares.accepted}/${s.shares.submitted} shares  '
                '${s.poolConnected ? s.poolUrl.replaceFirst(RegExp(r'^[a-z+]+://'), '') : 'Connecting'}';
    }
    return Container(
      color: color,
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                c.running ? Icons.bolt_rounded : Icons.circle_outlined,
                size: 13,
                color: p.onStatus,
              ),
              const SizedBox(width: 5),
              Text(left, style: style),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  right,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Editor-style tabs along the bottom; the active one has an accent edge.
  Widget tabStrip() {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.background,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, t) in _tabs.indexed)
                Expanded(
                  child: InkWell(
                    key: ValueKey('tab-${t.label}'),
                    onTap: () => setState(() => tab = i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: i == tab ? p.surface : p.background,
                        border: Border(
                          top: BorderSide(
                            color: i == tab ? p.accent : Colors.transparent,
                            width: 2,
                          ),
                          right: i == _tabs.length - 1
                              ? BorderSide.none
                              : BorderSide(color: p.border),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            t.icon,
                            size: 16,
                            color: i == tab ? p.accent : p.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.label,
                            style: mono(
                              size: 12.5,
                              weight: i == tab
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == tab ? p.strong : p.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Wide layouts get a left activity bar instead of the tab strip.
  Widget activityBar() {
    final p = Palette.of(context);
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: p.background,
        border: Border(right: BorderSide(color: p.border)),
      ),
      // Stretch each item to the bar's width, so the active edge sits on the
      // left border and the whole cell responds to hover and taps.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, t) in _tabs.indexed)
            Tooltip(
              message: t.label,
              child: InkWell(
                key: ValueKey('tab-${t.label}'),
                onTap: () => setState(() => tab = i),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: i == tab ? p.strong : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Icon(t.icon, color: i == tab ? p.strong : p.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final body = switch (tab) {
      0 => MinerPage(c: c, onPools: () => setState(() => tab = 1)),
      1 => PoolsPage(c: c),
      _ => LogPage(c: c),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): settings,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            settings,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              header(),
              Expanded(
                child: Row(
                  children: [
                    if (wide) activityBar(),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!wide) tabStrip(),
            ],
          ),
        ),
      ),
    );
  }
}
