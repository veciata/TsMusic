import 'dart:math';
import 'package:flutter/material.dart';

class SlidingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double pauseDuration;
  final double scrollSpeed;

  const SlidingText(
    this.text, {
    super.key,
    this.style,
    this.pauseDuration = 2.0,
    this.scrollSpeed = 80,
  });

  @override
  State<SlidingText> createState() => _SlidingTextState();
}

class _SlidingTextState extends State<SlidingText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  bool _needsScroll = false;
  double _textWidth = 0;
  double _containerWidth = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback(_checkOverflow);
  }

  void _checkOverflow(_) {
    if (!mounted) return;
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    _textWidth = textPainter.width;
    _containerWidth = context.size?.width ?? 0;

    if (_textWidth > _containerWidth) {
      setState(() => _needsScroll = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
    }
  }

  Future<void> _startScrolling() async {
    while (mounted && _needsScroll) {
      await Future.delayed(Duration(seconds: widget.pauseDuration.toInt()));
      if (!mounted) return;

      final maxScroll = max(0.0, _textWidth - _containerWidth + 10);
      final slideDuration = Duration(
        milliseconds: max(1, (maxScroll / widget.scrollSpeed * 1000).round()),
      );
      await _scrollController.animateTo(
        maxScroll,
        duration: slideDuration,
        curve: Curves.linear,
      );

      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));

      final returnDuration = Duration(
        milliseconds: max(1, (maxScroll / widget.scrollSpeed * 1000).round()),
      );
      await _scrollController.animateTo(
        0,
        duration: returnDuration,
        curve: Curves.linear,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ClipRect(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, style: widget.style, maxLines: 1),
      ),
    );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
