import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:rxminer/rxminer.dart';

import '../../controller.dart';
import '../../options.dart';
import '../../store.dart';
import '../option_form.dart';
import '../page_frame.dart';
import '../theme.dart';
import '../widgets.dart';

/// Every key of config.json except pools, grouped like upstream's sections,
/// plus the two proxy options config.json has no key for.
class ConfigPage extends StatefulWidget {
  const ConfigPage({required this.c, super.key});
  final MinerController c;
  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  MinerController get c => widget.c;
  late final Map<String, Object?> draft =
      (jsonDecode(jsonEncode(c.store.config)) as Map).cast<String, Object?>();
  late final Map<String, Object?> proxyDraft = {
    if (c.store.proxy.proxy.isNotEmpty) 'proxy': c.store.proxy.proxy,
    if (c.store.proxy.noProxy) 'no-proxy': true,
  };
  final open = <String>{};
  final errors = <String, String>{};
  String? failure;
  bool saving = false;
  bool dirty = false;

  void changed() => setState(() => dirty = true);

  void onError(String key, String? message) => setState(
    () => message == null ? errors.remove(key) : errors[key] = message,
  );

  /// Checks the draft with the miner, then saves it.
  Future<void> save() async {
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      final proxy = ProxySettings.fromJson(proxyDraft);
      await c.check(draft, proxy: proxy);
      await c.saveConfig(draft);
      await c.setProxy(proxy);
      if (mounted) Navigator.pop(context);
    } on MinerException catch (e) {
      failure = e.message;
    } catch (e) {
      failure = 'Could not save: $e';
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  int setCount(OptionSection section) =>
      section.fields.where((f) => readPath(draft, f.path) != null).length +
      (section.title == 'Connection' ? proxyDraft.length : 0);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return FeaturePage(
      title: 'Configuration',
      bottom: FilledButton(
        onPressed: saving || !dirty || errors.isNotEmpty ? null : save,
        child: Text(
          saving
              ? 'Checking'
              : errors.isNotEmpty
              ? 'Fix ${errors.length} field${errors.length == 1 ? '' : 's'} first'
              : dirty
              ? 'Check and save'
              : 'No changes',
        ),
      ),
      children: [
        Notice(
          c.running
              ? c.liveReload
                    ? 'The running miner reloads these settings when you save.'
                    : 'Changes apply the next time the miner starts, '
                          'because reload on save is off.'
              : 'Unset options use the miner’s defaults. Pools are on the '
                    'Pools tab.',
        ),
        for (final section in configSections) ...[
          SectionLabel(
            section.title,
            expanded: open.contains(section.title),
            onTap: () => setState(
              () => open.contains(section.title)
                  ? open.remove(section.title)
                  : open.add(section.title),
            ),
            trailing: Text(
              setCount(section) == 0 ? 'defaults' : '${setCount(section)} set',
              style: mono(size: 11, color: p.muted),
            ),
          ),
          if (open.contains(section.title)) ...[
            if (section.intro != null) ...[
              Notice(section.intro!),
              const SizedBox(height: 8),
            ],
            OptionGroup(
              fields: section.fields,
              data: draft,
              onChanged: changed,
              onError: onError,
              disabled: {if (!jitAllowed) 'randomx.jit'},
            ),
            if (section.title == 'Connection') ...[
              const SizedBox(height: 8),
              OptionGroup(
                fields: proxyFields,
                data: proxyDraft,
                onChanged: changed,
                onError: onError,
              ),
            ],
          ],
        ],
        if (failure != null) ...[
          const SizedBox(height: 12),
          Notice(failure!, tone: Tone.danger, icon: Icons.error_outline),
        ],
      ],
    );
  }
}
