String hashrate(double value) {
  if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(2)} MH/s';
  if (value >= 1e4) return '${(value / 1e3).toStringAsFixed(2)} kH/s';
  return '${value.toStringAsFixed(1)} H/s';
}

String count(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

String duration(Duration value) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = value.inHours, m = value.inMinutes % 60, s = value.inSeconds % 60;
  if (value.inDays > 0) return '${value.inDays}d ${two(h % 24)}h ${two(m)}m';
  if (h > 0) return '${h}h ${two(m)}m ${two(s)}s';
  return '${m}m ${two(s)}s';
}

String bytes(int value) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var v = value.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

String short(String text, {int head = 8, int tail = 6}) =>
    text.length <= head + tail + 1
    ? text
    : '${text.substring(0, head)}…${text.substring(text.length - tail)}';
