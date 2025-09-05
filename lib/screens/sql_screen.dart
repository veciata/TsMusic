import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/new_music_provider.dart' as music_provider;

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
    final db = await DatabaseHelper().database;

    // Fetch tables from sqlite_master
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    // Build counts per table
    final Map<String, int> counts = {};
    for (final row in tables) {
      final name = row['name'] as String;
      final cntRes = await db.rawQuery('SELECT COUNT(*) as c FROM $name');
      final c = (cntRes.first['c'] as int?) ?? 0;
      counts[name] = c;
    }

    // Fetch some domain data
    final songs = await db.query(DatabaseHelper.tableSongs, orderBy: 'id DESC', limit: 100);
    final artists = await db.query(DatabaseHelper.tableArtists, orderBy: 'id DESC', limit: 100);
    final genres = await db.query(DatabaseHelper.tableGenres, orderBy: 'id DESC', limit: 100);

    return _DbOverview(
      tableNames: tables.map((e) => e['name'] as String).toList(),
      counts: counts,
      songs: songs,
      artists: artists,
      genres: genres,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQL Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync from Library',
            onPressed: () async {
              try {
                final mp = context.read<music_provider.NewMusicProvider>();
                // Ensure songs are loaded
                if (mp.songs.isEmpty) {
                  await mp.loadSongsFromStorage();
                }
                await DatabaseHelper().syncMusicLibrary(mp);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Synced music library to database')),
                );
                setState(() {
                  _overviewFuture = _loadOverview();
                });
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sync failed: $e')),
                );
              }
            },
          ),
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
            length: 4,
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
                            'Database is empty. Tap the Sync button (↻) to import songs from your library.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Tables'),
                      Tab(text: 'Songs'),
                      Tab(text: 'Artists'),
                      Tab(text: 'Genres'),
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

  _DbOverview({
    required this.tableNames,
    required this.counts,
    required this.songs,
    required this.artists,
    required this.genres,
  });
}
