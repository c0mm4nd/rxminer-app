import 'package:material_ui/material_ui.dart';

const appName = 'RxMiner';

/// The rxminer version plus the app revision, e.g. 0.2.0.1, set by release builds with
/// `--dart-define=APP_VERSION=...`; see scripts/version.py.
const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'development build',
);

/// Miner built into this app; see packages/rxminer/native/Cargo.toml.
/// scripts/version.py checks both against Cargo.lock.
const minerVersion = '0.2.0';
const minerRevision = '6882dfb';
const minerSource = 'github.com/c0mm4nd/rxminer';

/// Fixed developer-fee endpoints in the pinned miner (src/developer.rs).
const devFeeHosts = [
  'pool.hashvault.pro:443',
  'pool.hashvault.sh:443',
  'xmr-hk.kryptex.network:8029',
];

/// The mark: an R built from square blocks, like rows of a dataset.
class RxMark extends StatelessWidget {
  const RxMark({this.height = 32, this.onAccent = false, super.key});
  final double height;
  final bool onAccent;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(height * 0.8, height),
    painter: _MarkPainter(
      onAccent
          ? const [Color(0xFFFFFFFF), Color(0xE0FFFFFF), Color(0xADFFFFFF)]
          : const [Color(0xFF1A85E0), Color(0xFF4DAAFC), Color(0xFF005FB8)],
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.colors);
  final List<Color> colors;
  // A 4x5 grid; each entry is (column, row, colour index).
  static const cells = [
    (0, 0, 0),
    (1, 0, 1),
    (2, 0, 1),
    (0, 1, 0),
    (3, 1, 1),
    (0, 2, 0),
    (1, 2, 1),
    (2, 2, 1),
    (0, 3, 0),
    (2, 3, 2),
    (0, 4, 0),
    (3, 4, 2),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / 5;
    for (final (x, y, c) in cells) {
      canvas.drawRect(
        Rect.fromLTWH(x * unit, y * unit, unit * 0.86, unit * 0.86),
        Paint()..color = colors[c],
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.colors != colors;
}
