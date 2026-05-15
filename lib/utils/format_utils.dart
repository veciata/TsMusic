
String formatDurationFromMs(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '${twoDigits(minutes)}:${twoDigits(seconds)}';
}

String formatDurationFromSeconds(int seconds) {
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainingSeconds';
}
