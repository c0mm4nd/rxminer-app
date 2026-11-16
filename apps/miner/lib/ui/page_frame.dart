import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets.dart';

/// Secondary page frame: app bar, scrolling body and an optional pinned button.
class FeaturePage extends StatelessWidget {
  const FeaturePage({
    required this.title,
    required this.children,
    this.actions = const [],
    this.bottom,
    super.key,
  });
  final String title;
  final List<Widget> children, actions;

  /// Pinned under the list, e.g. the main button of a flow.
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: children,
              ),
            ),
          ),
        ),
        if (bottom != null)
          Container(
            decoration: BoxDecoration(
              color: Palette.of(context).background,
              border: Border(
                top: BorderSide(color: Palette.of(context).border),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SafeArea(
              top: false,
              child: SizedBox(width: double.infinity, child: bottom!),
            ),
          ),
      ],
    ),
  );
}

/// A label/value line for detail panels.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    this.copy = false,
    this.color,
    super.key,
  });
  final String label, value;
  final bool copy;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: mono(size: 12, color: p.muted)),
          ),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: mono(size: 12.5, color: color ?? p.strong),
            ),
          ),
          if (copy) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) notify(context, 'Copied');
              },
              child: Icon(Icons.copy_rounded, size: 14, color: p.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A bordered square panel used to group content on feature pages.
/// It is a [Material] so list tiles inside it keep their ink.
class Panel extends StatelessWidget {
  const Panel({required this.children, this.padding, super.key});
  final List<Widget> children;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
