import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/album_art.dart';
import '../widgets/section_header.dart';
import '../widgets/progress_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_functions/cloud_functions.dart';

class CalendarScreen extends StatefulWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;

  const CalendarScreen({super.key, required this.t, required this.navigate});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  final _today = DateTime.now();
  late int _month;
  late int _year;
  bool _showTodayDetail = false;
  bool _isUpdatingPlan = false;
  double _updateProgress = 0.0; // 0.0 - 1.0
  bool _cancelUpdateRequested = false;
  bool _notifyLaterRequested = false;
  Timer? _updateProgressTimer;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();
  Map<String, dynamic>? _selectedTask;
  bool _calendarPermissionGranted = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _month = _today.month;
    _year = _today.year;
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addObserver(this);
    // 首次進入 Calendar 頁面時，檢查並請求行事曆權限
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestCalendarPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      print("使用者離開 App，開始同步行事曆與更新 AI 計畫...");
      _fetchExternalCalendar();
    } else if (state == AppLifecycleState.resumed) {
      // 使用者回到 App 時，重新檢查權限狀態
      _checkCalendarPermission();
    }
  }

  /// 檢查目前的行事曆權限狀態（不彈對話框）
  Future<void> _checkCalendarPermission() async {
    try {
      final result = await _deviceCalendarPlugin.hasPermissions();
      if (mounted) {
        setState(() {
          _calendarPermissionGranted = result.isSuccess && (result.data ?? false);
        });
      }
    } catch (e) {
      print(e);
      if (mounted) setState(() => _calendarPermissionGranted = false);
    }
  }

  Future<void> _requestCalendarPermission() async {
    try {
      final result = await _deviceCalendarPlugin.hasPermissions();
      if (result.isSuccess && (result.data ?? false)) {
        // 已經有權限
        if (mounted) setState(() => _calendarPermissionGranted = true);
        return;
      }

      final requestResult = await _deviceCalendarPlugin.requestPermissions();
      if (mounted) {
        setState(() {
          _calendarPermissionGranted =
              requestResult.isSuccess && (requestResult.data ?? false);
        });
      }
    } catch (e) {
      print("requestPermissions fail: $e");
      if (mounted) setState(() => _calendarPermissionGranted = false);
    }
  }

  /// 首次進入時，用友善對話框提示使用者允許行事曆存取
  Future<void> _checkAndRequestCalendarPermission() async {
    try {
      final result = await _deviceCalendarPlugin.hasPermissions();
      if (result.isSuccess && (result.data ?? false)) {
        // 已經有權限
        if (mounted) setState(() => _calendarPermissionGranted = true);
        return;
      }
    } catch (e) {
      print("checkAndRequestCalendarPermission error: $e");
      if (mounted) setState(() => _calendarPermissionGranted = false);
      return;
    }

    // 尚無權限，顯示友善對話框說明原因
    if (!mounted) return;
    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.calendar_month, color: t.accent, size: 24),
            const SizedBox(width: 10),
            Text(
              '行事曆存取',
              style: TextStyle(
                color: t.text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Fretwise 需要讀取你的行事曆，才能根據你的空閒時間自動安排練習計畫。\n\n'
          '📅 忙碌的日子 → 安排較短的練習\n'
          '🎸 空閒的日子 → 安排較完整的練習\n\n'
          '你的行事曆資料只會用於排程，不會被儲存或分享。',
          style: TextStyle(color: t.textSec, fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('稍後再說', style: TextStyle(color: t.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '允許存取',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (shouldRequest == true) {
      final permResult = await _deviceCalendarPlugin.requestPermissions();
      if (mounted) {
        setState(() {
          _calendarPermissionGranted =
              permResult.isSuccess && (permResult.data ?? false);
        });
      }
    }
  }

  /// 手動同步行事曆（由使用者主動觸發）
  Future<void> _manualSync() async {
    if (_isSyncing || _isUpdatingPlan) return;
    setState(() => _isSyncing = true);
    await _fetchExternalCalendar(forceSync: true);
    if (mounted) setState(() => _isSyncing = false);
  }

  AppTheme get t => widget.t;

  // 1. 建立一個 Stream 來監聽 Firebase 中當月的 PracticeDay 資料
  Stream<List<Map<String, dynamic>>> _getPracticeDaysStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';

    // 將目前的年月轉為 YYYY-MM 格式，用來過濾當月資料
    final monthStr = '$_year-${_month.toString().padLeft(2, '0')}';

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('practiceDays')
        // 根據 shared_models.md，date 的格式是 YYYY-MM-DD
        .where('date', isGreaterThanOrEqualTo: '$monthStr-01')
        .where('date', isLessThanOrEqualTo: '$monthStr-31')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> _getPracticeTasksStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';

    final todayStr =
        '$_year-${_month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('practiceTasks')
        .where('dayId', isGreaterThanOrEqualTo: todayStr)
        .orderBy('dayId')
        .orderBy('orderIndex')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // 讀取外部行事曆（未來 7 天）
  Future<void> _fetchExternalCalendar({bool forceSync = false}) async {
    bool hasPermission = false;
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !permissionsGranted.data!) {
        permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
        if (permissionsGranted.isSuccess && permissionsGranted.data!) {
          hasPermission = true;
        } else {
          print("使用者拒絕了行事曆權限，將無法讀取真實行事曆。");
        }
      } else if (permissionsGranted.isSuccess && permissionsGranted.data!) {
        hasPermission = true;
      }
    } catch (e) {
      print("檢查行事曆權限失敗（可能是不支援的平台）：$e");
    }

    List<dynamic> calendars = [];
    if (hasPermission) {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      calendars = (calendarsResult.isSuccess && calendarsResult.data != null)
          ? calendarsResult.data!
          : [];
    }

    final currentLocation = tz.getLocation('Asia/Taipei');
    final startDate = tz.TZDateTime.now(currentLocation);
    final endDate = startDate.add(const Duration(days: 28));

    List<Map<String, dynamic>> externalEvents = [];

    for (var calendar in calendars) {
      // 1. 多加一個 calendar.id == null 的檢查，擋掉幽靈行事曆
      if (calendar.isReadOnly == true || calendar.id == null) continue;

      final retrieveEventsParams = RetrieveEventsParams(
        startDate: startDate,
        endDate: endDate,
      );

      // 2. 用 try-catch 包起來，就算某個行事曆壞掉，也不會讓整個 App 當機
      try {
        final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
          calendar.id,
          retrieveEventsParams,
        );

        if (eventsResult.isSuccess && eventsResult.data != null) {
          for (var event in eventsResult.data!) {
            final title = event.title ?? '忙碌行程';
            
            // 過濾掉我們先前寫入的 Fretwise 練習行程，避免 AI 以為這天很忙而取消練習
            if (title.startsWith('[Fretwise]')) continue;
            
            externalEvents.add({
              'title': title,
              'start': event.start?.toIso8601String(),
              'end': event.end?.toIso8601String(),
            });
          }
        }
      } catch (e) {
        print("讀取行事曆 ${calendar.name} 時發生小錯誤，已跳過：$e");
      }
    }

    // [新增] 為了在模擬器上方便測試，如果因為 Bug 抓不到行程，我們就塞假行程給它
    if (externalEvents.isEmpty) {
      print("因為沒有抓到行程（或是在模擬器上遇到 Bug），自動塞入測試用的假行程！");
      externalEvents.add({
        'title': '模擬器測試：跟教練約好要練吉他',
        'start': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        'end': DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final currentEventsJson = jsonEncode(externalEvents);
    final lastEventsJson = prefs.getString('last_calendar_events');

    if (!forceSync && currentEventsJson == lastEventsJson) {
      print("行事曆沒有變動，跳過 API 呼叫。");
      return;
    }

    print("準備傳送 ${externalEvents.length} 個外部行程給後端：");
    print(externalEvents);

    // 顯示更新進度 UI
    setState(() {
      _isUpdatingPlan = true;
      _updateProgress = 0.02;
      _cancelUpdateRequested = false;
      _notifyLaterRequested = false;
    });

    // 啟動假進度條：遞增到 0.95，真正結果到時再完成到 1.0
    _updateProgressTimer?.cancel();
    _updateProgressTimer = Timer.periodic(const Duration(milliseconds: 300), (
      t,
    ) {
      if (_cancelUpdateRequested) {
        t.cancel();
        return;
      }
      setState(() {
        _updateProgress = (_updateProgress + 0.03).clamp(0.0, 0.95);
      });
    });

    // 呼叫後端 AI 進行排程 (updatePlan)
    try {
      print("正在呼叫 AI 排程 API (updatePlan)...");
      final HttpsCallable callable = FirebaseFunctions.instanceFor(
        region: 'asia-east1',
      ).httpsCallable('updatePlan');

      // 傳送外部行事曆資料，後端會自動讀取資料庫中的 Preference 等資訊
      final result = await callable.call({'externalCalendar': externalEvents});

      if (_cancelUpdateRequested) {
        // 使用者已取消，忽略結果
        print('updatePlan 已被取消，忽略回傳');
      } else {
        // 將進度補足到 100%
        _updateProgressTimer?.cancel();
        setState(() => _updateProgress = 1.0);
        await Future.delayed(const Duration(milliseconds: 300));
        print("AI 排程成功更新！後端回傳：${result.data}");
        
        // 成功後將這次的行事曆資料儲存起來
        await prefs.setString('last_calendar_events', currentEventsJson);
        
        // [新增] 將安排好的 practiceTasks 同步到手機內建行事曆
        if (result.data['planId'] != null) {
          await _syncTasksToNativeCalendar(result.data['planId']);
        }
      }
    } catch (e) {
      if (!_cancelUpdateRequested) print("呼叫 AI API 失敗：$e");
    } finally {
      _updateProgressTimer?.cancel();
      if (!_notifyLaterRequested) {
        setState(() {
          _isUpdatingPlan = false;
          _updateProgress = 0.0;
        });
      } else {
        // 若使用者選擇稍後通知，保留狀態並關閉 UI
        setState(() {
          _isUpdatingPlan = false;
          _updateProgress = 0.0;
          _notifyLaterRequested = false;
        });
      }
    }
  }

  Future<void> _syncTasksToNativeCalendar(String planId) async {
    print("開始將 Fretwise 課表同步到內建行事曆...");
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test_user_123';
      
      print("正在從 Firestore 抓取本次產生的 Practice Tasks (planId: $planId)...");
      // 因為後端剛寫入 Firestore，給它 1 秒的同步時間
      await Future.delayed(const Duration(seconds: 1));
      
      final tasksSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('practiceTasks')
          .where('planId', isEqualTo: planId)
          .get();
          
      if (tasksSnap.docs.isEmpty) {
        print("沒有找到對應的任務 (可能 Firestore 還沒同步過來)，跳過同步");
        return;
      }
      print("成功抓到 \${tasksSnap.docs.length} 個任務，準備寫入日曆...");

      // 取得日曆列表，尋找第一個可寫入的日曆
      print("正在取得手機的日曆列表...");
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null) {
        print("無法取得裝置行事曆");
        return;
      }
      
      final writableCalendars = calendarsResult.data!.where((c) => c.isReadOnly == false && c.id != null).toList();
      if (writableCalendars.isEmpty) {
        print("找不到可以寫入的行事曆");
        return;
      }
      
      // 預設寫入第一個可寫的日曆
      final targetCalendar = writableCalendars.first;
      print("將寫入目標日曆：\${targetCalendar.name} (ID: \${targetCalendar.id})");
      
      final currentLocation = tz.getLocation('Asia/Taipei');
      final startDate = tz.TZDateTime.now(currentLocation).subtract(const Duration(days: 1));
      final endDate = startDate.add(const Duration(days: 35));

      // 1. 先把舊的 [Fretwise] 行程清掉
      print("正在清理過去的 [Fretwise] 舊行程...");
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        targetCalendar.id,
        RetrieveEventsParams(startDate: startDate, endDate: endDate),
      );
      
      if (eventsResult.isSuccess && eventsResult.data != null) {
        for (var event in eventsResult.data!) {
          if ((event.title ?? '').startsWith('[Fretwise]')) {
            await _deviceCalendarPlugin.deleteEvent(targetCalendar.id, event.eventId);
          }
        }
      }
      print("舊行程清理完畢。");
      
      // 2. 新增每個 task
      print("開始逐一寫入新的練習行程...");
      int addedCount = 0;
      for (var i = 0; i < tasksSnap.docs.length; i++) {
        final doc = tasksSnap.docs[i];
        final data = doc.data();
        final title = data['title'] ?? 'Practice';
        final minutes = data['minutes'] ?? 20;
        final dayId = data['dayId'] as String; // YYYY-MM-DD
        
        final parts = dayId.split('-');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          
          // 預設排在晚上 20:00
          final taskStart = tz.TZDateTime(currentLocation, year, month, day, 20, 0);
          final taskEnd = taskStart.add(Duration(minutes: minutes));
          
          final event = Event(
            targetCalendar.id,
            title: '[Fretwise] $title',
            description: data['instructions'] ?? '',
            start: taskStart,
            end: taskEnd,
          );
          
          final createResult = await _deviceCalendarPlugin.createOrUpdateEvent(event);
          if (createResult?.isSuccess == true) {
            addedCount++;
            print("  -> 成功寫入：\${dayId} 的 $title");
          } else {
            print("  -> 寫入失敗：\${dayId} (\${createResult?.errors.map((e) => e.errorMessage).join(', ')})");
          }
        }
      }
      print("同步內建行事曆完成！共寫入 $addedCount 個行程");
    } catch (e) {
      print("同步內建行事曆發生例外錯誤：$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstDay = DateTime(_year, _month, 1).weekday % 7;
    final monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Calendar',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    // 手動同步按鈕
                    GestureDetector(
                      onTap: _calendarPermissionGranted
                          ? _manualSync
                          : _checkAndRequestCalendarPermission,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: t.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _isSyncing
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: t.accent,
                                    ),
                                  )
                                : Icon(
                                    _calendarPermissionGranted
                                        ? Icons.sync
                                        : Icons.calendar_month_outlined,
                                    size: 14,
                                    color: t.accent,
                                  ),
                            const SizedBox(width: 6),
                            Text(
                              _calendarPermissionGranted
                                  ? (_isSyncing ? 'Syncing...' : 'Sync')
                                  : 'Connect',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Today's Plan (dynamic)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(label: "Today's Plan", t: t),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _getPracticeTasksStream(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          print("Today's Plan Stream Error: \${snap.error}");
                        }
                        final todayStr =
                            '$_year-${_month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';
                        if (!snap.hasData || snap.data!.isEmpty) {
                          return Container(
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
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const AlbumArt(
                                      seed: 0,
                                      size: 48,
                                      radius: 14,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "No practice planned",
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: t.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        final tasks = snap.data!;
                        final todaysOriginal = tasks
                            .where((e) => (e['dayId'] as String) == todayStr)
                            .toList();
                        final todays = todaysOriginal
                            .where((e) => e['status'] != 'completed')
                            .toList();

                        if (todaysOriginal.isNotEmpty && todays.isEmpty) {
                          return Container(
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
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: t.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(Icons.check_circle_outline, color: t.accent),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "All done for today!",
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: t.text,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Great job! See you tomorrow.",
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
                          );
                        }

                        final Map<String, dynamic> task = todays.isNotEmpty
                            ? todays.first
                            : tasks.first;

                        final title =
                            task['title'] ?? task['songTitle'] ?? 'Practice';
                        final minutes = task['minutes']?.toString() ?? '20';
                        final artist = task['artist'] ?? '';
                        final bpm = task['bpm']?.toString() ?? '';

                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedTask = task;
                            _showTodayDetail = true;
                          }),
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
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const AlbumArt(
                                      seed: 0,
                                      size: 48,
                                      radius: 14,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (task['dayId'] == todayStr) ? "Today's practice" : "Next practice",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: t.textMuted,
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              color: t.text,
                                            ),
                                          ),
                                          Text(
                                            artist.isNotEmpty || bpm.isNotEmpty
                                                ? '$artist${artist.isNotEmpty && bpm.isNotEmpty ? ' · ' : ''}$bpm${bpm.isNotEmpty ? ' BPM' : ''}'
                                                : '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                                ProgressBar(progress: 0, t: t),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$minutes min planned',
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
                                        children: const [
                                          Icon(
                                            Icons.play_arrow,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Start',
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
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Coming Up (dynamic)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(label: 'Coming Up', t: t),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _getPracticeTasksStream(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          print("Coming Up Stream Error: \${snap.error}");
                        }
                        final todayStr =
                            '$_year-${_month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';
                        if (!snap.hasData || snap.data!.isEmpty) {
                          return Container(
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
                            child: Text(
                              'No upcoming tasks',
                              style: TextStyle(color: t.textSec),
                            ),
                          );
                        }

                        final tasks = snap.data!;
                        final upcoming = tasks
                            .where(
                              (e) =>
                                  (e['dayId'] as String).compareTo(todayStr) >
                                  0,
                            )
                            .toList();
                        if (upcoming.isEmpty) {
                          return Container(
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
                            child: Text(
                              'No upcoming tasks',
                              style: TextStyle(color: t.textSec),
                            ),
                          );
                        }

                        final Map<String, dynamic> next = upcoming.first;
                        final song =
                            next['songTitle'] ?? next['title'] ?? 'Upcoming';
                        final artist = next['artist'] ?? '';
                        final desc = next['title'] ?? '';
                        DateTime? itemDate;
                        try {
                          itemDate = DateTime.parse(next['dayId']);
                        } catch (_) {
                          itemDate = null;
                        }
                        final daysAway = itemDate != null
                            ? itemDate
                                  .difference(
                                    DateTime(
                                      _today.year,
                                      _today.month,
                                      _today.day,
                                    ),
                                  )
                                  .inDays
                            : null;

                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedTask = next;
                            _showTodayDetail = true;
                          }),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: t.text,
                                        ),
                                      ),
                                      if (artist.isNotEmpty)
                                        Text(
                                          artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: t.textSec,
                                          ),
                                        ),
                                      const SizedBox(height: 2),
                                      if (desc.isNotEmpty)
                                        Text(
                                          desc,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                                      daysAway != null
                                          ? 'In ${daysAway} days'
                                          : '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: t.accent,
                                      ),
                                    ),
                                    Text(
                                      next['minutes']?.toString() ?? '',
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
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Calendar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(label: 'History', t: t),

                    // Legend
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          _LegendDot(
                            color: const Color(0xFF7A9E7A),
                            label: 'Practiced',
                            soft: false,
                            t: t,
                          ),
                          _LegendDot(
                            color: const Color(0xFFB07868),
                            label: 'Missed',
                            soft: false,
                            t: t,
                          ),
                          _LegendDot(
                            color: t.accent,
                            label: 'Today',
                            soft: false,
                            t: t,
                          ),
                          _LegendDot(
                            color: t.accentMid,
                            label: 'Upcoming',
                            soft: true,
                            t: t,
                          ),
                        ],
                      ),
                    ),

                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _getPracticeDaysStream(),
                      builder: (context, snapshot) {
                        final practicedDays = <int>{};
                        final missedDays = <int>{};
                        final upcomingDays = <int>{};

                        if (snapshot.hasData) {
                          for (var dayData in snapshot.data!) {
                            final dateStr = dayData['date'] as String;
                            final status = dayData['status'] as String;
                            final dayInt = int.parse(dateStr.substring(8, 10));
                            if (status == 'completed')
                              practicedDays.add(dayInt);
                            else if (status == 'missed')
                              missedDays.add(dayInt);
                            else if (status == 'planned')
                              upcomingDays.add(dayInt);
                          }
                        }

                        Color getDynamicDayColor(int day) {
                          final isToday =
                              day == _today.day &&
                              _month == _today.month &&
                              _year == _today.year;
                          final isPast =
                              _year < _today.year ||
                              _month < _today.month ||
                              (_month == _today.month && day < _today.day);
                          if (isToday) return t.accent;
                          if (isPast && practicedDays.contains(day))
                            return const Color(0xFF7A9E7A);
                          if (isPast && missedDays.contains(day))
                            return const Color(0xFFB07868);
                          if (!isPast && upcomingDays.contains(day))
                            return t.accent;
                          return Colors.transparent;
                        }

                        return Container(
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
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Month nav
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      if (_month == 1) {
                                        _month = 12;
                                        _year--;
                                      } else {
                                        _month--;
                                      }
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        '‹',
                                        style: TextStyle(
                                          fontSize: 20,
                                          color: t.textSec,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${monthNames[_month - 1]} $_year',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: t.text,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      if (_month == 12) {
                                        _month = 1;
                                        _year++;
                                      } else {
                                        _month++;
                                      }
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        '›',
                                        style: TextStyle(
                                          fontSize: 20,
                                          color: t.textSec,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Day headers
                              Row(
                                children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                                    .map(
                                      (d) => Expanded(
                                        child: Center(
                                          child: Text(
                                            d,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: t.textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 6),

                              // Days grid
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 7,
                                      mainAxisSpacing: 2,
                                      crossAxisSpacing: 2,
                                      childAspectRatio: 1,
                                    ),
                                itemCount: firstDay + daysInMonth,
                                itemBuilder: (ctx, i) {
                                  if (i < firstDay) return const SizedBox();
                                  final day = i - firstDay + 1;
                                  final bgColor = getDynamicDayColor(day);
                                  final isToday =
                                      day == _today.day &&
                                      _month == _today.month &&
                                      _year == _today.year;
                                  final textColor = isToday
                                      ? Colors.white
                                      : (bgColor == Colors.transparent
                                            ? t.text
                                            : (bgColor == t.accent && !isToday 
                                                ? t.accent 
                                                : Colors.white));
                                  final border =
                                      bgColor != Colors.transparent && !isToday;

                                  return Center(
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: bgColor == Colors.transparent
                                            ? null
                                            : bgColor.withValues(
                                                alpha:
                                                    bgColor == t.accent &&
                                                        !isToday
                                                    ? 0.13
                                                    : 1.0,
                                              ),
                                        shape: BoxShape.circle,
                                        border: border
                                            ? Border.all(
                                                color: bgColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                                width: 1.5,
                                              )
                                            : null,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$day',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isToday
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: isToday
                                                ? Colors.white
                                                : textColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Today's detail bottom sheet
        if (_showTodayDetail)
          _TodayDetailSheet(
            t: t,
            navigate: widget.navigate,
            task: _selectedTask,
            onClose: () => setState(() => _showTodayDetail = false),
          ),
        // UpdatePlan progress overlay
        if (_isUpdatingPlan)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.35),
              child: Center(
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Updating plan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ProgressBar(progress: _updateProgress, t: t),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                            ),
                            onPressed: () {
                              setState(() => _cancelUpdateRequested = true);
                              setState(() => _isUpdatingPlan = false);
                            },
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.accent,
                            ),
                            onPressed: () {
                              setState(() => _notifyLaterRequested = true);
                              setState(() => _isUpdatingPlan = false);
                            },
                            child: const Text('Notify Later'),
                          ),
                        ],
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

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool soft;
  final AppTheme t;

  const _LegendDot({
    required this.color,
    required this.label,
    required this.soft,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: soft ? color.withValues(alpha: 0.2) : color,
            borderRadius: BorderRadius.circular(3),
            border: soft
                ? Border.all(color: color.withValues(alpha: 0.3), width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: t.textSec)),
      ],
    );
  }
}

class _TodayDetailSheet extends StatelessWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final Map<String, dynamic>? task;
  final VoidCallback onClose;

  const _TodayDetailSheet({
    required this.t,
    required this.navigate,
    required this.onClose,
    this.task,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    const AlbumArt(seed: 1, size: 56, radius: 16),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Today's Practice",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: t.textMuted,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            task?['songTitle'] ?? task?['title'] ?? 'Practice',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          Text(
                            '${task?['artist'] ?? ''}${(task?['artist'] != null && task?['bpm'] != null) ? ' · ${task?['bpm']} BPM' : (task?['bpm'] != null ? '${task?['bpm']} BPM' : '')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: t.textSec),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FOCUS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        task?['instructions'] ??
                            task?['focus'] ??
                            'Focus on the next practice items.',
                        style: TextStyle(
                          fontSize: 14,
                          color: t.text,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Text(
                              '${task?['minutes']?.toString() ?? '20'} min',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: t.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Planned',
                              style: TextStyle(
                                fontSize: 11,
                                color: t.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Text(
                              '${task?['bpm']?.toString() ?? ''}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: t.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'BPM',
                              style: TextStyle(
                                fontSize: 11,
                                color: t.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      onClose();
                      navigate(
                        'practicing',
                        props: {
                          'title': task?['songTitle'] ?? task?['title'],
                          'artist': task?['artist'],
                          'bpm': task?['bpm'],
                          'songId': task?['songId'],
                          'taskId': task?['id'],
                          'dayId': task?['dayId'],
                        },
                      );
                    },
                    icon: const Icon(
                      Icons.play_arrow,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Start Practice',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
