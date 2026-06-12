import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../theme.dart';

typedef ChatMessage = ({String role, String text});

class ChatSession {
  final String title;
  final List<ChatMessage> messages;
  final DateTime updatedAt;
  final String? practicingChatKey;

  const ChatSession({
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.practicingChatKey,
  });
}

class AIChatScreen extends StatefulWidget {
  final AppTheme t;
  final String fromScreen;
  final VoidCallback onClose;
  final List<ChatMessage> messages;
  final List<ChatSession> history;
  final VoidCallback onNewChat;
  final ValueChanged<ChatSession> onOpenHistory;
  final String? activeSongTitle;
  final String? activeSongArtist;

  const AIChatScreen({
    super.key,
    required this.t,
    required this.fromScreen,
    required this.onClose,
    required this.messages,
    required this.history,
    required this.onNewChat,
    required this.onOpenHistory,
    this.activeSongTitle,
    this.activeSongArtist,
  });

  static const initialMessages = <ChatMessage>[
    (
      role: 'assistant',
      text:
          'Hey! I\'m your AI guitar coach 🎸 Ask me anything about chords, technique, songs, or practice tips.',
    ),
  ];

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final FocusNode _inputFocus;
  bool _loading = false;

  AppTheme get t => widget.t;

  String get _backLabel {
    switch (widget.fromScreen) {
      case 'practicing':
        return 'Back to practice';
      case 'sessionComplete':
        return 'Back to session';
      default:
        return 'Back';
    }
  }

  List<ChatMessage> get _messages => widget.messages;

  static const _suggestions = [
    'How do I play F chord?',
    '30-min practice plan',
    'Fix barre chords',
    'Song for beginners',
  ];

  Future<void> _send([String? text]) async {
    final msg = text ?? _inputCtrl.text.trim();
    if (msg.isEmpty || _loading) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add((role: 'user', text: msg));
      _loading = true;
    });
    _scrollToBottom();

    try {
      // Everything in _messages except the user turn we just appended
      final history = _messages
          .take(_messages.length - 1)
          .map((m) => {'role': m.role, 'text': m.text})
          .toList();

      final result = await FirebaseFunctions.instance
          .httpsCallable('chatWithCoach')
          .call({
            'message': msg,
            'history': history,
            'fromScreen': widget.fromScreen,
            if (widget.activeSongTitle != null)
              'activeSongTitle': widget.activeSongTitle,
            if (widget.activeSongArtist != null)
              'activeSongArtist': widget.activeSongArtist,
          });

      if (!mounted) return;
      setState(() {
        _messages.add((
          role: 'assistant',
          text: result.data['reply'] as String,
        ));
        _loading = false;
      });
    } catch (e) {
      debugPrint('[chatWithCoach] $e');
      if (!mounted) return;
      setState(() {
        _messages.add((
          role: 'assistant',
          text:
              "Sorry, I couldn't connect right now. Check your internet and try again!",
        ));
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Chat history',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No previous chats yet.',
                      style: TextStyle(fontSize: 14, color: t.textMuted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.history.length,
                      separatorBuilder: (ctx, index) =>
                          Divider(color: t.border),
                      itemBuilder: (ctx, i) {
                        final session = widget.history[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: t.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: t.border),
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              size: 17,
                              color: t.accent,
                            ),
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          subtitle: Text(
                            _formatHistoryTime(session.updatedAt),
                            style: TextStyle(fontSize: 12, color: t.textMuted),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onOpenHistory(session);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatHistoryTime(DateTime value) {
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return 'Today ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.month}/${value.day}/${value.year}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          _send();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          color: t.surface,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              GestureDetector(
                onTap: widget.onClose,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 18, color: t.accent),
                    const SizedBox(width: 6),
                    Text(
                      _backLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'New chat',
                onPressed: widget.onNewChat,
                icon: Icon(
                  Icons.add_comment_outlined,
                  size: 20,
                  color: t.accent,
                ),
              ),
              IconButton(
                tooltip: 'Chat history',
                onPressed: _showHistory,
                icon: Icon(Icons.history, size: 21, color: t.accent),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF5E8275),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Coach',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const Text(
                    '● Online',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(color: t.border, height: 1),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount:
                _messages.length +
                (_loading ? 1 : 0) +
                (_messages.length == 1 ? 1 : 0),
            itemBuilder: (ctx, i) {
              // Suggestion chips after first message
              if (_messages.length == 1 && i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _suggestions
                        .map(
                          (s) => GestureDetector(
                            onTap: () => _send(s),
                            child: Container(
                              decoration: BoxDecoration(
                                color: t.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: t.border),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: t.text,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              }

              final msgIdx = _messages.length == 1 ? i - 1 : i;

              // Loading bubble
              if (msgIdx >= _messages.length) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AIAvatar(),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          border: Border.all(color: t.border),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            3,
                            (j) => _DotLoader(delay: j * 200),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final m = _messages[msgIdx];
              final isUser = m.role == 'user';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser) ...[_AIAvatar(), const SizedBox(width: 8)],
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(ctx).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: isUser ? const Color(0xFF5E8275) : t.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isUser ? 18 : 4),
                            topRight: Radius.circular(isUser ? 4 : 18),
                            bottomLeft: const Radius.circular(18),
                            bottomRight: const Radius.circular(18),
                          ),
                          border: isUser ? null : Border.all(color: t.border),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Text(
                          m.text,
                          style: TextStyle(
                            fontSize: 14,
                            color: isUser ? Colors.white : t.text,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Input
        Container(
          color: t.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(color: t.border, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surfaceAlt,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: t.border),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        child: TextField(
                          controller: _inputCtrl,
                          focusNode: _inputFocus,
                          style: TextStyle(fontSize: 14, color: t.text),
                          onSubmitted: (_) => _send(),
                          textInputAction: TextInputAction.send,
                          maxLines: null,
                          decoration: InputDecoration(
                            hintText: 'Ask your guitar coach…',
                            hintStyle: TextStyle(color: t.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF5E8275),
                        ),
                        child: const Icon(
                          Icons.send,
                          size: 17,
                          color: Colors.white,
                        ),
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

class _AIAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: const Color(0xFF5E8275),
      ),
      child: const Icon(
        Icons.chat_bubble_outline,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

class _DotLoader extends StatefulWidget {
  final int delay;
  const _DotLoader({required this.delay});

  @override
  State<_DotLoader> createState() => _DotLoaderState();
}

class _DotLoaderState extends State<_DotLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween<double>(begin: 0, end: 4).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Interval(
          widget.delay / 1200,
          (widget.delay + 400) / 1200,
          curve: Curves.easeInOut,
        ),
      ),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (ctx, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Transform.translate(
          offset: Offset(0, -_anim.value),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade400,
            ),
          ),
        ),
      ),
    );
  }
}
