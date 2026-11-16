import 'package:material_ui/material_ui.dart';

import 'theme.dart';

String clock(DateTime time) => time.toLocal().toString().substring(11, 19);

void notify(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

enum Tone { info, warning, danger, success }

Color toneColor(Palette p, Tone tone) => switch (tone) {
  Tone.info => p.accent,
  Tone.warning => p.warning,
  Tone.danger => p.danger,
  Tone.success => p.success,
};

/// A notification-style message: square panel with a coloured edge.
class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    this.tone = Tone.info,
    this.icon = Icons.info_outline_rounded,
    super.key,
  });
  final String text;
  final Tone tone;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = toneColor(p, tone);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(color: p.border),
          right: BorderSide(color: p.border),
          bottom: BorderSide(color: p.border),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: mono(size: 12, color: p.text, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small square tag.
class Pill extends StatelessWidget {
  const Pill(this.label, {this.color, this.icon, super.key});
  final String label;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color ?? p.text),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(
                size: 10.5,
                weight: FontWeight.w600,
                color: color ?? p.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A square action tile used in a row of equal cells.
class QuickAction extends StatelessWidget {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.badge,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final String? badge;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onTap != null;
    final fg = !enabled
        ? p.muted
        : primary
        ? p.onAccent
        : p.strong;
    return Material(
      color: primary && enabled ? p.accent : p.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: primary && enabled ? p.accent : p.inputBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 62,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    color: p.warning,
                    child: Text(
                      badge!,
                      style: mono(
                        size: 9,
                        weight: FontWeight.w700,
                        color: const Color(0xFF1F1F1F),
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
}

/// Tree-style section header: chevron, uppercase title and a count.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.title, {
    this.trailing,
    this.expanded,
    this.onTap,
    super.key,
  });
  final String title;
  final Widget? trailing;

  /// When set, the header shows a chevron and toggles through [onTap].
  final bool? expanded;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Row(
          children: [
            if (expanded != null)
              Icon(
                expanded!
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: p.text,
              )
            else
              const SizedBox(width: 2),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: mono(
                  size: 11,
                  spacing: 1,
                  weight: FontWeight.w700,
                  color: p.text,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: mono(size: 12, color: Palette.of(context).muted)),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 28, color: p.muted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: mono(size: 14, weight: FontWeight.w700, color: p.strong),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: mono(size: 12, color: p.muted, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Bottom sheet frame with a title, scrollable body and keyboard padding.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    required this.title,
    required this.children,
    this.actions = const [],
    this.top = 0,
    super.key,
  });
  final String title;
  final List<Widget> children, actions;
  final double top;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, top, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                ...children,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      for (final (i, action) in actions.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: action),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
