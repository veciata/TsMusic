/// Presentation rules for the progress shown during online (HLS) playback.
///
/// An HLS track is delivered as a playlist of short segments. The player
/// reports position and duration for the segment it is currently on, so the
/// raw values restart from zero roughly every 5-7 seconds -- about 43 times on
/// a four minute song. The UI must therefore be fed track-level values, not
/// player-level ones, or the elapsed counter and the seek bar snap backwards
/// repeatedly.
///
/// This is deliberately free of Flutter and of any player, so the rule can be
/// exercised directly.
library;

/// Longest track length worth believing. Guards against absurd values from
/// partially-known metadata (an interrupted resolve can report seconds).
const Duration maxPlausibleTrackDuration = Duration(hours: 3);

/// The length of an online track, given what is known about it.
///
/// [metadataDuration] is the length recorded with the song (search results, a
/// saved playlist); it is authoritative when present. [segmentDuration] is what
/// the player reports, which is one segment rather than the track, so it is
/// only a fallback for the brief window before metadata arrives.
Duration resolveOnlineTrackDuration({
  required Duration metadataDuration,
  required Duration segmentDuration,
}) {
  if (metadataDuration > Duration.zero &&
      metadataDuration <= maxPlausibleTrackDuration) {
    return metadataDuration;
  }
  if (segmentDuration > Duration.zero &&
      segmentDuration <= maxPlausibleTrackDuration) {
    return segmentDuration;
  }
  return Duration.zero;
}

/// The track-level playback position for an online track.
///
/// [banked] is the progress accumulated from segments already completed and
/// [segmentPosition] is the player's position within the segment now playing.
/// The sum counts up smoothly instead of restarting each segment.
///
/// Two corrections keep the displayed value honest:
///
/// * At a boundary the player can still be reporting the segment that has
///   already been banked, which briefly double-counts it. Whenever the result
///   exceeds [trackDuration] the display is pinned to the track length.
/// * A seek makes [banked] meaningless, so callers must reset it; until they
///   do, the position may be clamped rather than exact.
Duration onlineDisplayPosition({
  required Duration banked,
  required Duration segmentPosition,
  required Duration trackDuration,
}) {
  final total = banked + segmentPosition;
  if (trackDuration > Duration.zero && total > trackDuration) {
    return trackDuration;
  }
  if (total < Duration.zero) return Duration.zero;
  return total;
}

/// Whether a sequence of displayed positions is monotonic non-decreasing.
///
/// Used by tests and diagnostics: a backwards step means the UI would visibly
/// jump, which is the defect these rules exist to prevent.
bool isMonotonicProgress(Iterable<Duration> samples) {
  var previous = Duration.zero;
  for (final sample in samples) {
    if (sample < previous) return false;
    previous = sample;
  }
  return true;
}
