import 'package:tsmusic/models/lyrics.dart';

final RegExp _timestamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.,](\d{1,3}))?\]');

/// Parses LRC text into timestamped [LyricLine]s sorted by time.
///
/// Understands `mm:ss`, `mm:ss.xx` and `mm:ss.xxx` timestamps, multiple
/// timestamps on one line (`[00:01.00][00:05.00]text`), and ignores metadata
/// tags such as `[ar:...]` / `[ti:...]` and untimed lines.
List<LyricLine> parseLrc(String input) {
  final result = <LyricLine>[];
  for (final raw in input.split('\n')) {
    final matches = _timestamp.allMatches(raw);
    if (matches.isEmpty) continue;
    final text = raw.substring(matches.last.end).trim();
    if (text.isEmpty) continue;
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      result.add(
        LyricLine(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: _fractionToMillis(match.group(3)),
          ),
          text: text,
        ),
      );
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

int _fractionToMillis(String? fraction) {
  if (fraction == null || fraction.isEmpty) return 0;
  switch (fraction.length) {
    case 1:
      return int.parse(fraction) * 100;
    case 2:
      return int.parse(fraction) * 10;
    default:
      return int.parse(fraction.substring(0, 3));
  }
}
