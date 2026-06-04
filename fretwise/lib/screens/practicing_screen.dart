import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import '../theme.dart';

class PracticingScreen extends StatefulWidget {
  final AppTheme t;
  final void Function(String screen, {Map<String, dynamic>? props}) navigate;
  final String title;
  final String artist;
  final int bpm;
  final VoidCallback onOpenAI;

  const PracticingScreen({
    super.key,
    required this.t,
    required this.navigate,
    required this.title,
    required this.artist,
    required this.bpm,
    required this.onOpenAI,
  });

  @override
  State<PracticingScreen> createState() => _PracticingScreenState();
}

class _PracticingScreenState extends State<PracticingScreen> {
  int _seconds = 0;
  bool _running = true;
  bool _videoPlaying = false;
  bool _recording = false;
  String? _activePopup; // 'tuner' | 'metronome' | null
  static bool _strumModalDismissed = false;
  bool _showStrumModal = !_strumModalDismissed;

  // Metronome
  int _metroBpm = 80;
  bool _metroRunning = false;
  int _metroBeat = 0;
  Timer? _metroTimer;
  _MetronomeAudio? _metroAudio;

  // Tuner — real microphone pitch detection
  StreamSubscription<Uint8List>? _micSub;
  late final PitchDetector _pitchDetector;
  final List<int> _rawBuffer = [];
  double _tunerFreq = 0;
  String _tunerNote = '--';
  int _tunerCents = 0;
  int _tunerOctave = 4;
  bool _tunerPitched = false;
  bool _tunerPermDenied = false;
  bool _detecting = false;
  int _lastDetectionMs = 0;

  Timer? _sessionTimer;

  AppTheme get t => widget.t;

  @override
  void initState() {
    super.initState();
    _pitchDetector = PitchDetector(audioSampleRate: 44100.0, bufferSize: 4096);
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_running && mounted) setState(() => _seconds++);
    });
    _metroAudio = _MetronomeAudio();
    _metroAudio!.init();
  }

  void _dismissStrumModal() {
    _strumModalDismissed = true;
    setState(() => _showStrumModal = false);
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _metroTimer?.cancel();
    _micSub?.cancel();
    _metroAudio?.release();
    super.dispose();
  }

  void _startMetronome() {
    _metroTimer?.cancel();
    _metroBeat = 0;
    _metroAudio?.playAccent();
    final ms = (60000 / _metroBpm).round();
    _metroTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted) return;
      final next = (_metroBeat + 1) % 4;
      setState(() => _metroBeat = next);
      if (next == 0) {
        _metroAudio?.playAccent();
      } else {
        _metroAudio?.playTick();
      }
    });
  }

  void _stopMetronome() {
    _metroTimer?.cancel();
    _metroTimer = null;
  }

  Future<void> _startTuner() async {
    if (!mounted) return;
    setState(() {
      _tunerPermDenied = false;
      _tunerPitched = false;
      _tunerNote = '--';
    });
    try {
      // v0.6.x API: returns Future<Stream<Uint8List>?>
      final stream = await MicStream.microphone(
        sampleRate: 44100,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      );
      if (stream == null) {
        if (mounted) setState(() => _tunerPermDenied = true);
        return;
      }
      _micSub = stream.listen(
        (chunk) {
          _rawBuffer.addAll(chunk);
          // Cap to ~0.5 s of audio (44100 Hz × 2 bytes/sample = 88200 bytes)
          if (_rawBuffer.length > 88200) {
            _rawBuffer.removeRange(0, _rawBuffer.length - 88200);
          }
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          // Throttle detection to once per 150 ms; need ≥4096 bytes (2048 Int16 samples)
          if (nowMs - _lastDetectionMs >= 150 && _rawBuffer.length >= 4096) {
            _lastDetectionMs = nowMs;
            final bytes = Uint8List.fromList(_rawBuffer.sublist(0, 4096));
            _rawBuffer.removeRange(0, 4096);
            _processPitch(bytes);
          }
        },
        onError: (e) {
          debugPrint('Tuner stream error: $e');
          if (mounted) setState(() => _tunerPermDenied = true);
        },
      );
    } catch (e) {
      debugPrint('Tuner mic error: $e');
      if (mounted) setState(() => _tunerPermDenied = true);
    }
  }

  Future<void> _processPitch(Uint8List bytes) async {
    if (_detecting) return;
    _detecting = true;
    try {
      // Proper little-endian Int16 → float conversion (library's built-in is big-endian)
      final bd = bytes.buffer.asByteData();
      final floats = <double>[
        for (var i = 0; i + 1 < bytes.length; i += 2)
          bd.getInt16(i, Endian.little) / 32768.0,
      ];
      if (floats.length < _pitchDetector.bufferSize) return;
      final result = await _pitchDetector.getPitchFromFloatBuffer(floats);
      if (!mounted) return;
      if (result.pitched && result.pitch > 60 && result.pitch < 1500) {
        final (note, octave, cents) = _freqToNote(result.pitch);
        setState(() {
          _tunerPitched = true;
          _tunerFreq = result.pitch;
          _tunerNote = note;
          _tunerOctave = octave;
          _tunerCents = cents;
        });
      } else {
        setState(() => _tunerPitched = false);
      }
    } catch (e) {
      debugPrint('Pitch detection error: $e');
    } finally {
      _detecting = false;
    }
  }

  /// Maps a frequency in Hz to the nearest chromatic note, octave, and cents deviation.
  (String, int, int) _freqToNote(double freq) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    // A4 = 440 Hz = MIDI 69
    final midiExact = 12.0 * log(freq / 440.0) / log(2.0) + 69.0;
    final midiRound = midiExact.round();
    final cents = ((midiExact - midiRound) * 100).round().clamp(-50, 50);
    final noteIdx = ((midiRound % 12) + 12) % 12;
    final octave = (midiRound ~/ 12) - 1;
    return (names[noteIdx], octave, cents);
  }

  void _stopTuner() {
    _micSub?.cancel();
    _micSub = null;
    _rawBuffer.clear();
    if (mounted) setState(() { _tunerPitched = false; _tunerNote = '--'; });
  }

  void _handleToolTap(String id) {
    if (id == 'record') {
      setState(() => _recording = !_recording);
      return;
    }
    if (_activePopup == id) {
      setState(() => _activePopup = null);
      if (id == 'metronome') { _metroRunning = false; _stopMetronome(); }
      if (id == 'tuner') _stopTuner();
    } else {
      if (_activePopup == 'metronome') { _metroRunning = false; _stopMetronome(); }
      if (_activePopup == 'tuner') _stopTuner();
      setState(() => _activePopup = id);
      if (id == 'tuner') _startTuner();
    }
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 💡 1. 這裡包上 SingleChildScrollView，讓畫面超出時可以滑動
        SingleChildScrollView(
          child: Container(
            // 💡 2. 設定最小高度為螢幕高度，確保按鈕還是會被推到最下面
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            child: Column(
              children: [
                // Header
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () { _running = false; widget.navigate('library'); },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.arrow_back, size: 22, color: t.text),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
                        ),
                        Text(widget.artist, style: TextStyle(fontSize: 13, color: t.textSec)),
                      ],
                    ),
                  ),
                ),

                // Timer
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: t.border),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SESSION TIME',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.textMuted, letterSpacing: 0.7)),
                            const SizedBox(height: 2),
                            Text(
                              _fmt(_seconds),
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: t.text,
                                letterSpacing: -2,
                                height: 1,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _running = !_running),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _running ? t.accent : t.surfaceAlt,
                            ),
                            child: Icon(
                              _running ? Icons.pause : Icons.play_arrow,
                              size: 22,
                              color: _running ? Colors.white : t.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Tools row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(
                    children: [
                      Expanded(child: _ToolButton(id: 'tuner', label: 'Tuner', icon: Icons.graphic_eq, color: AppColors.blue, active: _activePopup == 'tuner', t: t, onTap: () => _handleToolTap('tuner'))),
                      const SizedBox(width: 10),
                      Expanded(child: _ToolButton(id: 'record', label: _recording ? 'Stop' : 'Record', icon: Icons.mic, color: AppColors.red, active: _recording, t: t, onTap: () => _handleToolTap('record'))),
                      const SizedBox(width: 10),
                      Expanded(child: _ToolButton(id: 'metronome', label: 'Metronome', icon: Icons.tune, color: AppColors.green, active: _activePopup == 'metronome', t: t, onTap: () => _handleToolTap('metronome'))),
                    ],
                  ),
                ),

                // Video
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _videoPlaying = !_videoPlaying),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF2A2420), Color(0xFF1A1510)],
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: 52, height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.18),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                                ),
                                child: Icon(
                                  _videoPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 22, color: Colors.white,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                                  ),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${widget.title} — Tutorial',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                    Text('${widget.artist} · Tap to ${_videoPlaying ? "pause" : "play"}',
                                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Tool panel
                if (_activePopup != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _activePopup == 'tuner'
                        ? _TunerPanel(
                            t: t,
                            note: _tunerNote,
                            octave: _tunerOctave,
                            freq: _tunerFreq,
                            cents: _tunerCents,
                            pitched: _tunerPitched,
                            permDenied: _tunerPermDenied,
                            onClose: () => _handleToolTap('tuner'),
                          )
                        : _MetronomePanel(
                            t: t,
                            bpm: _metroBpm,
                            running: _metroRunning,
                            beat: _metroBeat,
                            onBpmChange: (v) {
                              setState(() => _metroBpm = v);
                              if (_metroRunning) { _stopMetronome(); _startMetronome(); }
                            },
                            onToggle: () => setState(() {
                              _metroRunning = !_metroRunning;
                              _metroRunning ? _startMetronome() : _stopMetronome();
                            }),
                            onClose: () => _handleToolTap('metronome'),
                          ),
                  ),

                // 💡 3. 將 Spacer() 換成彈性空白，避免 ScrollView 當機
                const SizedBox(height: 40),

                // Finish button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        _running = false;
                        widget.navigate('sessionComplete', props: {
                          'title': widget.title,
                          'artist': widget.artist,
                          'duration': _seconds,
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: t.border, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Finish Session',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
                    ),
                  ),
                ),
                
                // 給底部留一點安全距離
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),

        // AI button
        Positioned(
          bottom: 84,
          right: 20,
          child: GestureDetector(
            onTap: widget.onOpenAI,
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF5E8275),
                boxShadow: [BoxShadow(color: const Color(0xFF5E8275).withValues(alpha: 0.4), blurRadius: 20)],
              ),
              child: const Icon(Icons.chat_bubble_outline, size: 22, color: Colors.white),
            ),
          ),
        ),

        // Strum modal
        if (_showStrumModal)
          GestureDetector(
            onTap: () => setState(() => _showStrumModal = false),
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 48),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: GestureDetector(
                              onTap: () => setState(() => _showStrumModal = false),
                              child: Container(
                                width: 30, height: 30,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: t.surfaceAlt),
                                child: Center(child: Text('✕', style: TextStyle(fontSize: 16, color: t.textMuted))),
                              ),
                            ),
                          ),
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [t.accent.withValues(alpha: 0.13), t.accent.withValues(alpha: 0.27)],
                              ),
                            ),
                            child: Icon(Icons.mic, size: 26, color: t.accent),
                          ),
                          const SizedBox(height: 16),
                          Text("We'll listen to you strum",
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.text, fontFamily: 'Georgia', height: 1.2)),
                          const SizedBox(height: 8),
                          Text(
                            "Fretwise uses your microphone to give real-time feedback on your playing. Make sure your guitar is in tune and you're in a quiet spot.",
                            style: TextStyle(fontSize: 14, color: t.textSec, height: 1.6),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => setState(() => _showStrumModal = false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.accent,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text("Got it, let's play",
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _dismissStrumModal,
                              child: Text("Don't show again",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: t.textMuted)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final AppTheme t;
  final VoidCallback onTap;

  const _ToolButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRecord = id == 'record';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: active && isRecord ? AppColors.red : active ? color.withValues(alpha: 0.094) : t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? color : t.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: color.withValues(alpha: 0.094),
              ),
              child: Icon(icon, size: 17, color: active && isRecord ? Colors.white : color),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active && isRecord ? Colors.white : t.text,
                )),
          ],
        ),
      ),
    );
  }
}

class _TunerPanel extends StatelessWidget {
  final AppTheme t;
  final String note;
  final int octave;
  final double freq;
  final int cents;
  final bool pitched;
  final bool permDenied;
  final VoidCallback onClose;

  const _TunerPanel({
    required this.t,
    required this.note,
    required this.octave,
    required this.freq,
    required this.cents,
    required this.pitched,
    required this.permDenied,
    required this.onClose,
  });

  bool get inTune => pitched && cents.abs() <= 8;

  @override
  Widget build(BuildContext context) {
    final noteStr = pitched ? '$note$octave' : '--';
    final freqStr = pitched ? '${freq.toStringAsFixed(1)} Hz' : '';
    final String statusStr;
    final Color statusColor;

    if (permDenied) {
      statusStr = 'Microphone access denied';
      statusColor = AppColors.red;
    } else if (!pitched) {
      statusStr = 'Play a note...';
      statusColor = t.textMuted;
    } else if (inTune) {
      statusStr = '✓ In tune';
      statusColor = AppColors.green;
    } else {
      statusStr = '${cents > 0 ? "+" : ""}$cents cents';
      statusColor = t.textSec;
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TUNER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.textMuted, letterSpacing: 0.8)),
              GestureDetector(
                onTap: onClose,
                child: Text('✕', style: TextStyle(fontSize: 18, color: t.textMuted)),
              ),
            ],
          ),
          Text(
            noteStr,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: inTune ? AppColors.green : t.text,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          if (freqStr.isNotEmpty)
            Text(freqStr, style: TextStyle(fontSize: 11, color: t.textMuted, fontWeight: FontWeight.w500)),
          Text(
            statusStr,
            style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
          ),
          SizedBox(
            height: 78,
            child: CustomPaint(
              size: const Size(double.infinity, 78),
              painter: _TunerPainter(
                cents: pitched ? cents.toDouble() : 0.0,
                inTune: inTune,
                borderColor: t.border,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TunerPainter extends CustomPainter {
  final double cents; // -50..+50
  final bool inTune;
  final Color borderColor;

  _TunerPainter({required this.cents, required this.inTune, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 4;
    const r = 58.0;

    final arcPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final greenPaint = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final needlePaint = Paint()
      ..color = inTune ? AppColors.green : AppColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Half-circle arc: from pi (left) sweeping pi radians to 2*pi (right)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      pi, pi, false, arcPaint,
    );

    // Green "in tune" zone centred at the top (3π/2), spanning ±8 cents
    // 8 cents → 8/50 * (π/2) ≈ 0.25 rad on each side
    const greenHalfSpan = 0.25;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      3 * pi / 2 - greenHalfSpan,
      greenHalfSpan * 2,
      false,
      greenPaint,
    );

    // Needle: cents=0 → straight up (3π/2), ±50 → left/right ends
    final angle = 3 * pi / 2 + (cents.clamp(-50.0, 50.0) / 50.0) * (pi / 2);
    final nx = cx + (r - 6) * cos(angle);
    final ny = cy + (r - 6) * sin(angle);
    canvas.drawLine(Offset(cx, cy), Offset(nx, ny), needlePaint);

    // Pivot dot
    canvas.drawCircle(
      Offset(cx, cy),
      4.5,
      Paint()..color = inTune ? AppColors.green : AppColors.blue,
    );
  }

  @override
  bool shouldRepaint(_TunerPainter old) =>
      old.cents != cents || old.inTune != inTune;
}

class _MetronomePanel extends StatelessWidget {
  final AppTheme t;
  final int bpm;
  final bool running;
  final int beat;
  final ValueChanged<int> onBpmChange;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  const _MetronomePanel({
    required this.t,
    required this.bpm,
    required this.running,
    required this.beat,
    required this.onBpmChange,
    required this.onToggle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('METRONOME', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textMuted, letterSpacing: 0.8)),
              GestureDetector(
                onTap: onClose,
                child: Text('✕', style: TextStyle(fontSize: 18, color: t.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running && beat % 4 == i
                      ? (i == 0 ? AppColors.red : AppColors.green)
                      : t.surfaceAlt,
                  border: i == 0 ? Border.all(color: AppColors.red.withValues(alpha: 0.19), width: 2) : Border.all(color: t.border),
                ),
              ),
            )),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => onBpmChange((bpm - 1).clamp(40, 240)),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: t.surfaceAlt),
                  child: Center(child: Text('−', style: TextStyle(fontSize: 22, color: t.text))),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 80,
                child: Column(
                  children: [
                    Text('$bpm',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: t.text, letterSpacing: -2, height: 1)),
                    Text('BPM', style: TextStyle(fontSize: 11, color: t.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.7)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => onBpmChange((bpm + 1).clamp(40, 240)),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: t.surfaceAlt),
                  child: Center(child: Text('+', style: TextStyle(fontSize: 22, color: t.text))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Slider(
            value: bpm.toDouble(),
            min: 40,
            max: 240,
            onChanged: (v) => onBpmChange(v.round()),
            activeColor: AppColors.green,
            inactiveColor: t.border,
          ),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: running ? AppColors.green : t.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Center(
                  child: Text(
                    running ? '⏸ Stop' : '▶ Start',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: running ? Colors.white : t.text),
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

class _MetronomeAudio {
  AudioPlayer? _accentPlayer;
  AudioPlayer? _tickPlayer;
  Uint8List? _accentWav;
  Uint8List? _tickWav;
  bool _ready = false;

  Future<void> init() async {
    try {
      _accentWav = _buildWav(freq: 1050, durationMs: 65);
      _tickWav = _buildWav(freq: 620, durationMs: 40);
      _accentPlayer = AudioPlayer();
      _tickPlayer = AudioPlayer();
      await _accentPlayer!.setPlayerMode(PlayerMode.lowLatency);
      await _tickPlayer!.setPlayerMode(PlayerMode.lowLatency);
      await _accentPlayer!.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      await _tickPlayer!.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('MetronomeAudio init: $e');
    }
  }

  void playAccent() {
    if (!_ready) return;
    _accentPlayer!.play(BytesSource(_accentWav!));
  }

  void playTick() {
    if (!_ready) return;
    _tickPlayer!.play(BytesSource(_tickWav!));
  }

  void release() {
    _accentPlayer?.dispose();
    _tickPlayer?.dispose();
    _accentPlayer = null;
    _tickPlayer = null;
    _ready = false;
  }

  static Uint8List _buildWav({required int freq, required int durationMs}) {
    const sr = 44100;
    final n = (sr * durationMs / 1000).round();
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      final env = 1.0 - (i / n);
      pcm[i] = (sin(2 * pi * freq * i / sr) * env * 28000)
          .round()
          .clamp(-32768, 32767);
    }
    final pcmBytes = pcm.buffer.asUint8List();
    final wav = ByteData(44 + pcmBytes.length);
    void ws(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        wav.setUint8(o + i, s.codeUnitAt(i));
      }
    }
    ws(0, 'RIFF'); wav.setUint32(4, 36 + pcmBytes.length, Endian.little);
    ws(8, 'WAVE');
    ws(12, 'fmt '); wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, sr, Endian.little);
    wav.setUint32(28, sr * 2, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    ws(36, 'data'); wav.setUint32(40, pcmBytes.length, Endian.little);
    final result = wav.buffer.asUint8List();
    result.setRange(44, 44 + pcmBytes.length, pcmBytes);
    return result;
  }
}
