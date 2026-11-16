import 'dart:convert';
import 'dart:io';

/// Reads lines appended to the miner's log file, keeping the last [limit].
class LogTail {
  LogTail(this.file, {this.limit = 2000});
  final File file;
  final int limit;
  final lines = <String>[];
  int _offset = 0;
  String _partial = '';

  /// Reads new bytes and returns whether any complete line arrived. A file
  /// that is missing, or removed or rotated while reading, yields nothing.
  Future<bool> poll() async {
    try {
      return await _read();
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _read() async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length < _offset) reset();
    if (length == _offset) return false;
    final handle = await file.open();
    try {
      await handle.setPosition(_offset);
      final bytes = await handle.read(length - _offset);
      _offset += bytes.length;
      final parts = (_partial + utf8.decode(bytes, allowMalformed: true)).split(
        '\n',
      );
      _partial = parts.removeLast();
      final added = parts.map((l) => l.trimRight()).where((l) => l.isNotEmpty);
      if (added.isEmpty) return false;
      lines.addAll(added);
      if (lines.length > limit) lines.removeRange(0, lines.length - limit);
      return true;
    } finally {
      await handle.close();
    }
  }

  /// Starts after what the file already holds.
  Future<void> skipExisting() async {
    reset();
    if (await file.exists()) _offset = await file.length();
  }

  void reset() {
    lines.clear();
    _offset = 0;
    _partial = '';
  }
}
