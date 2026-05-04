import 'package:flutter/material.dart';

class SlidingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double pauseDuration;
  final double slideDuration;

  const SlidingText(
    this.text, {
    super.key,
    this.style,
    this.pauseDuration = 2.0,
    this.slideDuration = 3.0,
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
      _startScrolling();
    }
  }

  void _startScrolling() async {
    while (mounted && _needsScroll) {
      await Future.delayed(Duration(seconds: widget.pauseDuration.toInt()));
      if (!mounted) return;

      final maxScroll = _textWidth - _containerWidth + 20;
      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(seconds: widget.slideDuration.toInt()),
        curve: Curves.easeInOut,
      );

      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));

      await _scrollController.animateTo(
        0,
        duration: Duration(seconds: widget.slideDuration.toInt()),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, style: widget.style, maxLines: 1),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
