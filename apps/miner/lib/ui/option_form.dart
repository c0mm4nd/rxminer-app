import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../options.dart';
import 'theme.dart';
import 'widgets.dart';

/// Edits [field] inside [data] in place. Text-like fields report parse
/// errors through [onError] with the field key, or null once valid.
class OptionTile extends StatefulWidget {
  const OptionTile({
    required this.field,
    required this.data,
    required this.onChanged,
    required this.onError,
    this.enabled = true,
    super.key,
  });
  final OptionField field;
  final Map<String, Object?> data;
  final VoidCallback onChanged;
  final void Function(String key, String? error) onError;
  final bool enabled;
  @override
  State<OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<OptionTile> {
  OptionField get f => widget.field;
  Object? get raw => readPath(widget.data, f.path);
  bool get isSet => raw != null;
  Object? get value => raw ?? f.fallback;
  late final text = TextEditingController(text: _format(raw));
  String? error;

  static String _format(Object? value) => switch (value) {
    null => '',
    String s => s,
    _ => jsonEncode(value),
  };

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void set(Object? v) {
    writePath(widget.data, f.path, v);
    widget.onChanged();
    setState(() {});
  }

  void reset() {
    text.text = '';
    setError(null);
    set(null);
  }

  void setError(String? message) {
    if (message == error) return;
    setState(() => error = message);
    widget.onError(f.key, message);
  }

  void typed(String input) {
    final s = input.trim();
    if (s.isEmpty) {
      setError(null);
      return set(null);
    }
    switch (f.kind) {
      case Kind.integer:
        final n = int.tryParse(s);
        if (n == null) return setError('Enter a whole number.');
        if ((f.min != null && n < f.min!) || (f.max != null && n > f.max!)) {
          return setError('Enter ${f.min} to ${f.max}.');
        }
        setError(null);
        set(n);
      case Kind.json:
        try {
          final v = jsonDecode(s);
          setError(null);
          set(v);
        } on FormatException {
          setError('This is not valid JSON.');
        }
      default:
        setError(null);
        set(input);
    }
  }

  Future<void> choose() async {
    final picked = await showModalBottomSheet<(Object?,)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SheetFrame(
        title: f.label,
        children: [
          for (final (v, label) in f.choices)
            ListTile(
              title: Text(label),
              trailing: v == value ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, (v,)),
            ),
        ],
      ),
    );
    if (picked != null) set(picked.$1);
  }

  Widget details(Palette p) {
    final note = f.note?.call();
    final fallback = f.fallback == null
        ? ''
        : ', default ${f.describe(f.fallback)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (f.help.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(f.help, style: mono(size: 11.5, color: p.muted, height: 1.4)),
        ],
        const SizedBox(height: 2),
        Text(
          f.inConfig
              ? 'Key ${f.key}$fallback'
              : 'Kept in the app’s settings, not in config.json$fallback',
          style: mono(size: 10.5, color: p.muted),
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note, style: mono(size: 11.5, color: p.warning, height: 1.4)),
        ],
      ],
    );
  }

  Widget? resetButton() => isSet
      ? IconButton(
          tooltip: 'Use the default',
          onPressed: widget.enabled ? reset : null,
          icon: const Icon(Icons.undo_rounded, size: 16),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final title = Text(f.label);
    switch (f.kind) {
      case Kind.boolean:
        return CheckboxListTile(
          value: value == true,
          onChanged: widget.enabled ? (v) => set(v ?? false) : null,
          title: title,
          subtitle: details(p),
          secondary: resetButton(),
          controlAffinity: ListTileControlAffinity.trailing,
        );
      case Kind.choice:
        return ListTile(
          enabled: widget.enabled,
          title: title,
          subtitle: details(p),
          onTap: choose,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                f.describe(value),
                style: mono(size: 12.5, color: isSet ? p.strong : p.muted),
              ),
              const Icon(Icons.chevron_right_rounded),
              ?resetButton(),
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.label,
                      style: mono(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: p.strong,
                      ),
                    ),
                  ),
                  ?resetButton(),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TextField(
                  controller: text,
                  enabled: widget.enabled,
                  onChanged: typed,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: f.kind == Kind.integer
                      ? const TextInputType.numberWithOptions(signed: true)
                      : TextInputType.text,
                  style: mono(size: 12.5, color: p.strong),
                  decoration: InputDecoration(
                    hintText: f.fallback == null
                        ? 'Not set'
                        : _format(f.fallback),
                    errorText: error,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: details(p),
              ),
            ],
          ),
        );
    }
  }
}

/// A list of [fields] in one bordered group.
class OptionGroup extends StatelessWidget {
  const OptionGroup({
    required this.fields,
    required this.data,
    required this.onChanged,
    required this.onError,
    this.disabled = const {},
    super.key,
  });
  final List<OptionField> fields;
  final Map<String, Object?> data;
  final VoidCallback onChanged;
  final void Function(String key, String? error) onError;

  /// Keys shown but not editable on this system.
  final Set<String> disabled;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, field) in fields.indexed) ...[
            if (i > 0) const Divider(),
            OptionTile(
              field: field,
              data: data,
              onChanged: onChanged,
              onError: onError,
              enabled: !disabled.contains(field.key),
            ),
          ],
        ],
      ),
    );
  }
}
