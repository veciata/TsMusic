import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/models/lyrics.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/lyrics_provider.dart';
import 'package:tsmusic/providers/music_provider.dart';

/// Opens the lyrics sheet for the track that is currently playing.
void showLyricsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LyricsSheet(),
  );
}

/// Lyrics for the active track, following track changes while open.
class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key});

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  static const double _lineExtent = 44;

  final ScrollController _scrollController = ScrollController();
  String? _requestedKey;
  int _activeIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _requestLoad(Song? song) {
    if (song == null) return;
    final key = LyricsProvider.keyFor(song);
    if (key == _requestedKey) return;
    _requestedKey = key;
    _activeIndex = -1;
    final provider = context.read<LyricsProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.load(song);
    });
  }

  void _followActiveLine(int index) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final target = (index * _lineExtent) - (viewport / 2) + (_lineExtent / 2);
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  int _indexForPosition(List<LyricLine> lines, Duration position) {
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final musicProvider = context.watch<MusicProvider>();
    final lyricsProvider = context.watch<LyricsProvider>();
    final song = musicProvider.activeSong;
    _requestLoad(song);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lyrics, style: theme.textTheme.titleLarge),
                      if (song != null)
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(theme, l10n, musicProvider, lyricsProvider, song),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    AppLocalizations l10n,
    MusicProvider musicProvider,
    LyricsProvider lyricsProvider,
    Song? song,
  ) {
    if (song == null) {
      return _message(theme, l10n.notPlaying);
    }
    if (lyricsProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = lyricsProvider.lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return _message(theme, l10n.noLyricsFound);
    }
    if (!lyrics.hasSynced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          lyrics.plain,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
      );
    }
    return StreamBuilder<Duration>(
      stream: musicProvider.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final index = _indexForPosition(
          lyrics.synced,
          snapshot.data ?? Duration.zero,
        );
        if (index != _activeIndex) {
          _activeIndex = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && index >= 0) _followActiveLine(index);
          });
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 24),
          itemExtent: _lineExtent,
          itemCount: lyrics.synced.length,
          itemBuilder: (context, i) {
            final isActive = i == index;
            return InkWell(
              onTap: () => musicProvider.seek(lyrics.synced[i].time),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    lyrics.synced[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _message(ThemeData theme, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 56,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ),
  );
}
