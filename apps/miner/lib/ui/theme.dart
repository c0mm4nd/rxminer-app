import 'package:material_ui/material_ui.dart';

/// Editor-style type: one monospace family.
const monoFamily = 'RxMono';

TextStyle mono({
  double? size,
  FontWeight? weight,
  Color? color,
  double? height,
  double? spacing,
}) => TextStyle(
  fontFamily: monoFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: spacing,
);

// Semantic colours taken from VS Code's Dark Modern and Light Modern themes.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.background,
    required this.surface,
    required this.raised,
    required this.hover,
    required this.border,
    required this.input,
    required this.inputBorder,
    required this.text,
    required this.strong,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.link,
    required this.selection,
    required this.status,
    required this.onStatus,
    required this.success,
    required this.warning,
    required this.danger,
  });
  final Color background, surface, raised, hover, border, input, inputBorder;
  final Color text, strong, muted, accent, onAccent, link;
  final Color selection, status, onStatus;
  final Color success, warning, danger;

  static const dark = Palette(
    background: Color(0xFF181818),
    surface: Color(0xFF1F1F1F),
    raised: Color(0xFF2B2B2B),
    hover: Color(0xFF2A2D2E),
    border: Color(0xFF2B2B2B),
    input: Color(0xFF313131),
    inputBorder: Color(0xFF3C3C3C),
    text: Color(0xFFCCCCCC),
    strong: Color(0xFFFFFFFF),
    muted: Color(0xFF9D9D9D),
    accent: Color(0xFF0078D4),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF4DAAFC),
    selection: Color(0xFF04395E),
    status: Color(0xFF0078D4),
    onStatus: Color(0xFFFFFFFF),
    success: Color(0xFF2EA043),
    warning: Color(0xFFCCA700),
    danger: Color(0xFFF85149),
  );
  static const light = Palette(
    background: Color(0xFFF8F8F8),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF0F0F0),
    hover: Color(0xFFF2F2F2),
    border: Color(0xFFE5E5E5),
    input: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFCECECE),
    text: Color(0xFF3B3B3B),
    strong: Color(0xFF1F1F1F),
    muted: Color(0xFF6E6E6E),
    accent: Color(0xFF005FB8),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF005FB8),
    selection: Color(0xFFDCEAF8),
    status: Color(0xFF005FB8),
    onStatus: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFBF8803),
    danger: Color(0xFFC72E0F),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;
  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      hover: mix(hover, other.hover),
      border: mix(border, other.border),
      input: mix(input, other.input),
      inputBorder: mix(inputBorder, other.inputBorder),
      text: mix(text, other.text),
      strong: mix(strong, other.strong),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      link: mix(link, other.link),
      selection: mix(selection, other.selection),
      status: mix(status, other.status),
      onStatus: mix(onStatus, other.onStatus),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  // Square corners throughout, like editor panels and controls.
  const square = RoundedRectangleBorder();
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: brightness,
      ).copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        secondary: p.accent,
        surface: p.surface,
        onSurface: p.text,
        onSurfaceVariant: p.muted,
        surfaceContainerLowest: p.background,
        surfaceContainerLow: p.surface,
        surfaceContainer: p.surface,
        surfaceContainerHigh: p.raised,
        surfaceContainerHighest: p.raised,
        outline: p.inputBorder,
        outlineVariant: p.border,
        error: p.danger,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: monoFamily,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
  );
  final t = base.textTheme.apply(bodyColor: p.text, displayColor: p.strong);
  final text = t.copyWith(
    displaySmall: t.displaySmall?.copyWith(
      fontSize: 34,
      fontWeight: FontWeight.w600,
      letterSpacing: -1,
    ),
    headlineMedium: t.headlineMedium?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineSmall: t.headlineSmall?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: t.titleLarge?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: t.titleMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: t.titleSmall?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 14),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 13),
    bodySmall: t.bodySmall?.copyWith(fontSize: 11.5, color: p.muted),
    labelLarge: t.labelLarge?.copyWith(fontSize: 13),
  );
  final label = mono(size: 13, weight: FontWeight.w600);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  final squareInput = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: p.inputBorder),
  );
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    canvasColor: p.surface,
    dividerColor: p.border,
    splashFactory: InkRipple.splashFactory,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.strong,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 12,
      toolbarHeight: 48,
      titleTextStyle: mono(size: 14, weight: FontWeight.w700, color: p.strong),
      shape: Border(bottom: BorderSide(color: p.border)),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.border)),
    ),
    dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: p.muted,
      textColor: p.text,
      titleTextStyle: mono(
        size: 13.5,
        weight: FontWeight.w600,
        color: p.strong,
      ),
      subtitleTextStyle: mono(size: 11.5, color: p.muted, height: 1.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      dense: true,
      shape: square,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        disabledBackgroundColor: p.raised,
        disabledForegroundColor: p.muted,
        shape: square,
        padding: buttonPadding,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.strong,
        side: BorderSide(color: p.inputBorder),
        shape: square,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.link,
        shape: square,
        padding: buttonPadding,
        textStyle: label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: square),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: mono(color: p.muted),
      hintStyle: mono(color: p.muted),
      prefixIconColor: p.muted,
      suffixIconColor: p.muted,
      border: squareInput,
      enabledBorder: squareInput,
      focusedBorder: squareInput.copyWith(
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.inputBorder)),
      titleTextStyle: mono(size: 15, weight: FontWeight.w700, color: p.strong),
      contentTextStyle: mono(size: 13, color: p.text, height: 1.5),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.inputBorder,
      dragHandleSize: const Size(36, 3),
      shape: Border(top: BorderSide(color: p.accent, width: 2)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.raised,
      contentTextStyle: mono(size: 13, color: p.strong),
      shape: RoundedRectangleBorder(side: BorderSide(color: p.inputBorder)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.background,
      indicatorColor: Colors.transparent,
      indicatorShape: square,
      selectedIconTheme: IconThemeData(color: p.strong),
      unselectedIconTheme: IconThemeData(color: p.muted),
      selectedLabelTextStyle: mono(
        size: 11,
        weight: FontWeight.w600,
        color: p.strong,
      ),
      unselectedLabelTextStyle: mono(size: 11, color: p.muted),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: square,
      side: BorderSide(color: p.inputBorder, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? p.accent : p.input,
      ),
      checkColor: WidgetStatePropertyAll(p.onAccent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? p.accent : p.muted,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.selection,
      side: BorderSide(color: p.inputBorder),
      labelStyle: mono(size: 12, color: p.text),
      secondaryLabelStyle: mono(size: 12, color: p.strong),
      shape: square,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        selectedBackgroundColor: p.selection,
        selectedForegroundColor: p.strong,
        side: BorderSide(color: p.inputBorder),
        shape: square,
        textStyle: mono(size: 12.5, weight: FontWeight.w600),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: mono(size: 13, color: p.text),
      shape: RoundedRectangleBorder(side: BorderSide(color: p.inputBorder)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.raised,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.raised,
        border: Border.all(color: p.inputBorder),
      ),
      textStyle: mono(size: 12, color: p.strong),
    ),
  );
}
