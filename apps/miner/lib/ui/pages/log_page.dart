import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../controller.dart';
import '../theme.dart';
import '../widgets.dart';

/// Line colours follow the command-line miner's own categories.
Color lineColor(Palette p, String line) {
  if (line.startsWith('rxminer:') ||
      line.startsWith('[net] user connection:') ||
      (line.startsWith('[net] pool ') && line.contains(' failed:'))) {
    return p.danger;
  }
  if (line.contains('unavailable') ||
      line.contains('initialization failed') ||
      line.startsWith('[config] reload rejected:') ||
      line.startsWith('[rx] memory budget')) {
    return p.warning;
  }
  if (line.startsWith('[speed] ') ||
      line.startsWith('benchmark finished:') ||
      line == 'benchmark checksum verified' ||
      line == '[net] user login accepted' ||
      (line.startsWith('[rx] ') && line.contains(' ready ('))) {
    return p.success;
  }
  if (line.startsWith('[net]') || line.startsWith('[http]')) return p.link;
  if (line.startsWith('[health]') || line.startsWith('dev fee:')) {
    return p.muted;
  }
  if (line.startsWith('RxMiner ')) return p.strong;
  return p.text;
}

class LogPage extends StatefulWidget {
  const LogPage({required this.c, super.key});
  final MinerController c;
  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final scroll = ScrollController();
  bool follow = true;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (!scroll.hasClients) return;
      final atEnd =
          scroll.position.pixels >= scroll.position.maxScrollExtent - 24;
      if (atEnd != follow) setState(() => follow = atEnd);
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lines = widget.c.log.lines;
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: SectionLabel(
            'Miner log',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${lines.length} lines',
                  style: mono(size: 11, color: p.muted),
                ),
                IconButton(
                  tooltip: 'Copy the log',
                  onPressed: lines.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: lines.join('\n')),
                          );
                          if (context.mounted) notify(context, 'Copied');
                        },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? const EmptyState(
                  icon: Icons.notes_rounded,
                  title: 'Nothing logged yet',
                  subtitle:
                      'Messages from the miner appear here once it starts.',
                )
              : Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border.all(color: p.border),
                  ),
                  child: SelectionArea(
                    child: ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: lines.length,
                      itemBuilder: (context, i) => Text(
                        lines[i],
                        style: mono(
                          size: 11.5,
                          height: 1.5,
                          color: lineColor(p, lines[i]),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
