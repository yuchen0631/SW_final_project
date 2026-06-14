import 'package:cloud_firestore/cloud_firestore.dart';

// 對應 shared_models.md 中的 SongEntry
class SongEntry {
  final String id;
  final String title;
  final String artist;
  final String duration;
  final int progressPercent;
  final Timestamp? lastPracticedAt;
  final int seed;
  final int bpm;
  final bool isArchived;
  final bool isFavorite;
  final String? videoUrl;

  SongEntry({
    required this.id,
    required this.title,
    required this.artist,
    this.duration = '?:??',
    this.progressPercent = 0,
    this.lastPracticedAt,
    this.seed = 0,
    this.bpm = 80,
    this.isArchived = false,
    this.isFavorite = false,
    this.videoUrl,
  });

  factory SongEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SongEntry(
      id: doc.id,
      title: data['title'] ?? 'Unknown',
      artist: data['artist'] ?? 'Unknown',
      duration: data['durationSec'] != null ? '${data['durationSec'] ~/ 60}:${(data['durationSec'] % 60).toString().padLeft(2, '0')}' : '?:??',
      progressPercent: data['progressPercent'] ?? 0,
      lastPracticedAt: data['lastPracticedAt'] as Timestamp?,
      seed: data['seed'] ?? 0,
      bpm: data['bpm'] ?? 80,
      isArchived: data['isArchived'] ?? false,
      isFavorite: data['isFavorite'] ?? false,
      videoUrl: data['videoUrl'] as String?,
    );
  }
}

// 對應 shared_models.md 中的 FeedItem
class FeedItem {
  final String id;
  final String songId;
  final String title;
  final String artist;
  final String genre;
  final String description;
  final String videoUrl; // 這裡將會是 AI 找來的 YouTube 教學影片網址
  final String actionState; // 'liked', 'disliked', 'ignored'

  FeedItem({
    required this.id,
    required this.songId,
    required this.title,
    required this.artist,
    required this.genre,
    required this.description,
    required this.videoUrl,
    this.actionState = 'ignored',
  });

  factory FeedItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FeedItem(
      id: doc.id,
      songId: data['songId'] ?? '',
      title: data['title'] ?? 'Unknown',
      artist: data['artist'] ?? 'Unknown',
      genre: data['genre'] ?? '',
      description: data['description'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      actionState: data['actionState'] ?? 'ignored',
    );
  }
}