import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models/song.dart';
import '../models/app_state.dart';
import '../widgets/progress_bar.dart';

class LibraryScreen extends StatefulWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;

  const LibraryScreen({super.key, required this.t, required this.navigate});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _filterFavs = false;
  bool _filterArchived = false;
  String _sortBy = 'date';
  bool _sortAsc = false;
  bool _showSort = false;
  bool _showAddModal = false;
  String? _addError;
  final _titleCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  String _searchQuery = '';
  
  // 儲存每個卡片的 GlobalKey 以便捲動
  final Map<String, GlobalKey> _cardKeys = {};
  
  // 記錄目前正在發光的歌曲 ID (本地狀態)
  String? _localHighlightedId;

  AppTheme get t => widget.t;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    super.dispose();
  }

  // 💡 核心功能：捲動到指定歌曲並觸發 3 秒發光
  void _triggerScrollAndGlow(String songId, AppState appState) {
    // 1. 立刻清空全域狀態，防止 build 函式重複觸發導致閃爍不停
    if (appState.highlightedSongId == songId) {
      appState.setHighlightedSong(null);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 2. 稍微延遲，確保過濾條件清空後的 UI 已經重新排版完成
      Future.delayed(const Duration(milliseconds: 300), () {
        final key = _cardKeys[songId];
        if (key?.currentContext != null) {
          // 3. 捲動到該項目，使其對齊畫面頂部 (alignment: 0.0)
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOutQuart,
            alignment: 0.0, 
          );
          
          if (mounted) {
            // 4. 觸發本地發光狀態
            setState(() => _localHighlightedId = songId);
            
            // 5. 精準 3 秒後自動熄滅
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _localHighlightedId = null);
            });
          }
        }
      });
    });
  }

  void _addSongAI(AppState appState) async {
    final title = _titleCtrl.text.trim();
    final artist = _artistCtrl.text.trim();
    if (title.isEmpty) return;

    setState(() => _showAddModal = false);

    // 1. 呼叫 AI (AppState 內部會判斷是否重複)
    final newSong = await appState.searchSongToLibrary(title, artist);

    if (newSong != null && mounted) {
      // 情況 A: 新歌 -> 跳轉到練習頁面
      widget.navigate('practicing', props: {
        'title': newSong.title,
        'artist': newSong.artist,
        'bpm': newSong.bpm,
        'songId': newSong.id,
      });
    } else {
      // 情況 B: 重複歌曲 (searchSongToLibrary 會回傳 null 並設好全域 highlightedSongId)
      // 我們要強制清空搜尋與過濾，否則該卡片若被隱藏會捲動不到
      setState(() {
        _searchQuery = '';
        _filterFavs = false;
        _filterArchived = false;
      });
      // 接下來 build 函式偵測到全域 ID 後會自動觸發 _triggerScrollAndGlow
    }

    _titleCtrl.clear();
    _artistCtrl.clear();
  }

  List<SongEntry> _getVisibleSongs(List<SongEntry> allSongs) {
    List<SongEntry> all = allSongs.where((s) => s.isArchived == _filterArchived).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      all = all.where((s) => s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q)).toList();
    }
    if (_filterFavs && !_filterArchived) {
      all = all.where((s) => s.isFavorite).toList();
    }
    all.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'date':
          final aDate = a.lastPracticedAt?.toDate().millisecondsSinceEpoch ?? 0;
          final bDate = b.lastPracticedAt?.toDate().millisecondsSinceEpoch ?? 0;
          cmp = aDate.compareTo(bDate);
          break;
        case 'progress': cmp = a.progressPercent.compareTo(b.progressPercent); break;
        case 'title': cmp = a.title.compareTo(b.title); break;
        case 'artist': cmp = a.artist.compareTo(b.artist); break;
        default: cmp = 0;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return all;
  }

  String _sortDirectionLabel(String key) {
    switch (key) {
      case 'date': return _sortAsc ? 'Oldest first' : 'Newest first';
      case 'progress': return _sortAsc ? 'Least → Most' : 'Most → Least';
      case 'title':
      case 'artist': return _sortAsc ? 'A → Z' : 'Z → A';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // 💡 攔截器：一旦偵測到全域有需要高亮的 ID (來自 Inspiration 或本地新增重複)
    if (appState.highlightedSongId != null) {
      final id = appState.highlightedSongId!;
      _filterFavs = false;
      _filterArchived = false;
      _searchQuery = '';
      _triggerScrollAndGlow(id, appState);
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: StreamBuilder<List<SongEntry>>(
                stream: appState.libraryStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allSongs = snapshot.data ?? [];
                  final songs = _getVisibleSongs(allSongs);

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 120),
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Library', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: t.text, fontFamily: 'Georgia')),
                            const SizedBox(height: 4),
                            Text('${allSongs.length} songs', style: TextStyle(fontSize: 14, color: t.textSec)),
                          ],
                        ),
                      ),

                      // Search
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                        child: Container(
                          decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 16, color: t.textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                  style: TextStyle(fontSize: 14, color: t.text),
                                  decoration: InputDecoration(
                                    hintText: 'Search songs, artists…',
                                    hintStyle: TextStyle(color: t.textMuted),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Filters
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Favorites', icon: Icons.favorite, active: _filterFavs, t: t,
                              onTap: () => setState(() { _filterFavs = !_filterFavs; _filterArchived = false; }),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Archived', icon: Icons.archive_outlined, active: _filterArchived, t: t, activeColor: t.textMuted,
                              onTap: () => setState(() { _filterArchived = !_filterArchived; _filterFavs = false; }),
                            ),
                            if (!_filterArchived) ...[
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Sort', icon: Icons.sort, active: _showSort, t: t,
                                onTap: () => setState(() => _showSort = !_showSort),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Sort menu
                      if (_showSort)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: t.border),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30)],
                            ),
                            child: Column(
                              children: [
                                for (final opt in [('date', 'Date Practiced'), ('progress', 'Progress'), ('title', 'Title'), ('artist', 'Artist')])
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      if (_sortBy == opt.$1) { _sortAsc = !_sortAsc; } 
                                      else { _sortBy = opt.$1; _sortAsc = opt.$1 == 'title' || opt.$1 == 'artist'; }
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                      decoration: BoxDecoration(
                                        color: _sortBy == opt.$1 ? t.accentSoft : Colors.transparent,
                                        border: Border(bottom: BorderSide(color: t.borderLight)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(opt.$2, style: TextStyle(fontSize: 14, color: _sortBy == opt.$1 ? t.accent : t.text, fontWeight: _sortBy == opt.$1 ? FontWeight.w700 : FontWeight.w400)),
                                                if (_sortBy == opt.$1) Text(_sortDirectionLabel(opt.$1), style: TextStyle(fontSize: 11, color: t.accent)),
                                              ],
                                            ),
                                          ),
                                          if (_sortBy == opt.$1) Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: t.accent),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                      // Loading state from AI
                      if (appState.isLoadingAddSong)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(backgroundColor: t.border, color: t.accent, minHeight: 6),
                              ),
                              const SizedBox(height: 8),
                              Text('AI is searching for the song tutorial...', style: TextStyle(color: t.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),

                      // Song list
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            if (songs.isEmpty && !appState.isLoadingAddSong)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Center(child: Text(_filterArchived ? 'No archived songs.' : 'No songs yet — add one!', style: TextStyle(fontSize: 14, color: t.textMuted))),
                              ),
                            for (final s in songs) ...[
                              _SongCard(
                                key: _cardKeys.putIfAbsent(s.id, () => GlobalKey()),
                                song: s,
                                t: t,
                                isHighlighted: _localHighlightedId == s.id,
                                onTap: () => widget.navigate('practicing', props: {'title': s.title, 'artist': s.artist, 'bpm': s.bpm, 'songId': s.id}),
                                onFavToggle: () => appState.updateSongStatus(s.id, {'isFavorite': !s.isFavorite}),
                                onArchive: !_filterArchived ? () => appState.updateSongStatus(s.id, {'isArchived': true}) : null,
                                onUnarchive: _filterArchived ? () => appState.updateSongStatus(s.id, {'isArchived': false}) : null,
                                onDelete: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Song?'),
                                      content: Text('Are you sure you want to permanently delete "${s.title}"?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                        TextButton(
                                          onPressed: () {
                                            appState.deleteSong(s.id); 
                                            Navigator.pop(ctx);
                                          },
                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                },  
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),

        // Add Song FAB
        if (!_filterArchived)
          Positioned(
            bottom: 20, left: 20,
            child: GestureDetector(
              onTap: () => setState(() => _showAddModal = true),
              child: Container(
                decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8)]),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Add Song', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),

        // Add Song Modal
        if (_showAddModal)
          GestureDetector(
            onTap: () => setState(() { _showAddModal = false; _addError = null; }),
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
                      Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 20),
                      Text('Add song to library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 18),
                      _ModalField(label: 'SONG TITLE', hint: 'e.g. Stairway to Heaven', controller: _titleCtrl, t: t, onChanged: (_) { if (_addError != null) setState(() => _addError = null); }),
                      if (_addError != null) ...[const SizedBox(height: 6), Text(_addError!, style: TextStyle(fontSize: 12, color: AppColors.red))],
                      const SizedBox(height: 12),
                      _ModalField(label: 'ARTIST', hint: 'e.g. Led Zeppelin', controller: _artistCtrl, t: t, onSubmit: () => _addSongAI(appState)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _addSongAI(appState),
                          style: ElevatedButton.styleFrom(backgroundColor: t.accent, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          child: const Text('Add to Library', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final AppTheme t;
  final Color? activeColor;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.icon, required this.active, required this.t, required this.onTap, this.activeColor});

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? t.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: active ? color : t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: active ? color : t.border)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? Colors.white : t.textSec),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : t.textSec)),
          ],
        ),
      ),
    );
  }
}

class _SongCard extends StatefulWidget {
  final SongEntry song;
  final AppTheme t;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback? onFavToggle;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onDelete;

  const _SongCard({super.key, required this.song, required this.t, required this.onTap, this.isHighlighted = false, this.onFavToggle, this.onArchive, this.onUnarchive, this.onDelete});

  @override
  State<_SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<_SongCard> with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;
  double _offset = 0;
  double? _startX;
  bool _revealed = false;
  bool _pointerMoved = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _glowAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70), 
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 15),
    ]).animate(_glowCtrl);
  }

  @override
  void didUpdateWidget(_SongCard old) {
    super.didUpdateWidget(old);
    if (widget.isHighlighted && !old.isHighlighted) {
      _glowCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.song.progressPercent > 0 ? 120 : 80,
      child: Stack(
        children: [
          // 底層左滑按鈕區
          if (widget.onArchive != null || widget.onDelete != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: widget.onArchive,
                      child: Container(
                        width: 72,
                        color: Colors.blueGrey[400],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.archive_outlined, size: 20, color: Colors.white),
                            SizedBox(height: 3),
                            Text('Archive', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        width: 72,
                        decoration: const BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.horizontal(right: Radius.circular(16))),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.delete_outline, size: 20, color: Colors.white),
                            SizedBox(height: 3),
                            Text('Delete', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 卡片本體
          AnimatedContainer(
            duration: _startX != null ? Duration.zero : const Duration(milliseconds: 200),
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: Listener(
              onPointerDown: (_) => _pointerMoved = false,
              onPointerMove: (e) { if (e.delta.dy.abs() > 2) _pointerMoved = true; },
              child: GestureDetector(
                onHorizontalDragStart: (d) => setState(() => _startX = d.globalPosition.dx),
                onHorizontalDragUpdate: (d) {
                  if (_startX == null) return;
                  final dx = d.globalPosition.dx - _startX!;
                  if (dx < 0) setState(() => _offset = dx.clamp(-144, 0));
                },
                onHorizontalDragEnd: (_) {
                  setState(() {
                    if (_offset < -60) { _offset = -144; _revealed = true; } 
                    else { _offset = 0; _revealed = false; }
                    _startX = null;
                  });
                },
                onTap: () {
                  if (_pointerMoved) return;
                  if (_revealed) { setState(() { _offset = 0; _revealed = false; }); } 
                  else { widget.onTap(); }
                },
                child: AnimatedBuilder(
                  animation: _glowAnim,
                  builder: (context, child) => Container(
                    decoration: BoxDecoration(
                      color: widget.t.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Color.lerp(widget.t.border, widget.t.accent, _glowAnim.value)!,
                        width: 1.0 + (_glowAnim.value * 1.5), // 亮起來時加粗邊框
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4),
                        if (_glowAnim.value > 0)
                          BoxShadow(
                            color: widget.t.accent.withValues(alpha: 0.5 * _glowAnim.value),
                            blurRadius: 15 * _glowAnim.value,
                            spreadRadius: 2 * _glowAnim.value,
                          ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.song.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: widget.t.text), overflow: TextOverflow.ellipsis),
                                  Text(widget.song.artist, style: TextStyle(fontSize: 12, color: widget.t.textSec)), // ❌ 刪除 duration 問號
                                ],
                              ),
                            ),
                            if (widget.song.isArchived && widget.onUnarchive != null)
                              GestureDetector(
                                onTap: widget.onUnarchive,
                                child: Container(
                                  decoration: BoxDecoration(border: Border.all(color: widget.t.border), borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  child: Text('Restore', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.t.textSec)),
                                ),
                              )
                            else if (widget.onFavToggle != null)
                              GestureDetector(
                                onTap: widget.onFavToggle,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(widget.song.isFavorite ? Icons.favorite : Icons.favorite_border, size: 18, color: widget.song.isFavorite ? AppColors.red : widget.t.textMuted),
                                ),
                              ),
                          ],
                        ),
                        if (widget.song.progressPercent > 0) ...[
                          const SizedBox(height: 12),
                          ProgressBar(progress: widget.song.progressPercent / 100, t: widget.t, height: 4),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(widget.song.progressPercent == 100 ? 'Completed' : 'In progress', style: TextStyle(fontSize: 11, color: widget.song.progressPercent == 100 ? AppColors.green : widget.t.textMuted)),
                              Text('${widget.song.progressPercent}%', style: TextStyle(fontSize: 11, color: widget.t.textMuted)),
                            ],
                          ),
                        ],
                      ],
                    ),
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

class _ModalField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final AppTheme t;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;

  const _ModalField({required this.label, required this.hint, required this.controller, required this.t, this.onSubmit, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.textMuted, letterSpacing: 0.07 * 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: 15, color: t.text),
          onSubmitted: (_) => onSubmit?.call(),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textMuted),
            filled: true, fillColor: t.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.accent)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}