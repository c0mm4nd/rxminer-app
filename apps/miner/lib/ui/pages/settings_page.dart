import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:rxminer/rxminer.dart';

import '../../controller.dart';
import '../../store.dart';
import '../brand.dart';
import '../page_frame.dart';
import 'config_page.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.c, super.key});
  final MinerController c;

  /// Applies [change] to a copy of the configuration, checks it with the
  /// miner and saves it. The saved file is untouched when the check fails.
  Future<void> update(
    BuildContext context,
    void Function(Map<String, Object?> config) change,
  ) async {
    final next = (jsonDecode(jsonEncode(c.store.config)) as Map)
        .cast<String, Object?>();
    change(next);
    try {
      await c.check(next);
      await c.saveConfig(next);
    } on MinerException catch (error) {
      if (context.mounted) notify(context, error.message);
    } catch (error) {
      if (context.mounted) {
        notify(context, 'Could not save the configuration: $error');
      }
    }
  }

  Map<String, Object?> sectionOf(Map<String, Object?> config, String name) {
    final value = config[name];
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    config[name] = map;
    return map;
  }

  /// Sets the thread count in cpu.rx, keeping an affinity mask if there is
  /// one. Automatic removes cpu.rx so the miner picks physical cores.
  Future<void> threads(BuildContext context) async {
    final logical = c.device?.logical ?? 1;
    final rx = c.store.section('cpu')['rx'];
    final current = profileThreads(rx);
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SheetFrame(
        title: 'Worker threads',
        children: [
          Notice(
            'Each thread hashes on one CPU and needs a 2 MiB scratchpad. '
            'Automatic uses ${c.device?.selected ?? 'the'} physical cores.'
            '${rx is List ? ' Choosing a number replaces the CPU list in cpu.rx.' : ''}',
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Automatic'),
            trailing: rx == null ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(context, 0),
          ),
          for (var n = 1; n <= logical; n++)
            ListTile(
              title: Text('$n'),
              trailing: current == n ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, n),
            ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    await update(context, (config) {
      final cpu = sectionOf(config, 'cpu');
      if (value == 0) {
        cpu.remove('rx');
      } else {
        final affinity = rx is Map ? rx['affinity'] : null;
        cpu['rx'] = {'threads': value, 'affinity': ?affinity};
      }
    });
  }

  /// What cpu.rx means, in a few words.
  String threadsLabel() {
    final rx = c.store.section('cpu')['rx'];
    if (rx == null) return 'Automatic';
    final n = profileThreads(rx);
    if (n == null) return 'Named profile in cpu.rx';
    final pinned = rx is List || (rx is Map && rx['affinity'] != null);
    return '$n thread${n == 1 ? '' : 's'}${pinned ? ', pinned to CPUs' : ''}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final p = Palette.of(context);
      final cpu = c.store.section('cpu');
      final randomx = c.store.section('randomx');
      final mode = randomx['mode'] as String? ?? 'auto';
      final jitSupported = c.device?.jit ?? false;
      return FeaturePage(
        title: 'Settings',
        children: [
          const SectionLabel('Appearance'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System')),
              ButtonSegment(value: 'light', label: Text('Light')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
            ],
            selected: {c.store.theme},
            onSelectionChanged: (v) => c.setTheme(v.first),
          ),
          const SectionLabel('Performance'),
          if (c.running)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Notice(
                c.liveReload
                    ? 'The running miner reloads these settings when you save.'
                    : 'Changes apply the next time the miner starts.',
              ),
            ),
          Panel(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                title: const Text('Worker threads'),
                subtitle: Text(threadsLabel()),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => threads(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Memory mode', style: mono(size: 12, color: p.muted)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Automatic')),
              ButtonSegment(value: 'fast', label: Text('Fast')),
              ButtonSegment(value: 'light', label: Text('Light')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => update(
              context,
              (config) => sectionOf(config, 'randomx')['mode'] = v.first,
            ),
          ),
          const SizedBox(height: 6),
          Text(switch (mode) {
            'fast' => 'Fast builds the 2.3 GiB dataset for full speed.',
            'light' =>
              'Light keeps only the 256 MiB cache. It is several times slower.',
            _ =>
              isMobile
                  ? 'This system does not report free memory, so Automatic means Fast here.'
                  : 'Automatic uses Fast when enough memory is free, otherwise Light.',
          }, style: mono(size: 11.5, color: p.muted, height: 1.5)),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            children: [
              CheckboxListTile(
                value: cpu['huge-pages'] != false,
                onChanged: (v) => update(
                  context,
                  (config) =>
                      sectionOf(config, 'cpu')['huge-pages'] = v ?? false,
                ),
                title: const Text('Huge pages'),
                subtitle: const Text(
                  'Uses 2 MiB pages when the system has them, and ordinary pages otherwise.',
                ),
              ),
              const Divider(),
              CheckboxListTile(
                value: jitSupported && jitAllowed && randomx['jit'] != false,
                onChanged: jitSupported && jitAllowed
                    ? (v) => update(
                        context,
                        (config) =>
                            sectionOf(config, 'randomx')['jit'] = v ?? false,
                      )
                    : null,
                title: const Text('JIT compiler'),
                subtitle: Text(
                  !jitAllowed
                      ? 'iOS does not allow apps to create executable memory, so the interpreter is used.'
                      : !jitSupported
                      ? 'This CPU architecture has no RandomX JIT; the interpreter is used.'
                      : 'Compiles RandomX programs to machine code. Much faster than the interpreter.',
                ),
              ),
              const Divider(),
              CheckboxListTile(
                value: cpu['yield'] != false,
                onChanged: (v) => update(
                  context,
                  (config) => sectionOf(config, 'cpu')['yield'] = v ?? false,
                ),
                title: const Text('Yield to other apps'),
                subtitle: const Text(
                  'Workers give way to other work between hashes.',
                ),
              ),
            ],
          ),
          const SectionLabel('Configuration'),
          Panel(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.tune_rounded, size: 18),
                title: const Text('All configuration options'),
                subtitle: const Text(
                  'Every miner option, with its default and limits.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ConfigPage(c: c)),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.data_object_rounded, size: 18),
                title: const Text('Edit config.json'),
                subtitle: const Text(
                  'The file itself, in the command-line miner’s format.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConfigEditorPage(c: c),
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded, size: 18),
                title: const Text('Reset configuration'),
                subtitle: const Text(
                  'Clears every option, including the proxy. Keeps your pools.',
                ),
                onTap: () async {
                  await c.setProxy(ProxySettings());
                  await c.saveConfig({
                    ...MinerStore.initialConfig(),
                    'pools': c.store.config['pools'] ?? const [],
                  });
                  if (context.mounted) {
                    notify(context, 'Configuration reset');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Panel(children: [InfoRow('Folder', c.store.dir.path, copy: true)]),
          const SectionLabel('About'),
          Panel(
            children: [
              const InfoRow('App', appVersion),
              InfoRow(
                'Miner',
                'RxMiner $minerVersion, revision $minerRevision',
              ),
              const InfoRow('Source', minerSource, copy: true),
              const InfoRow('Developer fee', 'Under 1% of hashing time'),
              InfoRow('Fee pools', devFeeHosts.join('\n')),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: appName,
              applicationVersion: appVersion,
            ),
            child: const Text('Open-source licences'),
          ),
        ],
      );
    },
  );
}

/// Raw editor for config.json, checked by the miner before it is saved.
class ConfigEditorPage extends StatefulWidget {
  const ConfigEditorPage({required this.c, super.key});
  final MinerController c;
  @override
  State<ConfigEditorPage> createState() => _ConfigEditorPageState();
}

class _ConfigEditorPageState extends State<ConfigEditorPage> {
  late final text = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(widget.c.store.config),
  );
  String? error;
  bool saving = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final Object? json;
      try {
        json = jsonDecode(text.text);
      } on FormatException catch (e) {
        throw FormatException('This is not valid JSON: ${e.message}');
      }
      if (json is! Map) {
        throw const FormatException('The configuration must be a JSON object.');
      }
      final config = json.cast<String, Object?>();
      await widget.c.check(config);
      await widget.c.saveConfig(config);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      error = e.message;
    } on MinerException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not save the configuration: $e';
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return FeaturePage(
      title: 'config.json',
      bottom: FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Checking' : 'Check and save'),
      ),
      children: [
        const Notice(
          'Every key here reaches the miner unchanged. When http is not '
          'enabled, the app adds a private API on 127.0.0.1; when log-file is '
          'not set, it adds its own log.',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: text,
          maxLines: null,
          minLines: 18,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          style: mono(size: 12, color: p.strong, height: 1.5),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Notice(error!, tone: Tone.danger, icon: Icons.error_outline),
        ],
      ],
    );
  }
}
