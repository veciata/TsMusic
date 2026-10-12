import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/utils/lrc_parser.dart';

void main() {
  test('parses timestamps and sorts lines by time', () {
    final lines = parseLrc('[00:10.00]Second\n[00:02.50]First');
    expect(lines.map((line) => line.text), ['First', 'Second']);
    expect(lines.first.time, const Duration(seconds: 2, milliseconds: 500));
  });

  test('supports multiple timestamps on one line', () {
    final lines = parseLrc('[00:01.00][00:05.00]Repeat');
    expect(lines, hasLength(2));
    expect(lines[0].time, const Duration(seconds: 1));
    expect(lines[1].time, const Duration(seconds: 5));
    expect(lines.every((line) => line.text == 'Repeat'), isTrue);
  });

  test('ignores metadata tags and untimed lines', () {
    final lines = parseLrc(
      '[ar:Artist]\n[ti:Title]\nNot timed\n[00:03.00]Real',
    );
    expect(lines, hasLength(1));
    expect(lines.single.text, 'Real');
  });

  test('normalises the fractional part across 1-3 digits', () {
    expect(
      parseLrc('[01:02.5]a').single.time,
      const Duration(minutes: 1, seconds: 2, milliseconds: 500),
    );
    expect(
      parseLrc('[01:02.05]a').single.time,
      const Duration(minutes: 1, seconds: 2, milliseconds: 50),
    );
    expect(
      parseLrc('[01:02.123]a').single.time,
      const Duration(minutes: 1, seconds: 2, milliseconds: 123),
    );
  });

  test('accepts comma-separated fractions', () {
    expect(
      parseLrc('[00:01,50]a').single.time,
      const Duration(seconds: 1, milliseconds: 500),
    );
  });
}
