import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// 👇 新增這兩行 Firebase 必備的 import
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 

import 'theme.dart';
import 'models/app_state.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/practicing_screen.dart';
import 'screens/session_complete_screen.dart';
import 'screens/inspiration_screen.dart';
import 'screens/ai_chat_screen.dart';

// 👇 將原本的 main() 替換成這個非同步版本
void main() async {
  // 1. 確保 Flutter 引擎已經啟動
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. 初始化 Firebase (連接到同學建好的專案)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. 執行 App
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => AiMaterialService()),
      ],
      child: const FretwiseApp(),
    ),
  );
}

class FretwiseApp extends StatelessWidget {
  const FretwiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (ctx, state, _) {
        final t = state.theme;
        return MaterialApp(
          title: 'Fretwise',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme(
              brightness: state.darkMode ? Brightness.dark : Brightness.light,
              primary: AppColors.accent,
              onPrimary: Colors.white,
              secondary: AppColors.accentMid,
              onSecondary: Colors.white,
              error: AppColors.red,
              onError: Colors.white,
              surface: t.surface,
              onSurface: t.text,
            ),
            scaffoldBackgroundColor: t.bg,
          ),
          home: const FretwiseShell(),
        );
      },
    );
  }
}

const _overlayScreens = {'practicing', 'sessionComplete', 'inspiration'};

class FretwiseShell extends StatefulWidget {
  const FretwiseShell({super.key});

  @override
  State<FretwiseShell> createState() => _FretwiseShellState();
}

class _FretwiseShellState extends State<FretwiseShell> {
  String _screen = 'home';
  Map<String, dynamic>? _screenProps;
  bool _showAI = false;
  String _prevScreen = 'home';
  Offset _fabPos = const Offset(20, 84);

  void _navigate(String dest, {Map<String, dynamic>? props}) {
    if (dest == 'sessionComplete' && props != null) {
      context.read<AppState>().addDiaryEntry(
        DiaryEntry(
          date: DateTime.now(),
          title: props['title'] as String? ?? '',
          artist: props['artist'] as String? ?? '',
          duration: props['duration'] as int? ?? 0,
        ),
      );
    }
    setState(() {
      _screenProps = props;
      _screen = dest;
      _showAI = false;
    });
  }

  void _openAI() => setState(() {
    _prevScreen = _screen;
    _showAI = true;
  });
  void _closeAI() => setState(() => _showAI = false);

  bool get _isOverlay => _overlayScreens.contains(_screen);
  bool get _showNav => !_showAI && !_isOverlay;
  bool get _showFloatingAI => !_showAI && !_isOverlay;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.theme;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: state.darkMode
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _showAI
                      ? AIChatScreen(
                          t: t,
                          fromScreen: _prevScreen,
                          onClose: _closeAI,
                        )
                      : _buildScreen(t, state),
                ),
                if (_showNav)
                  _BottomNavBar(active: _screen, navigate: _navigate, t: t),
              ],
            ),

            if (_showFloatingAI)
              Positioned(
                bottom: _fabPos.dy,
                right: _fabPos.dx,
                child: GestureDetector(
                  onTap: _openAI,
                  onPanUpdate: (details) {
                    final size = MediaQuery.sizeOf(context);
                    const fab = 52.0;
                    setState(() {
                      _fabPos = Offset(
                        (_fabPos.dx - details.delta.dx).clamp(
                          0,
                          size.width - fab,
                        ),
                        (_fabPos.dy - details.delta.dy).clamp(
                          0,
                          size.height - fab,
                        ),
                      );
                    });
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF5E8275),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 16,
                          spreadRadius: 1,
                          offset: const Offset(0, 5),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreen(AppTheme t, AppState state) {
    final props = _screenProps ?? {};

    switch (_screen) {
      case 'home':
        return HomeScreen(t: t, navigate: _navigate, coins: state.coins);

      case 'library':
        // 💡 修正這裡：只傳入 t 和 navigate，不傳舊的假資料
        return LibraryScreen(t: t, navigate: _navigate);

      case 'calendar':
        return CalendarScreen(t: t, navigate: _navigate);

      case 'shop':
        return ShopScreen(
          t: t,
          navigate: _navigate,
          coins: state.coins,
          ownedItems: state.ownedItems,
          onBuy: (id) {
            // (商城功能不變)
          },
        );

      case 'profile':
        return ProfileScreen(
          t: t,
          navigate: _navigate,
          coins: state.coins,
          ownedItems: state.ownedItems,
          diaryEntries: state.diaryEntries,
        );

      case 'practicing':
        final aiService = context.watch<AiMaterialService>();

        return PracticingScreen(
          t: t,
          navigate: _navigate,
          title: props['title'] as String? ?? 'Wonderwall',
          artist: props['artist'] as String? ?? 'Oasis',
          bpm: props['bpm'] as int? ?? 87,
          videoUrl: props['videoUrl'] as String?,
          onOpenAI: _openAI,
          practiceMaterial: aiService.currentMaterial,
        );

      case 'sessionComplete':
        return SessionCompleteScreen(
          t: t,
          navigate: _navigate,
          title: props['title'] as String? ?? 'Wonderwall',
          artist: props['artist'] as String? ?? 'Oasis',
          duration: props['duration'] as int? ?? 0,
          recordingUrls: props['recordingUrls'] != null
              ? List<String>.from(props['recordingUrls'] as List)
              : [],
          chatHistory: props['chatHistory'] != null
              ? (props['chatHistory'] as List).map((m) => Map<String, String>.from(m as Map)).toList()
              : [],
          onOpenAI: _openAI,
          onSaveNote: (note) => context.read<AppState>().updateLatestDiaryNote(note),
        );

      case 'inspiration':
        // 💡 修正這裡：只傳入 t 和 navigate，不傳舊的假資料
        return InspirationScreen(t: t, navigate: _navigate);

      default:
        return HomeScreen(t: t, navigate: _navigate, coins: state.coins);
    }
  }
}

class _BottomNavBar extends StatelessWidget {
  final String active;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final AppTheme t;

  const _BottomNavBar({
    required this.active,
    required this.navigate,
    required this.t,
  });

  static const _tabs = [
    (id: 'shop', label: 'Shop', icon: Icons.storefront_outlined),
    (id: 'calendar', label: 'Calendar', icon: Icons.calendar_today_outlined),
    (id: 'home', label: 'Home', icon: Icons.home_outlined),
    (id: 'library', label: 'Library', icon: Icons.menu_book_outlined),
    (id: 'profile', label: 'Profile', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: t.border, height: 1),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: _tabs.map((tab) {
                  final isActive = active == tab.id;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => navigate(tab.id),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: isActive ? 24 : 0,
                            height: 2.5,
                            decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(
                            tab.icon,
                            size: 24,
                            color: isActive ? t.accent : t.textMuted,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isActive ? t.accent : t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}