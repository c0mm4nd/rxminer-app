import 'package:material_ui/material_ui.dart';
import 'package:rxminer/rxminer.dart';

import '../../controller.dart';
import '../../store.dart';
import '../../options.dart';
import '../format.dart';
import '../option_form.dart';
import '../page_frame.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pools in failover order. The first enabled pool is used first.
class PoolsPage extends StatelessWidget {
  const PoolsPage({required this.c, super.key});
  final MinerController c;

  Future<void> edit(BuildContext context, int? index) async {
    final pools = c.store.pools;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PoolEditorPage(
          c: c,
          pool: index == null ? PoolEntry.empty() : pools[index].copy(),
          onSave: (pool) async {
            final next = List.of(pools);
            index == null ? next.add(pool) : next[index] = pool;
            return save(context, next);
          },
          onDelete: index == null
              ? null
              : () => save(context, List.of(pools)..removeAt(index)),
        ),
      ),
    );
  }

  Future<String?> save(BuildContext context, List<PoolEntry> pools) async {
    final config = {
      ...c.store.config,
      'pools': [for (final p in pools) p.json],
    };
    try {
      await c.check(config);
      await c.savePools(pools);
      return null;
    } on MinerException catch (error) {
      return error.message;
    } on FormatException catch (error) {
      return error.message;
    } catch (error) {
      return 'Could not save the configuration: $error';
    }
  }

  Future<void> move(BuildContext context, int from, int to) async {
    final pools = c.store.pools;
    pools.insert(to, pools.removeAt(from));
    final error = await save(context, pools);
    if (error != null && context.mounted) notify(context, error);
  }

  Future<void> toggle(BuildContext context, int index, bool enabled) async {
    final pools = c.store.pools;
    pools[index].enabled = enabled;
    final error = await save(context, pools);
    if (error != null && context.mounted) notify(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pools = c.store.pools;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        SectionLabel(
          'Pools',
          trailing: Text(
            '${pools.length}',
            style: mono(size: 11, color: p.muted),
          ),
        ),
        if (c.running)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Notice(
              c.liveReload
                  ? 'The running miner reloads pool changes when you save.'
                  : 'Changes apply the next time the miner starts.',
            ),
          ),
        if (pools.isEmpty)
          EmptyState(
            icon: Icons.dns_outlined,
            title: 'No pools',
            subtitle: 'Add the Stratum address of a Monero (rx/0) pool and your wallet address.',
            action: FilledButton.icon(
              onPressed: () => edit(context, null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add a pool'),
            ),
          )
        else ...[
          Panel(
            padding: EdgeInsets.zero,
            children: [
              Column(
                children: [
                  for (final (i, pool) in pools.indexed) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 4, right: 4),
                      leading: Checkbox(
                        value: pool.enabled,
                        onChanged: (v) => toggle(context, i, v ?? false),
                      ),
                      title: Text(
                        pool.host.isEmpty ? 'Unnamed pool' : pool.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: pool.enabled ? p.strong : p.muted,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (i == 0) Pill('First', color: p.accent),
                            Pill(
                              pool.secure
                                  ? pool.tlsVerify ||
                                            pool.fingerprint.isNotEmpty
                                        ? 'TLS, verified'
                                        : 'TLS, not verified'
                                  : 'Plain TCP',
                              color: pool.secure
                                  ? pool.tlsVerify ||
                                            pool.fingerprint.isNotEmpty
                                        ? p.success
                                        : p.warning
                                  : p.warning,
                            ),
                            Text(
                              short(pool.user),
                              style: mono(size: 11.5, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Move up',
                            onPressed: i == 0
                                ? null
                                : () => move(context, i, i - 1),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => edit(context, i),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                        ],
                      ),
                      onTap: () => edit(context, i),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => edit(context, null),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a pool'),
          ),
          const SizedBox(height: 10),
          const Notice(
            'If the first pool fails after its retries, the miner moves to the next enabled one.',
          ),
        ],
      ],
    );
  }
}

class PoolEditorPage extends StatefulWidget {
  const PoolEditorPage({
    required this.c,
    required this.pool,
    required this.onSave,
    this.onDelete,
    super.key,
  });
  final MinerController c;
  final PoolEntry pool;

  /// Returns an error message, or null once saved.
  final Future<String?> Function(PoolEntry) onSave;
  final Future<String?> Function()? onDelete;
  @override
  State<PoolEditorPage> createState() => _PoolEditorPageState();
}

class _PoolEditorPageState extends State<PoolEditorPage> {
  PoolEntry get pool => widget.pool;
  final errors = <String, String>{};
  String? error;
  bool saving = false;

  Future<void> save() async {
    if (pool.url.trim().isEmpty || pool.user.trim().isEmpty) {
      setState(() => error = 'Enter the pool address and your wallet address.');
      return;
    }
    setState(() => saving = true);
    final result = await widget.onSave(pool);
    if (!mounted) return;
    setState(() {
      saving = false;
      error = result;
    });
    if (result == null) Navigator.pop(context);
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this pool?'),
        content: Text(
          pool.url.isEmpty ? 'This pool has no address.' : pool.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await widget.onDelete!();
    if (!mounted) return;
    if (result == null) {
      Navigator.pop(context);
    } else {
      setState(() => error = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    void changed() => setState(() {});
    void onError(String key, String? message) => setState(
      () => message == null ? errors.remove(key) : errors[key] = message,
    );
    List<OptionField> fields(Set<String> keys) => [
      for (final f in poolFields)
        if (keys.contains(f.key)) f,
    ];
    return FeaturePage(
      title: widget.onDelete == null ? 'Add a pool' : 'Edit pool',
      actions: [
        if (widget.onDelete != null)
          IconButton(
            tooltip: 'Remove',
            onPressed: saving ? null : delete,
            icon: Icon(Icons.delete_outline_rounded, color: p.danger),
          ),
      ],
      bottom: FilledButton(
        onPressed: saving || errors.isNotEmpty ? null : save,
        child: Text(saving ? 'Checking' : 'Save'),
      ),
      children: [
        const SectionLabel('Connection'),
        OptionGroup(
          fields: fields({'url', 'user', 'pass', 'rig-id', 'enabled'}),
          data: pool.json,
          onChanged: changed,
          onError: onError,
        ),
        const SectionLabel('Security'),
        OptionGroup(
          fields: fields({'tls', 'tls-verify', 'tls-fingerprint', 'tls-ca'}),
          data: pool.json,
          onChanged: changed,
          onError: onError,
        ),
        if (pool.secure && !pool.tlsVerify && pool.fingerprint.isEmpty) ...[
          const SizedBox(height: 8),
          const Notice(
            'Without verification or a fingerprint, someone on the network path '
            'could pose as this pool and take your hashrate.',
            tone: Tone.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        const SectionLabel('Protocol'),
        OptionGroup(
          fields: fields({'socks5', 'keepalive', 'nicehash', 'algo', 'coin'}),
          data: pool.json,
          onChanged: changed,
          onError: onError,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Notice(error!, tone: Tone.danger, icon: Icons.error_outline),
        ],
      ],
    );
  }
}
