import 'package:material_ui/material_ui.dart';

import '../../controller.dart';
import '../../store.dart';
import '../brand.dart';
import '../format.dart';
import '../page_frame.dart';
import '../theme.dart';
import '../widgets.dart';

/// The dashboard: hashrate, controls, session facts and the device.
class MinerPage extends StatelessWidget {
  const MinerPage({required this.c, required this.onPools, super.key});
  final MinerController c;
  final VoidCallback onPools;

  Future<void> benchmark(BuildContext context) async {
    final seconds = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SheetFrame(
        title: 'Run a benchmark',
        children: [
          const Notice(
            'The benchmark hashes a fixed local job. It contacts no pool and '
            'submits nothing. It uses the same threads and memory settings as mining.',
          ),
          const SizedBox(height: 8),
          for (final s in const [30, 60, 300])
            ListTile(
              title: Text(
                s < 60 ? '$s seconds' : '${s ~/ 60} minute${s > 60 ? 's' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, s),
            ),
        ],
      ),
    );
    if (seconds != null) await c.start(benchmark: seconds);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = c.summary;
    final pools = c.enabledPools;
    final mining = c.running && c.phase == Phase.mining;
    final rate = c.running && !c.paused ? s?.hashrate : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        SectionLabel(
          c.phase == Phase.benchmark ? 'Benchmark' : 'Hashrate',
          trailing: c.running
              ? Pill(
                  c.state.stopping
                      ? 'Stopping'
                      : c.paused
                      ? 'Paused'
                      : c.phase == Phase.benchmark
                      ? 'Benchmark'
                      : 'Mining',
                  color: c.paused || c.state.stopping ? p.warning : p.success,
                )
              : const Pill('Stopped'),
        ),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          children: [
            Text(
              rate == null ? '—' : hashrate(rate.s10),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 2),
            Text(
              rate == null
                  ? c.running
                        ? 'Preparing CPUs and the RandomX dataset'
                        : 'Not running'
                  : '10-second average',
              style: mono(size: 12, color: p.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 72, child: Sparkline(c.samples)),
            const SizedBox(height: 10),
            Row(
              children: [
                _Figure('60 s', rate == null ? '—' : hashrate(rate.s60)),
                _Figure('15 min', rate == null ? '—' : hashrate(rate.m15)),
                _Figure('Session', rate == null ? '—' : hashrate(rate.total)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        controls(context),
        if (c.failure != null) ...[
          const SizedBox(height: 10),
          Notice(c.failure!, tone: Tone.danger, icon: Icons.error_outline),
        ],
        if (c.running && c.phase == Phase.mining && !c.canControl) ...[
          const SizedBox(height: 10),
          const Notice(
            'Pause is unavailable because your HTTP API is read only. '
            'Turn off http.restricted and set an access token to use it.',
          ),
        ],
        if (!c.running && !c.canStart) ...[
          const SizedBox(height: 10),
          const Notice(
            'Add a pool and your wallet address before mining. '
            'A benchmark works without one.',
            tone: Tone.warning,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPools,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a pool'),
          ),
        ] else if (!c.running && pools.isNotEmpty) ...[
          const SizedBox(height: 10),
          Notice(
            'Starting connects to ${pools.first.host}'
            '${pools.length > 1 ? ' (then ${pools.length - 1} failover pool${pools.length > 2 ? 's' : ''})' : ''}'
            ' and to the RxMiner developer pools, which receive under 1% of '
            'hashing time: ${devFeeHosts.join(', ')}.',
          ),
        ],
        if (isMobile && !c.running) ...[
          const SizedBox(height: 8),
          const Notice(
            'Mining runs while RxMiner is open. The phone may slow it down or '
            'suspend it when the screen is off, and it gets warm under load.',
            icon: Icons.phone_android_rounded,
          ),
        ],
        if (mining || (c.running && s != null)) session(context),
        device(context),
      ],
    );
  }

  Widget controls(BuildContext context) {
    final running = c.running;
    final mining = running && c.phase == Phase.mining;
    final stopping = c.state.stopping;
    return Row(
      children: [
        Expanded(
          child: running
              ? QuickAction(
                  icon: Icons.stop_rounded,
                  label: stopping ? 'Stopping' : 'Stop',
                  primary: true,
                  onTap: stopping ? null : c.stop,
                )
              : QuickAction(
                  icon: Icons.play_arrow_rounded,
                  label: 'Start',
                  primary: true,
                  onTap: c.busy || !c.canStart ? null : c.start,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: QuickAction(
            icon: c.paused ? Icons.play_circle_outline : Icons.pause_rounded,
            label: c.paused ? 'Resume' : 'Pause',
            onTap: mining && !stopping && c.canControl && c.summary != null
                ? () => c.setPaused(!c.paused)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: QuickAction(
            icon: Icons.speed_rounded,
            label: 'Benchmark',
            onTap: running || c.busy ? null : () => benchmark(context),
          ),
        ),
      ],
    );
  }

  Widget session(BuildContext context) {
    final p = Palette.of(context);
    final s = c.summary;
    final shares = s?.shares;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Session'),
        Panel(
          children: [
            if (c.phase == Phase.mining) ...[
              InfoRow(
                'Pool',
                s?.poolUrl.isNotEmpty == true
                    ? s!.poolUrl
                    : c.enabledPools.first.url,
              ),
              InfoRow(
                'Connection',
                s?.poolConnected == true ? 'Connected' : 'Connecting',
                color: s?.poolConnected == true ? p.success : p.warning,
              ),
              InfoRow(
                'Shares',
                shares == null
                    ? '—'
                    : '${count(shares.accepted)} accepted, '
                          '${count(shares.rejected)} rejected of ${count(shares.submitted)}',
                color: (shares?.rejected ?? 0) > 0 ? p.warning : null,
              ),
            ],
            InfoRow('Hashes', s == null ? '—' : count(s.hashes)),
            InfoRow('Uptime', s == null ? '—' : duration(s.uptime)),
            InfoRow(
              'Workers',
              s == null || s.threads == 0
                  ? 'Starting'
                  : '${s.threads} on ${s.nodes} NUMA node${s.nodes == 1 ? '' : 's'}',
            ),
            if (s != null && s.threads > 0)
              InfoRow(
                'Huge pages',
                '${s.hugeScratchpads} of ${s.threads} scratchpads, '
                    '${s.hugeDatasets} dataset${s.hugeDatasets == 1 ? '' : 's'}',
              ),
            if (c.phase == Phase.mining && s != null)
              InfoRow(
                'Developer fee',
                '${s.devFee}, ${s.devPhase ? 'mining for the developer now' : 'mining for you now'}',
                color: s.devPhase ? p.warning : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget device(BuildContext context) {
    final d = c.device;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('This device'),
        if (d == null)
          Notice(
            'The miner could not read this device: ${c.deviceError ?? 'unknown error'}',
            tone: Tone.danger,
          )
        else
          Panel(
            children: [
              InfoRow('CPU', d.summary),
              InfoRow(
                'Logical CPUs',
                '${d.logical}, ${d.selected} chosen by default',
              ),
              InfoRow(
                'Free memory',
                d.memory == null ? 'Not reported' : bytes(d.memory!),
              ),
              InfoRow(
                'RandomX',
                !jitAllowed
                    ? 'Interpreter (iOS forbids JIT)'
                    : d.jit
                    ? 'JIT compiler for ${d.arch}'
                    : 'Interpreter (no JIT for ${d.arch})',
              ),
              InfoRow(
                'Threads',
                profileThreads(c.store.section('cpu')['rx'])?.toString() ??
                    (c.store.section('cpu')['rx'] == null
                        ? 'Automatic'
                        : 'Named profile'),
              ),
              InfoRow('Memory mode', switch (c.store.section(
                'randomx',
              )['mode']) {
                'fast' => 'Fast, 2.3 GiB dataset',
                'light' => 'Light, 256 MiB cache',
                _ => 'Automatic',
              }),
            ],
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: mono(size: 11, color: p.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(size: 13, weight: FontWeight.w600, color: p.strong),
          ),
        ],
      ),
    );
  }
}

/// Recent hashrate as a step line over a faint grid.
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key});
  final List<double> values;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CustomPaint(
      painter: _SparkPainter(List.of(values), p.accent, p.border),
      size: Size.infinite,
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.line, this.grid);
  final List<double> values;
  final Color line, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = grid;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) return;
    final top = values.reduce((a, b) => a > b ? a : b);
    if (top <= 0) return;
    final step = size.width / (MinerController.sampleLimit - 1);
    final start = size.width - step * (values.length - 1);
    final path = Path();
    for (final (i, v) in values.indexed) {
      final point = Offset(
        start + step * i,
        size.height * (1 - v / (top * 1.1)),
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(start, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = line.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}
