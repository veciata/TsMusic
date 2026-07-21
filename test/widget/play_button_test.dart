import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Reusable play button widget for testing (mirrors _PlayButton from mini_player)
class TestPlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const TestPlayButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey('play_$isPlaying'),
          size: 26,
        ),
      ),
      onPressed: onPressed,
    ),
  );
}

void main() {
  group('Media button state flips between play and pause', () {
    testWidgets('shows play icon when not playing', (tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TestPlayButton(
              isPlaying: false,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);

      await tester.tap(find.byType(IconButton));
      expect(pressed, isTrue);
    });

    testWidgets('shows pause icon when playing', (tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TestPlayButton(
              isPlaying: true,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      await tester.tap(find.byType(IconButton));
      expect(pressed, isTrue);
    });

    testWidgets('icon flips when isPlaying changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TestPlayButton(
                isPlaying: false,
                onPressed: () {
                  setState(() {
                    // State change handled by parent
                  });
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Rebuild with playing state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TestPlayButton(
                isPlaying: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });
  });
}
