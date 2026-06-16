import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/notification_manager.dart';
import '../widgets/album_art.dart';
import '../widgets/section_header.dart';
import '../widgets/progress_bar.dart';

class HomeScreen extends StatelessWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final int coins;

  const HomeScreen({
    super.key,
    required this.t,
    required this.navigate,
    required this.coins,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.only(
            bottom: 80,
          ), // Increased bottom padding for FAB
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Alex 🎸',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 5),
                        Text(
                          '$coins',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Streak card
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Column(
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 56)),
                          const SizedBox(height: 2),
                          Text(
                            '12',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: t.text,
                              letterSpacing: -3,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'day streak',
                            style: TextStyle(
                              fontSize: 16,
                              color: t.textSec,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Resume section
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(label: 'Resume', t: t),
                    GestureDetector(
                      onTap: () => navigate(
                        'practicing',
                        props: {
                          'title': 'Wonderwall',
                          'artist': 'Oasis',
                          'bpm': 87,
                        },
                      ),
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
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const AlbumArt(seed: 0, size: 48, radius: 14),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Last practiced',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: t.textMuted,
                                          letterSpacing: 0.07 * 11,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Wonderwall',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: t.text,
                                        ),
                                      ),
                                      Text(
                                        'Oasis · 80% complete',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: t.textSec,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ProgressBar(progress: 0.8, t: t),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Continued yesterday · 18 min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.textSec,
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: t.accent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.play_arrow,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Continue',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Get inspired button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: GestureDetector(
                  onTap: () => navigate('inspiration'),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: t.accent.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.35),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt, size: 20, color: t.accent),
                        const SizedBox(width: 10),
                        Text(
                          'Get inspired',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: t.border, height: 1),
              ),

              // Next Up
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      label: 'Next Up',
                      action: 'See calendar',
                      onAction: () => navigate('calendar'),
                      t: t,
                    ),
                    GestureDetector(
                      onTap: () => navigate('calendar'),
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const AlbumArt(seed: 1, size: 40, radius: 12),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Blackbird',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: t.text,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'The Beatles',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: t.textSec,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Bars 1–8 fingerpicking',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: t.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'In 3 days',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: t.accent,
                                  ),
                                ),
                                Text(
                                  '2:18',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 90,
          left: 20,
          child: FloatingActionButton(
            backgroundColor: t.accent,
            onPressed: () {
              NotificationManager().scheduleTestNotification();
            },
            child: const Icon(Icons.notifications_active, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
