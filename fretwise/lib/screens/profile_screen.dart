import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/app_state.dart';
import '../utils/song_id.dart';
import '../widgets/section_header.dart';
import 'shop_screen.dart';

class _SongLogData {
  final String title;
  final String artist;
  final int durationSeconds;
  final String userNote;
  final String aiNote;
  final List<String> recordings;

  const _SongLogData({
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.userNote,
    required this.aiNote,
    required this.recordings,
  });
}

class ProfileScreen extends StatefulWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final int coins;
  final Set<String> ownedItems;
  final List<DiaryEntry> diaryEntries;

  const ProfileScreen({
    super.key,
    required this.t,
    required this.navigate,
    required this.coins,
    required this.ownedItems,
    required this.diaryEntries,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showItemsPage = false;
  bool _showNameEdit = false;
  bool _showDailyLog = false;
  String _dailyLogDate = '';
  List<_SongLogData> _dailyLogSongs = [];
  String _userName = 'Alex Johnson';
  final _nameCtrl = TextEditingController();

  AppTheme get t => widget.t;

  List<ShopItem> get _purchasedItems =>
      ShopItem.items.where((i) => widget.ownedItems.contains(i.id)).toList();

  static const _achievements = [
    ('🔥', '12-Day\nStreak'),
    ('🎸', 'First\nSong'),
    ('⭐', '1K\nXP'),
    ('🏆', '10\nSongs'),
    ('💎', 'Level\n7'),
  ];

  static String _fmtDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    return m < 1 ? '<1 min' : '$m min';
  }

  void _openDailyLog(String date, List<_SongLogData> songs) {
    setState(() {
      _showDailyLog = true;
      _dailyLogDate = date;
      _dailyLogSongs = songs;
    });
  }

  String _fallbackAiNote(String title) {
    return 'Great practice session on "$title"! Keep working on chord transitions and timing consistency.';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _sessionsStream {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            children: [
              // Avatar + name
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Column(
                  children: [
                    Container(
                      width: 84, height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.accent,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8)],
                      ),
                      child: const Center(
                        child: Text('A', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_userName,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: t.text, fontFamily: 'Georgia')),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            _nameCtrl.text = _userName;
                            setState(() => _showNameEdit = true);
                          },
                          child: Icon(Icons.settings, size: 16, color: t.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Guitar enthusiast · Level 7', style: TextStyle(fontSize: 13, color: t.textSec)),
                    const SizedBox(height: 16),

                    // Stat badges
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatBadge(icon: Icons.local_fire_department, value: '12', label: 'Streak', color: AppColors.red, t: t),
                        const SizedBox(width: 10),
                        _StatBadge(icon: Icons.access_time, value: '48h', label: 'Practice', color: AppColors.accent, t: t),
                        const SizedBox(width: 10),
                        _StatBadge(emoji: '⭐', value: '${widget.coins}', label: 'Stars', t: t),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: t.border, height: 1),
              ),

              // Badges
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(label: 'Badges', t: t),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _achievements.map((a) => Expanded(
                          child: Column(
                            children: [
                              Container(
                                width: 52, height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.surface,
                                  border: Border.all(color: t.border, width: 1.5),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
                                ),
                                child: Center(child: Text(a.$1, style: const TextStyle(fontSize: 24))),
                              ),
                              const SizedBox(height: 6),
                              Text(a.$2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: t.textSec, height: 1.3)),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Divider(color: t.border, height: 1),
              ),

              // My Items
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      label: 'My Items',
                      action: 'More',
                      onAction: () => setState(() => _showItemsPage = true),
                      t: t,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: t.border),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
                        ),
                        child: Column(
                          children: [
                            if (_purchasedItems.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Center(child: Text('No items yet — visit the Shop!', style: TextStyle(fontSize: 13, color: t.textMuted))),
                              )
                            else
                              for (int i = 0; i < _purchasedItems.length.clamp(0, 3); i++) ...[
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38, height: 38,
                                        decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(11)),
                                        child: Center(child: Text(_purchasedItems[i].icon, style: const TextStyle(fontSize: 20))),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_purchasedItems[i].name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
                                          Text(_purchasedItems[i].category, style: TextStyle(fontSize: 12, color: t.textSec)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < _purchasedItems.length.clamp(0, 3) - 1)
                                  Divider(color: t.borderLight, height: 1, indent: 14, endIndent: 14),
                              ],
                            Divider(color: t.borderLight, height: 1),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: GestureDetector(
                                onTap: () => widget.navigate('shop'),
                                child: Row(
                                  children: [
                                    Icon(Icons.storefront_outlined, size: 14, color: t.accent),
                                    const SizedBox(width: 6),
                                    Text('Go to Shop', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.accent)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Divider(color: t.border, height: 1),
              ),

              // Practice Diary
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(label: 'Practice Diary', t: t),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _sessionsStream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }

                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text('Error loading sessions: ${snapshot.error}', style: TextStyle(color: AppColors.red)),
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            if (widget.diaryEntries.isNotEmpty) {
                              return Column(
                                children: [
                                  for (final entry in widget.diaryEntries) ...[
                                    _DiaryCard(
                                      t: t,
                                      date: _fmtDate(entry.date),
                                      songs: ['${entry.title} – ${_fmtDuration(entry.duration)}'],
                                      xp: '+${(entry.duration / 10 + 3).clamp(3, 15).floor() * 5} XP',
                                      onTap: () => _openDailyLog(
                                        _fmtDate(entry.date),
                                        [_SongLogData(
                                          title: entry.title,
                                          artist: entry.artist,
                                          durationSeconds: entry.duration,
                                          userNote: entry.userNote,
                                          aiNote: _fallbackAiNote(entry.title),
                                          recordings: [],
                                        )],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                'No practice sessions yet. Finish a session to see your diary here.',
                                style: TextStyle(fontSize: 13, color: t.textMuted),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          return Column(
                            children: [
                              for (final doc in docs) ...[
                                Builder(builder: (context) {
                                  final data = doc.data();
                                  final title = data['title'] as String? ?? 'Untitled';
                                  final artist = data['artist'] as String? ?? '';
                                  final duration = (data['durationSec'] as num?)?.toInt() ?? 0;
                                  final userNote = data['userNote'] as String? ?? '';
                                  final practiceDate = data['practiceDate'] as String? ?? '';
                                  final sessionInfo = data['sessionInfo'] as Map<String, dynamic>?;
                                  final recordings = (data['recordingUrls'] as List?)?.whereType<String>().toList() ?? [];
                                  final displayDate = practiceDate.isNotEmpty
                                      ? _fmtDate(DateTime.tryParse(practiceDate) ?? DateTime.now())
                                      : _fmtDate(DateTime.now());
                                  final aiNote = sessionInfo?['aiComment'] as String? ?? _fallbackAiNote(title);
                                  return Column(
                                    children: [
                                      _DiaryCard(
                                        t: t,
                                        date: displayDate,
                                        songs: ['${title} – ${_fmtDuration(duration)}'],
                                        xp: '+${(duration / 10 + 3).clamp(3, 15).floor() * 5} XP',
                                        onTap: () => _openDailyLog(
                                          displayDate,
                                          [
                                            _SongLogData(
                                              title: title,
                                              artist: artist,
                                              durationSeconds: duration,
                                              userNote: userNote,
                                              aiNote: aiNote,
                                              recordings: recordings,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  );
                                }),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Daily log detail page
        if (_showDailyLog)
          _DailyLogPage(
            t: t,
            date: _dailyLogDate,
            songs: _dailyLogSongs,
            onBack: () => setState(() => _showDailyLog = false),
          ),

        // My Items subpage
        if (_showItemsPage)
          _ItemsPage(t: t, navigate: widget.navigate, items: _purchasedItems, onBack: () => setState(() => _showItemsPage = false)),

        // Name edit modal
        if (_showNameEdit)
          GestureDetector(
            onTap: () => setState(() => _showNameEdit = false),
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: t.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Change Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        style: TextStyle(fontSize: 15, color: t.text),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: t.surfaceAlt,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_nameCtrl.text.trim().isNotEmpty) {
                              setState(() { _userName = _nameCtrl.text.trim(); _showNameEdit = false; });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String value;
  final String label;
  final Color? color;
  final AppTheme t;

  const _StatBadge({this.icon, this.emoji, required this.value, required this.label, required this.t, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          if (emoji != null)
            Text(emoji!, style: const TextStyle(fontSize: 13))
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: t.textSec)),
        ],
      ),
    );
  }
}

class _ItemsPage extends StatelessWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final List<ShopItem> items;
  final VoidCallback onBack;

  const _ItemsPage({required this.t, required this.navigate, required this.items, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.bg,
      child: Column(
        children: [
          Container(
            color: t.surface,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Icon(Icons.arrow_back, size: 22, color: t.text),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('My Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.text))),
                GestureDetector(
                  onTap: () => navigate('shop'),
                  child: Container(
                    decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: const Text('Shop', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Items & power-ups purchased from the shop.', style: TextStyle(fontSize: 13, color: t.textSec)),
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    Center(child: Text('No items yet — visit the Shop!', style: TextStyle(fontSize: 14, color: t.textMuted)))
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.border),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < items.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46, height: 46,
                                    decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(13)),
                                    child: Center(child: Text(items[i].icon, style: const TextStyle(fontSize: 22))),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(items[i].name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
                                        const SizedBox(height: 2),
                                        Text(items[i].desc, style: TextStyle(fontSize: 12, color: t.textSec)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.094), borderRadius: BorderRadius.circular(6)),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    child: const Text('OWNED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.green)),
                                  ),
                                ],
                              ),
                            ),
                            if (i < items.length - 1) Divider(color: t.borderLight, height: 1),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  final AppTheme t;
  final String date;
  final List<String> songs;
  final String xp;
  final VoidCallback? onTap;

  const _DiaryCard({required this.t, required this.date, required this.songs, required this.xp, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text)),
              Text(xp, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accent)),
            ],
          ),
          const SizedBox(height: 10),
          for (final song in songs) ...[
            Row(
              children: [
                Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: t.accent)),
                const SizedBox(width: 7),
                Expanded(child: Text(song, style: TextStyle(fontSize: 13, color: t.textSec))),
              ],
            ),
            const SizedBox(height: 5),
          ],
        ],
      ),
    ),
    );
  }
}

class _DailyLogPage extends StatelessWidget {
  final AppTheme t;
  final String date;
  final List<_SongLogData> songs;
  final VoidCallback onBack;

  const _DailyLogPage({required this.t, required this.date, required this.songs, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.bg,
      child: Column(
        children: [
          Container(
            color: t.surface,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Icon(Icons.arrow_back, size: 22, color: t.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(date, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.text)),
                      Text('${songs.length} song${songs.length == 1 ? '' : 's'} practiced',
                          style: TextStyle(fontSize: 12, color: t.textSec)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  for (final song in songs) ...[
                    _SongLogCard(t: t, song: song),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongLogCard extends StatefulWidget {
  final AppTheme t;
  final _SongLogData song;

  const _SongLogCard({required this.t, required this.song});

  static String _fmtDur(int s) {
    final m = s ~/ 60;
    return m < 1 ? '<1 min' : '$m min';
  }

  @override
  State<_SongLogCard> createState() => _SongLogCardState();
}

class _SongLogCardState extends State<_SongLogCard> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingUrl;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';

  Stream<QuerySnapshot<Map<String, dynamic>>> get _recordingsStream {
    final songId = makeSongId(widget.song.title, widget.song.artist);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('songLibrary')
        .doc(songId)
        .collection('recordings')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback(String url) async {
    if (_playingUrl == url) {
      await _audioPlayer.pause();
      setState(() => _playingUrl = null);
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(url));
    setState(() => _playingUrl = url);
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown date';
    final dt = ts.toDate();
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.t.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Song title + duration
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: widget.t.accentSoft, borderRadius: BorderRadius.circular(11)),
                  child: Icon(Icons.music_note, size: 20, color: widget.t.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.song.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: widget.t.text)),
                      if (widget.song.artist.isNotEmpty)
                        Text(widget.song.artist, style: TextStyle(fontSize: 12, color: widget.t.textSec)),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: widget.t.accentSoft, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 12, color: widget.t.accent),
                      const SizedBox(width: 4),
                      Text(_SongLogCard._fmtDur(widget.song.durationSeconds),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.t.accent)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(color: widget.t.borderLight, height: 1),

          // Your notes
          _LogSection(
            t: widget.t,
            icon: Icons.edit_note_outlined,
            label: 'YOUR NOTES',
            iconColor: const Color(0xFF5B8DEF),
            child: widget.song.userNote.isNotEmpty
                ? Text(widget.song.userNote,
                    style: TextStyle(fontSize: 13, color: widget.t.text, height: 1.6))
                : Text('No notes added for this session.',
                    style: TextStyle(fontSize: 13, color: widget.t.textMuted, fontStyle: FontStyle.italic)),
          ),

          Divider(color: widget.t.borderLight, height: 1),

          // AI Coach notes
          _LogSection(
            t: widget.t,
            icon: Icons.chat_bubble_outline,
            label: 'AI COACH',
            iconColor: const Color(0xFF1A7A5E),
            child: Text(widget.song.aiNote,
                style: TextStyle(fontSize: 13, color: widget.t.text, height: 1.6)),
          ),

          Divider(color: widget.t.borderLight, height: 1),

          // Recordings
          _LogSection(
            t: widget.t,
            icon: Icons.mic_none_outlined,
            label: 'RECORDINGS',
            iconColor: AppColors.red,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _recordingsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  if (widget.song.recordings.isEmpty) {
                    return Text('No recordings found for this song yet.', style: TextStyle(fontSize: 13, color: widget.t.textMuted));
                  }
                  return Column(
                    children: [
                      for (final rec in widget.song.recordings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.t.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: widget.t.borderLight),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.play_circle_outline, size: 20, color: widget.t.accent),
                                const SizedBox(width: 10),
                                Expanded(child: Text(rec,
                                    style: TextStyle(fontSize: 12, color: widget.t.textSec, fontFamily: 'monospace'))),
                                Icon(Icons.download_outlined, size: 18, color: widget.t.textMuted),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                }

                return Column(
                  children: [
                    for (final doc in docs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () {
                            final downloadUrl = doc.data()['downloadUrl'] as String?;
                            if (downloadUrl != null && downloadUrl.isNotEmpty) {
                              _togglePlayback(downloadUrl);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.t.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: widget.t.borderLight),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  _playingUrl == (doc.data()['downloadUrl'] as String?)
                                      ? Icons.pause_circle_outline
                                      : Icons.play_circle_outline,
                                  size: 20,
                                  color: widget.t.accent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.data()['fileName'] as String? ?? 'Recording',
                                        style: TextStyle(fontSize: 12, color: widget.t.textSec, fontFamily: 'monospace'),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTimestamp(doc.data()['createdAt'] as Timestamp?),
                                        style: TextStyle(fontSize: 10, color: widget.t.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.download_outlined, size: 18, color: widget.t.textMuted),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogSection extends StatelessWidget {
  final AppTheme t;
  final IconData icon;
  final String label;
  final Color iconColor;
  final Widget child;

  const _LogSection({required this.t, required this.icon, required this.label, required this.iconColor, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, size: 12, color: iconColor),
              ),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: t.textMuted, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
