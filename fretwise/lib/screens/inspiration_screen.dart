import 'package:flutter/material.dart';
import 'package:fretwise/models/song.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../theme.dart';
import '../models/app_state.dart';

class InspirationScreen extends StatefulWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;

  const InspirationScreen({super.key, required this.t, required this.navigate});

  @override
  State<InspirationScreen> createState() => _InspirationScreenState();
}

class _InspirationScreenState extends State<InspirationScreen> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // 💡 改用 StreamBuilder 監聽 Firebase 裡面的真實資料
    return StreamBuilder<List<FeedItem>>(
      stream: appState.feedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: widget.t.accent),
          );
        }

        final feedItems = snapshot.data ?? [];

        // 1. 如果資料庫是空的，顯示「生成推薦」按鈕
        if (feedItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.video_library_outlined,
                  size: 64,
                  color: widget.t.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'No inspiration feed yet.',
                  style: TextStyle(color: widget.t.textSec, fontSize: 16),
                ),
                const SizedBox(height: 24),
                if (_isGenerating)
                  Column(
                    children: [
                      CircularProgressIndicator(color: widget.t.accent),
                      const SizedBox(height: 16),
                      Text(
                        'AI is picking songs and fetching videos...',
                        style: TextStyle(color: widget.t.accent),
                      ),
                    ],
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.t.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () async {
                      setState(() => _isGenerating = true);
                      await appState.updateFeed(); // 呼叫 Gemini AI
                      setState(() => _isGenerating = false);
                    },
                    child: const Text(
                      'Ask AI to Generate Feed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        // 找到這個 PageView.builder
        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: feedItems.length,
          // 💡 新增這段：當滑到最後一部影片時，叫 AI 繼續生新的！
          onPageChanged: (index) {
            if (index == feedItems.length - 1) {
              appState.updateFeed(); // 背景默默生成，無限滑動
            }
          },
          itemBuilder: (context, index) {
            // ... (保持原樣)
            // ... (保持原樣)
            return _VideoFeedItem(
              item: feedItems[index],
              t: widget.t,
              navigate: widget.navigate,
              appState: appState,
            );
          },
        );
      },
    );
  }
}

class _VideoFeedItem extends StatefulWidget {
  final FeedItem item;
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final AppState appState;

  const _VideoFeedItem({
    required this.item,
    required this.t,
    required this.navigate,
    required this.appState,
  });

  @override
  State<_VideoFeedItem> createState() => _VideoFeedItemState();
}

class _VideoFeedItemState extends State<_VideoFeedItem> {
  YoutubePlayerController? _ytController;

  @override
  void initState() {
    super.initState();

    final videoId = YoutubePlayerController.convertUrlToId(
      widget.item.videoUrl,
    );

    if (videoId != null) {
      _ytController = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          mute: true,
          showControls: true,
          loop: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ytController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景與影片播放器
        Container(color: Colors.black),
        if (_ytController != null)
          Center(child: YoutubePlayer(controller: _ytController!))
        else
          const Center(
            child: Text(
              'Invalid Video URL',
              style: TextStyle(color: Colors.white),
            ),
          ),

        // 底部漸層遮罩 (為了讓文字清楚)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
        ),

        // 歌曲資訊與推薦理由 (左下角)
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.item.artist} · ${widget.item.genre}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.item.description,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.t.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    final existingId = await widget.appState.findExistingSongId(
                      widget.item.title,
                      widget.item.artist,
                    );
                    if (existingId != null) {
                      // 1. 如果已存在，設定高亮 ID
                      widget.appState.setHighlightedSong(existingId);
                      // 2. 直接跳轉到 Library
                      widget.navigate('library');
                      print('🔍 發現重複，跳轉至 Library 並發光');
                    } else {
                      final newSong = await widget.appState.searchSongToLibrary(
                        widget.item.title,
                        widget.item.artist,
                      );
                      if (!context.mounted) return;
                      if (newSong != null) {
                        widget.navigate(
                          'practicing',
                          props: {
                            'title': newSong.title,
                            'artist': newSong.artist,
                            'bpm': newSong.bpm,
                            'songId': newSong.id,
                          },
                        );
                      } else {
                        widget.navigate('library');
                      }
                    }
                  },
                  child: const Text(
                    "Let's practice",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: () => widget.navigate('library'),
                  child: const Text(
                    'Go to my library',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white38,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 互動按鈕 (右下角)
        Positioned(
          right: 16,
          bottom: 160,
          child: Column(
            children: [
              // Like
              GestureDetector(
                onTap: () => widget.appState.setFeedItemAction(
                  widget.item.id,
                  widget.item.actionState,
                  'liked',
                ),
                child: Column(
                  children: [
                    Icon(
                      widget.item.actionState == 'liked'
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 36,
                      color: widget.item.actionState == 'liked'
                          ? widget.t.accent
                          : Colors.white,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'More',
                      style: TextStyle(
                        color: widget.item.actionState == 'liked'
                            ? widget.t.accent
                            : Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Dislike
              GestureDetector(
                onTap: () => widget.appState.setFeedItemAction(
                  widget.item.id,
                  widget.item.actionState,
                  'disliked',
                ),
                child: Column(
                  children: [
                    Icon(
                      widget.item.actionState == 'disliked'
                          ? Icons.remove_circle
                          : Icons.remove_circle_outline,
                      size: 36,
                      color: widget.item.actionState == 'disliked'
                          ? Colors.red
                          : Colors.white,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Less',
                      style: TextStyle(
                        color: widget.item.actionState == 'disliked'
                            ? Colors.red
                            : Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
