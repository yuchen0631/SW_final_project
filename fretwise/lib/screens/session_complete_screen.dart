import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/song_id.dart';

class SessionCompleteScreen extends StatefulWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final String title;
  final String artist;
  final int duration;
  final List<String> recordingUrls;
  final String? songId;
  final String? taskId;
  final String? dayId;
  final VoidCallback onOpenAI;
  final void Function(String note)? onSaveNote;
  final List<Map<String, String>> chatHistory;

  const SessionCompleteScreen({
    super.key,
    required this.t,
    required this.navigate,
    required this.title,
    required this.artist,
    required this.duration,
    required this.recordingUrls,
    this.songId,
    this.taskId,
    this.dayId,
    required this.onOpenAI,
    this.onSaveNote,
    required this.chatHistory,
  });

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  bool _recording = false;
  final _feedbackCtrl = TextEditingController();
  bool _showDeadlineModal = false;
  String _deadlineDate = '';
  bool _deadlineSaved = false;
  bool _isSaving = false;
  String _targetDestination = 'home';

  Map<String, dynamic>? _nextTask;

  AppTheme get t => widget.t;

  @override
  void initState() {
    super.initState();
    if (widget.dayId != null) {
      _fetchNextTask();
    }
  }

  Future<void> _fetchNextTask() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('practiceTasks')
        .where('dayId', isEqualTo: widget.dayId)
        .where('status', isEqualTo: 'planned')
        .orderBy('orderIndex')
        .get();

    for (var doc in snap.docs) {
      if (doc.id != widget.taskId) {
        setState(() {
          _nextTask = doc.data();
          _nextTask!['id'] = doc.id;
        });
        break;
      }
    }
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  int get _starsEarned => (widget.duration / 10 + 3).clamp(3, 15).floor();

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  // song id helper moved to lib/utils/song_id.dart

  Future<void> _handleSaveAndNavigate(String destination) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _targetDestination = destination;
    });

    widget.onSaveNote?.call(_feedbackCtrl.text.trim());
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && widget.taskId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('practiceTasks')
            .doc(widget.taskId)
            .update({'status': 'completed'});
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'recordSession',
      );

      // 整合練習中的 AI 對話歷史
      final allChatHistory = [...widget.chatHistory];
      if (_feedbackCtrl.text.trim().isNotEmpty) {
        allChatHistory.add({
          'role': 'user',
          'text': 'Session feedback: ${_feedbackCtrl.text.trim()}',
        });
      }

      final payload = {
        'song': {
          'title': widget.title,
          'artist': widget.artist,
          'progressPercent': 0,
          'defaultSectionLabel': null,
          'deadlineDate': _deadlineDate.isEmpty ? null : _deadlineDate,
        },
        'songProfile': null,
        'profile': null,
        'userThoughts': {
          'practiceDate': DateTime.now().toIso8601String().split('T')[0],
          'durationSec': widget.duration,
          'userNote': _feedbackCtrl.text.trim().isEmpty
              ? null
              : _feedbackCtrl.text.trim(),
          'deadlineDate': _deadlineDate.isEmpty ? null : _deadlineDate,
          'recordingUrls': widget.recordingUrls,
          'chatHistory': allChatHistory,
          'startedAt': null,
          'endedAt': DateTime.now().toIso8601String(),
        },
      };

      final result = await callable.call(payload);
      print('recordSession result: ${result.data}');
      
      final data = result.data as Map<String, dynamic>?;
      if (data != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';
        FirebaseFunctions.instance.httpsCallable('applyPatch').call({
          'uid': uid,
          'userProfilePatch': data['userProfilePatch'],
          'songProfilePatch': data['songProfilePatch'],
          'song': data['song'] ?? {
            'title': widget.title,
            'artist': widget.artist,
          },
        }).catchError((e) => print('Background applyPatch error: $e'));
      }

      // Best-effort: set firstCompleteDate on user's songProfiles doc if missing
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';
      final songId = makeSongId(widget.title, widget.artist);
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('songProfiles')
          .doc(songId);
      final doc = await docRef.get();
      final nowDate = DateTime.now().toIso8601String().split('T')[0];
      if (!doc.exists) {
        await docRef.set({
          'firstCompleteDate': nowDate,
          'title': widget.title,
          'artist': widget.artist,
        });
      } else {
        final data = doc.data();
        if (data != null &&
            (data['firstCompleteDate'] == null ||
                data['firstCompleteDate'] == '')) {
          await docRef.update({'firstCompleteDate': nowDate});
        }
      }
    } catch (e) {
      print('recordSession error: $e');
      // FALLBACK: If Cloud Function fails (e.g. offline, not deployed), save directly to Firestore!
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';
      try {
        final dummyAiResponse = {
          'sessionInfo': {
            'aiComment':
                'Great effort today! (Note: the AI backend is currently unreachable, but your practice was safely saved.)',
            'nextFocus': [
              'Keep practicing consistently.',
              'Focus on your problem areas.',
            ],
          },
          'userProfilePatch': {},
          'songProfilePatch': {},
        };

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .add({
              'title': widget.title,
              'artist': widget.artist,
              'practiceDate': DateTime.now().toIso8601String().split('T')[0],
              'durationSec': widget.duration,
              'userNote': _feedbackCtrl.text.trim(),
              'recordingUrls': widget.recordingUrls,
              'createdAt': FieldValue.serverTimestamp(),
              'sessionInfo': dummyAiResponse['sessionInfo'],
            });
        print('recordSession fallback success');
      } catch (fallbackErr) {
        print('recordSession fallback error: $fallbackErr');
      }
    }

    setState(() => _isSaving = false);
    widget.navigate(_targetDestination);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: Column(
                  children: [
                    Text(
                      'Session Complete',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: t.text,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.artist,
                      style: TextStyle(fontSize: 13, color: t.textSec),
                    ),
                  ],
                ),
              ),

              // Stats row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: t.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                Text(
                                  'THIS SESSION',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: t.textMuted,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _fmt(widget.duration),
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: t.text,
                                    letterSpacing: -1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(
                          color: t.border,
                          width: 1,
                          indent: 14,
                          endIndent: 14,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                Text(
                                  'TOTAL ON SONG',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: t.textMuted,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '4h 25m',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: t.text,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Stars earned
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: t.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 20,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('⭐', style: TextStyle(fontSize: 40)),
                      const SizedBox(width: 12),
                      Text(
                        '+$_starsEarned',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: AppColors.gold,
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'stars earned',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: t.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Feedback
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How was the practice?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _feedbackCtrl,
                            maxLines: 4,
                            style: TextStyle(
                              fontSize: 14,
                              color: t.text,
                              height: 1.6,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type or tap the mic to speak…',
                              hintStyle: TextStyle(color: t.textMuted),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _recording = !_recording),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _recording
                                        ? AppColors.red
                                        : t.surfaceAlt,
                                  ),
                                  child: Icon(
                                    Icons.mic,
                                    size: 16,
                                    color: _recording
                                        ? Colors.white
                                        : t.textSec,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_recording) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Listening…',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF5E8275),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: widget.onOpenAI,
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Ask AI Coach about this session',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size(double.infinity, 46),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Nav buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () => _handleSaveAndNavigate('home'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accent,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving && _targetDestination == 'home'
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Back to Home',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => _handleSaveAndNavigate('library'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: t.border, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSaving && _targetDestination == 'library'
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: t.accent,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Go to my Library',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: t.text,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Performance deadline modal
        if (_showDeadlineModal)
          GestureDetector(
            onTap: () => setState(() => _showDeadlineModal = false),
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: t.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          gradient: LinearGradient(
                            colors: [
                              t.accent.withValues(alpha: 0.13),
                              t.accent.withValues(alpha: 0.27),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          size: 26,
                          color: t.accent,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Do you have a performance coming up?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: t.text,
                          fontFamily: 'Georgia',
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is your first time practicing ${widget.title}. Set a deadline and we\'ll build a practice schedule to get you ready.',
                        style: TextStyle(
                          fontSize: 14,
                          color: t.textSec,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_deadlineSaved) ...[
                        Text(
                          'PERFORMANCE DATE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(
                                const Duration(days: 30),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(
                                () => _deadlineDate = picked
                                    .toIso8601String()
                                    .split('T')[0],
                              );
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: t.surfaceAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _deadlineDate.isNotEmpty
                                    ? t.accent
                                    : t.border,
                                width: 1.5,
                              ),
                            ),
                            padding: const EdgeInsets.all(13),
                            child: Text(
                              _deadlineDate.isEmpty
                                  ? 'Select a date'
                                  : _deadlineDate,
                              style: TextStyle(
                                fontSize: 15,
                                color: _deadlineDate.isEmpty
                                    ? t.textMuted
                                    : t.text,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _deadlineDate.isEmpty
                                ? null
                                : () => setState(() => _deadlineSaved = true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _deadlineDate.isNotEmpty
                                  ? t.accent
                                  : t.surfaceAlt,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Set my deadline',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _deadlineDate.isNotEmpty
                                    ? Colors.white
                                    : t.textMuted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _showDeadlineModal = false),
                            child: Text(
                              "No deadline, I'm just exploring",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: t.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              const Text('🎯', style: TextStyle(fontSize: 36)),
                              const SizedBox(height: 10),
                              Text(
                                'Goal set for $_deadlineDate',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "We'll tailor your practice schedule to have you performance-ready in time.",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: t.textSec,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
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
