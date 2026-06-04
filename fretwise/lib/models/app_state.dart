import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/song.dart';

class DiaryEntry {
  final DateTime date;
  final String title;
  final String artist;
  final int duration; // seconds
  final String userNote;

  DiaryEntry({required this.date, required this.title, required this.artist, required this.duration, this.userNote = ''});
}

class AppState extends ChangeNotifier {
  bool _darkMode = false;
  int _coins = 340;
  Set<String> _ownedItems = {'streak_shield_1'};
  final List<Song> _extraSongs = [];
  final Set<String> _removedLibrarySongs = {};
  final List<DiaryEntry> _diaryEntries = [];

  bool get darkMode => _darkMode;
  Color get accent => AppColors.accent;
  int get coins => _coins;
  Set<String> get ownedItems => Set.unmodifiable(_ownedItems);
  List<Song> get extraSongs => List.unmodifiable(_extraSongs);
  Set<String> get removedLibrarySongs => Set.unmodifiable(_removedLibrarySongs);
  List<DiaryEntry> get diaryEntries => List.unmodifiable(_diaryEntries);

  void addDiaryEntry(DiaryEntry entry) {
    _diaryEntries.insert(0, entry);
    notifyListeners();
  }

  void updateLatestDiaryNote(String note) {
    if (_diaryEntries.isNotEmpty) {
      final e = _diaryEntries[0];
      _diaryEntries[0] = DiaryEntry(date: e.date, title: e.title, artist: e.artist, duration: e.duration, userNote: note);
      notifyListeners();
    }
  }

  void addSong(Song song) {
    final isBase = Song.library.any((s) => s.title.toLowerCase() == song.title.toLowerCase());
    if (isBase) {
      _removedLibrarySongs.remove(song.title);
    } else {
      _extraSongs.add(song);
    }
    notifyListeners();
  }

  void removeSongByTitle(String title) {
    final extraIdx = _extraSongs.indexWhere((s) => s.title.toLowerCase() == title.toLowerCase());
    if (extraIdx >= 0) {
      _extraSongs.removeAt(extraIdx);
    } else {
      _removedLibrarySongs.add(title);
    }
    notifyListeners();
  }

  AppTheme get theme => AppTheme(isDark: _darkMode);

  void toggleDarkMode() {
    _darkMode = !_darkMode;
    notifyListeners();
  }

  void setCoins(int value) {
    _coins = value;
    notifyListeners();
  }

  void spendCoins(int amount) {
    _coins -= amount;
    notifyListeners();
  }

  void addOwnedItem(String id) {
    _ownedItems = {..._ownedItems, id};
    notifyListeners();
  }

  bool ownsItem(String id) => _ownedItems.contains(id);
}

class AiMaterialService extends ChangeNotifier {
  Map<String, dynamic>? _currentMaterial;
  bool _isGenerating = false;

  // 供 UI 讀取目前的教材與生成狀態
  Map<String, dynamic>? get currentMaterial => _currentMaterial;
  bool get isGenerating => _isGenerating;

  /// 呼叫 AI API 生成教材（支援在背景執行）
  Future<void> generateMaterial({
    required String song,
    required String artist,
    String? preference,
  }) async {
    // 如果正在生成中，就不要重複觸發
    if (_isGenerating) return;

    _isGenerating = true;
    notifyListeners(); // 通知 UI 顯示「AI 正在尋找資源...」之類的載入狀態

    debugPrint('➔ [AI Service] 開始背景工作，搜尋 $song ($artist) 的資源...');

    try {
      // 模擬呼叫 API，利用 Google Search & YouTube 找資源（延遲 4 秒）
      await Future.delayed(const Duration(seconds: 4));

      // 模擬 API 回傳的資料結構（隨機模擬影片或圖片）
      final isVideo = DateTime.now().second % 2 == 0;

      if (isVideo) {
        _currentMaterial = {
          'type': 'video',
          'title': '$song — Advanced Tutorial',
          'url': 'https://www.youtube.com/watch?v=mock_video_id',
        };
      } else {
        _currentMaterial = {
          'type': 'image',
          'title': '$song — Guitar Tabs',
          'url': 'https://example.com/mock_tabs.png',
        };
      }
      
      debugPrint('➔ [AI Service] 背景生成成功！新型態為: ${_currentMaterial?['type']}');
    } catch (e) {
      debugPrint('➔ [AI Service] 生成出錯: $e');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// 重置教材（例如換別首歌時）
  void reset() {
    _currentMaterial = null;
    _isGenerating = false;
    notifyListeners();
  }
}