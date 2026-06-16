import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/app_state.dart';
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

  static const _staticDiary = [
    (date: 'May 3, 2026', songs: ['Wonderwall – 22 min', 'Blackbird – 8 min'], note: 'Chord transitions feeling smoother today!', xp: '+85 XP'),
    (date: 'May 2, 2026', songs: ['Hotel California – 30 min'], note: 'Struggled with the solo part, need to slow down.', xp: '+95 XP'),
    (date: 'Apr 30, 2026', songs: ['Wish You Were Here – 20 min', "Knockin' On Heaven's Door – 15 min"], note: 'Great session! Both songs almost complete.', xp: '+110 XP'),
    (date: 'Apr 29, 2026', songs: ['Nothing Else Matters – 25 min'], note: 'Starting to get the fingerpicking pattern.', xp: '+80 XP'),
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
    setState(() { _showDailyLog = true; _dailyLogDate = date; _dailyLogSongs = songs; });
  }

  static String _dummyAiNote(String title) =>
      'Your timing on "$title" is improving steadily. Focus on keeping consistent pressure on chord shapes during transitions — there\'s a small hesitation around the bridge that a few slow-practice reps will fix. Overall a solid session!';

  static List<String> _dummyRecordings(String dateStr) => [
    'rec_${dateStr.replaceAll(', ', '_').replaceAll(' ', '_')}_001.m4a',
    'rec_${dateStr.replaceAll(', ', '_').replaceAll(' ', '_')}_002.m4a',
  ];

  static _SongLogData _parseStaticSong(String songStr, String note, String dateStr) {
    final parts = songStr.split(' – ');
    final title = parts[0];
    final minutes = parts.length > 1 ? int.tryParse(parts[1].replaceAll(' min', '').trim()) ?? 0 : 0;
    return _SongLogData(
      title: title, artist: '',
      durationSeconds: minutes * 60,
      userNote: note,
      aiNote: _dummyAiNote(title),
      recordings: _dummyRecordings(dateStr),
    );
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

                    // Stat progress bars & badges
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _StatProgressBar(icon: Icons.local_fire_department, value: 12, max: 30, unit: '', label: 'Streak', color: AppColors.red, t: t),
                          const SizedBox(height: 12),
                          _StatProgressBar(icon: Icons.access_time, value: 48, max: 60, unit: 'h', label: 'Practice', color: AppColors.accent, t: t),
                          const SizedBox(height: 12),
                          _StatBadge(emoji: '⭐', value: '${widget.coins}', label: 'Stars', t: t),
                        ],
                      ),
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
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFFFFFF),
                                      Color(0xFFE6E6E6),
                                      Color(0xFFB3B3B3),
                                      Color(0xFFE6E6E6),
                                    ],
                                    stops: [0.0, 0.4, 0.6, 1.0],
                                  ),
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      offset: const Offset(2, 4),
                                      blurRadius: 6,
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      offset: const Offset(-2, -2),
                                      blurRadius: 4,
                                    ),
                                  ],
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
                      child: Column(
                        children: [
                          for (int i = 0; i < widget.diaryEntries.length; i++)
                            _DiaryCard(
                              t: t,
                              date: _fmtDate(widget.diaryEntries[i].date),
                              songs: ['${widget.diaryEntries[i].title} – ${_fmtDuration(widget.diaryEntries[i].duration)}'],
                              xp: '+${(widget.diaryEntries[i].duration / 10 + 3).clamp(3, 15).floor() * 5} XP',
                              isLast: false,
                              onTap: () => _openDailyLog(
                                _fmtDate(widget.diaryEntries[i].date),
                                [_SongLogData(
                                  title: widget.diaryEntries[i].title,
                                  artist: widget.diaryEntries[i].artist,
                                  durationSeconds: widget.diaryEntries[i].duration,
                                  userNote: widget.diaryEntries[i].userNote,
                                  aiNote: _dummyAiNote(widget.diaryEntries[i].title),
                                  recordings: _dummyRecordings(_fmtDate(widget.diaryEntries[i].date)),
                                )],
                              ),
                            ),
                          for (int i = 0; i < _staticDiary.length; i++)
                            _DiaryCard(
                              t: t,
                              date: _staticDiary[i].date,
                              songs: _staticDiary[i].songs,
                              xp: _staticDiary[i].xp,
                              isLast: i == _staticDiary.length - 1,
                              onTap: () => _openDailyLog(
                                _staticDiary[i].date,
                                [for (int j = 0; j < _staticDiary[i].songs.length; j++)
                                  _parseStaticSong(_staticDiary[i].songs[j], j == 0 ? _staticDiary[i].note : '', _staticDiary[i].date)],
                              ),
                            ),
                        ],
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

class _StatProgressBar extends StatelessWidget {
  final IconData icon;
  final int value;
  final int max;
  final String unit;
  final String label;
  final Color color;
  final AppTheme t;

  const _StatProgressBar({
    required this.icon,
    required this.value,
    required this.max,
    required this.unit,
    required this.label,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = (value / max).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.textSec)),
              const Spacer(),
              Text('$value$unit / $max$unit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: t.borderLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
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
  final bool isLast;

  const _DiaryCard({required this.t, required this.date, required this.songs, required this.xp, this.onTap, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Node
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12, height: 12,
                  margin: const EdgeInsets.only(top: 24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.accent,
                    border: Border.all(color: t.bg, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: t.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
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
                          Text(date, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
                          Text(xp, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.accent)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final song in songs) ...[
                        Row(
                          children: [
                            Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: t.accentMid)),
                            const SizedBox(width: 7),
                            Expanded(child: Text(song, style: TextStyle(fontSize: 13, color: t.textSec))),
                          ],
                        ),
                        const SizedBox(height: 5),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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

class _SongLogCard extends StatelessWidget {
  final AppTheme t;
  final _SongLogData song;

  const _SongLogCard({required this.t, required this.song});

  static String _fmtDur(int s) {
    final m = s ~/ 60;
    return m < 1 ? '<1 min' : '$m min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
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
                  decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(11)),
                  child: Icon(Icons.music_note, size: 20, color: t.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                      if (song.artist.isNotEmpty)
                        Text(song.artist, style: TextStyle(fontSize: 12, color: t.textSec)),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 12, color: t.accent),
                      const SizedBox(width: 4),
                      Text(_fmtDur(song.durationSeconds),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accent)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(color: t.borderLight, height: 1),

          // Your notes
          _LogSection(
            t: t,
            icon: Icons.edit_note_outlined,
            label: 'YOUR NOTES',
            iconColor: const Color(0xFF5B8DEF),
            child: song.userNote.isNotEmpty
                ? Text(song.userNote,
                    style: TextStyle(fontSize: 13, color: t.text, height: 1.6))
                : Text('No notes added for this session.',
                    style: TextStyle(fontSize: 13, color: t.textMuted, fontStyle: FontStyle.italic)),
          ),

          Divider(color: t.borderLight, height: 1),

          // AI Coach notes
          _LogSection(
            t: t,
            icon: Icons.chat_bubble_outline,
            label: 'AI COACH',
            iconColor: const Color(0xFF1A7A5E),
            child: Text(song.aiNote,
                style: TextStyle(fontSize: 13, color: t.text, height: 1.6)),
          ),

          Divider(color: t.borderLight, height: 1),

          // Recordings
          _LogSection(
            t: t,
            icon: Icons.mic_none_outlined,
            label: 'RECORDINGS',
            iconColor: AppColors.red,
            child: Column(
              children: [
                for (final rec in song.recordings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.borderLight),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.play_circle_outline, size: 20, color: t.accent),
                          const SizedBox(width: 10),
                          Expanded(child: Text(rec,
                              style: TextStyle(fontSize: 12, color: t.textSec, fontFamily: 'monospace'))),
                          Icon(Icons.download_outlined, size: 18, color: t.textMuted),
                        ],
                      ),
                    ),
                  ),
              ],
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
