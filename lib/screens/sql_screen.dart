import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart' as music_provider;

class SqlScreen extends StatefulWidget {
  const SqlScreen({super.key});

  @override
  State<SqlScreen> createState() => _SqlScreenState();
}

class _SqlScreenState extends State<SqlScreen> {
  late Future<_DbOverview> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _overviewFuture = _loadOverview();
  }

  Future<_DbOverview> _loadOverview() async {
    try {
      final db = await DatabaseHelper().database;

      // Fetch tables from sqlite_master
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );

      // Build counts per table
      final Map<String, int> counts = {};
      for (final row in tables) {
        final name = row['name'] as String;
        try {
          final cntRes = await db.rawQuery('SELECT COUNT(*) as c FROM $name');
          final c = (cntRes.first['c'] as int?) ?? 0;
          counts[name] = c;
        } catch (e) {
          debugPrint('Error counting records in table $name: $e');
          counts[name] = 0;
        }
      }

      // Fetch some domain data
      final songs = await db.query(DatabaseHelper.tableSongs, orderBy: 'id DESC', limit: 100);
      final artists = await db.query(DatabaseHelper.tableArtists, orderBy: 'id DESC', limit: 100);
      final genres = await db.query(DatabaseHelper.tableGenres, orderBy: 'id DESC', limit: 100);
      final playlists = await db.query(DatabaseHelper.tablePlaylists, orderBy: 'id');

      // Fetch songs for each playlist
      final playlistSongs = <int, List<Map<String, Object?>>>{};
      for (final playlist in playlists) {
        final playlistId = playlist['id'] as int;
        try {
          final songs = await db.rawQuery('''
            SELECT s.*, ps.position
            FROM ${DatabaseHelper.tableSongs} s
            JOIN ${DatabaseHelper.tablePlaylistSongs} ps ON s.id = ps.song_id
            WHERE ps.playlist_id = ?
            ORDER BY ps.position
          ''', [playlistId]);
          playlistSongs[playlistId] = songs;
        } catch (e) {
          debugPrint('Error fetching songs for playlist $playlistId: $e');
          playlistSongs[playlistId] = [];
        }
      }

      return _DbOverview(
        tableNames: tables.map((e) => e['name'] as String).toList(),
        counts: counts,
        songs: songs,
        artists: artists,
        genres: genres,
        playlists: playlists,
        playlistSongs: playlistSongs,
      );
    } catch (e) {
      debugPrint('Error loading database overview: $e');
      // Return empty overview on error
      return _DbOverview(
        tableNames: [],
        counts: {},
        songs: [],
        artists: [],
        genres: [],
        playlists: [],
        playlistSongs: {},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQL Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() {
                _overviewFuture = _loadOverview();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<_DbOverview>(
        future: _overviewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error: ${snapshot.error}'),
              ),
            );
          }
          final data = snapshot.data!;
          final allEmpty = data.counts.values.every((c) => c == 0);
          return DefaultTabController(
            length: 6,
            child: Column(
              children: [
                if (allEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Database is empty. Music files will be automatically added when you play songs.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    isScrollable: true,
                    tabs: [
                      const Tab(text: 'Tables'),
                      Tab(text: 'Songs (${data.songs.length})'),
                      Tab(text: 'Artists (${data.artists.length})'),
                      Tab(text: 'Genres (${data.genres.length})'),
                      Tab(text: 'Playlists (${data.playlists.length})'),
                      const Tab(text: 'Schema'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _TablesTab(tableNames: data.tableNames, counts: data.counts),
                      _SimpleListTab(
                        titleKey: 'title',
                        subtitleBuilder: (m) => 'id: ${m['id']}  •  duration: ${m['duration']}',
                        rows: data.songs,
                      ),
                      _SimpleListTab(
                        titleKey: 'name',
                        subtitleBuilder: (m) => 'id: ${m['id']}',
                        rows: data.artists,
                      ),
                      _SimpleListTab(
                        titleKey: 'name',
                        subtitleBuilder: (m) => 'id: ${m['id']}',
                        rows: data.genres,
                      ),
                      _buildPlaylistsTab(context, data),
                      _buildSchemaTab(context, data),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistsTab(BuildContext context, _DbOverview data) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: data.playlists.length,
      itemBuilder: (context, index) {
        final playlist = data.playlists[index];
        final playlistId = playlist['id'] as int;
        final songs = data.playlistSongs[playlistId] ?? [];
        final isNowPlaying = playlistId == DatabaseHelper.nowPlayingPlaylistId;
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: ExpansionTile(
            leading: isNowPlaying 
                ? const Icon(Icons.play_arrow, color: Colors.green)
                : const Icon(Icons.playlist_play),
            title: Text(
              playlist['name'] as String? ?? 'Unnamed Playlist',
              style: TextStyle(
                fontWeight: isNowPlaying ? FontWeight.bold : FontWeight.normal,
                color: isNowPlaying ? Colors.green : null,
              ),
            ),
            subtitle: Text('${songs.length} songs'),
            children: [
              if (playlist['description'] != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                  child: Text(playlist['description'].toString()),
                ),
              if (songs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No songs in this playlist'),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: songs.length,
                  itemBuilder: (context, songIndex) {
                    final song = songs[songIndex];
                    return ListTile(
                      leading: Text('${songIndex + 1}.'),
                      title: Text(song['title']?.toString() ?? 'Unknown Title'),
                      subtitle: Text(song['artists']?.toString() ?? 'Unknown Artist'),
                      trailing: Text(
                        _formatDuration(Duration(milliseconds: (song['duration'] as int?) ?? 0)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  Widget _buildSchemaTab(BuildContext context, _DbOverview data) {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        const Text('Tables', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        ...data.tableNames.map((name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text('• $name (${data.counts[name] ?? 0} records)'),
        )).toList(),
      ],
    );
  }
}

class _TablesTab extends StatelessWidget {
  final List<String> tableNames;
  final Map<String, int> counts;
  const _TablesTab({required this.tableNames, required this.counts});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: tableNames.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final name = tableNames[index];
        final count = counts[name] ?? 0;
        return ListTile(
          title: Text(name),
          trailing: CircleAvatar(
            radius: 14,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            child: Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          onTap: () async {
            // On tap: show first 100 rows
            final db = await DatabaseHelper().database;
            final rows = await db.query(name, limit: 100);
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _RowsScreen(table: name, rows: rows),
              ),
            );
          },
        );
      },
    );
  }
}

class _RowsScreen extends StatelessWidget {
  final String table;
  final List<Map<String, Object?>> rows;
  const _RowsScreen({required this.table, required this.rows});

  @override
  Widget build(BuildContext context) {
    final columns = rows.isEmpty ? <String>[] : rows.first.keys.toList();
    return Scaffold(
      appBar: AppBar(title: Text('$table (first ${rows.length})')),
      body: rows.isEmpty
          ? const Center(child: Text('No rows'))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [for (final c in columns) DataColumn(label: Text(c))],
                rows: rows
                    .map(
                      (r) => DataRow(
                        cells: [
                          for (final c in columns)
                            DataCell(SizedBox(
                              width: 200,
                              child: Text(
                                '${r[c]}',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 3,
                              ),
                            )),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}

class _SimpleListTab extends StatelessWidget {
  final String titleKey;
  final String Function(Map<String, Object?>) subtitleBuilder;
  final List<Map<String, Object?>> rows;

  const _SimpleListTab({
    required this.titleKey,
    required this.subtitleBuilder,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        final title = row[titleKey]?.toString() ?? '(null)';
        return ListTile(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitleBuilder(row),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _DbOverview {
  final List<String> tableNames;
  final Map<String, int> counts;
  final List<Map<String, Object?>> songs;
  final List<Map<String, Object?>> artists;
  final List<Map<String, Object?>> genres;
  final List<Map<String, Object?>> playlists;
  final Map<int, List<Map<String, Object?>>> playlistSongs;

  _DbOverview({
    required this.tableNames,
    required this.counts,
    required this.songs,
    required this.artists,
    required this.genres,
    required this.playlists,
    required this.playlistSongs,
  });
}
