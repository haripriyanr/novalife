import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';                    // ✅ Correct import
import 'package:audioplayers/audioplayers.dart';       // ✅ Correct import
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();    // ✅ Fixed
  final AudioPlayer _audioPlayer = AudioPlayer();          // ✅ Fixed

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _hasPermission = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;

  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _setupAnimations();
    _setupAudioPlayer();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _setupAudioPlayer() {
    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _playbackDuration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _playbackPosition = position;
      });
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _isPlaying = false;
        _playbackPosition = Duration.zero;
      });
    });
  }

  // ✅ Check microphone permission
  Future<void> _checkPermissions() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
      });
    } else {
      final result = await Permission.microphone.request();
      setState(() {
        _hasPermission = result.isGranted;
      });
    }
  }

  // ✅ Start recording with correct API
  Future<void> _startRecording() async {
    if (!_hasPermission) {
      _showErrorMessage('Microphone permission required');
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), // ✅ Fixed config
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _recordingPath = filePath;
        _recordingDuration = Duration.zero;
      });

      _pulseController.repeat(reverse: true);
      _startTimer();

      _showSuccessMessage('Recording started');
    } catch (e) {
      _showErrorMessage('Failed to start recording: $e');
    }
  }

  // ✅ Stop recording
  Future<void> _stopRecording() async {
    try {
      await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      _pulseController.stop();

      _showSuccessMessage('Recording saved');
    } catch (e) {
      _showErrorMessage('Failed to stop recording: $e');
    }
  }

  // ✅ Play recording with correct API
  Future<void> _playRecording() async {
    if (_recordingPath == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
      } else {
        await _audioPlayer.play(DeviceFileSource(_recordingPath!)); // ✅ Fixed
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (e) {
      _showErrorMessage('Failed to play recording: $e');
    }
  }

  // ✅ Delete recording
  Future<void> _deleteRecording() async {
    if (_recordingPath == null) return;

    try {
      final file = File(_recordingPath!);
      if (await file.exists()) {
        await file.delete();
      }

      await _audioPlayer.stop();

      setState(() {
        _recordingPath = null;
        _isPlaying = false;
        _recordingDuration = Duration.zero;
        _playbackDuration = Duration.zero;
        _playbackPosition = Duration.zero;
      });

      _showSuccessMessage('Recording deleted');
    } catch (e) {
      _showErrorMessage('Failed to delete recording: $e');
    }
  }

  void _startTimer() {
    Stream.periodic(const Duration(seconds: 1), (i) => i).listen((timer) {
      if (_isRecording && mounted) {
        setState(() {
          _recordingDuration = Duration(seconds: timer + 1);
        });
      }
    });
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_hasPermission) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_off,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'Microphone Permission Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please grant microphone permission to record audio',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checkPermissions,
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Header
                Text(
                  'Voice Recorder',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Record and play audio messages',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),

                // Recording visualization
                Expanded(
                  child: _buildRecordingVisualization(isDark),
                ),

                // Playback controls
                if (_recordingPath != null) ...[
                  _buildPlaybackControls(isDark),
                  const SizedBox(height: 24),
                ],

                // Action buttons
                _buildActionButtons(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingVisualization(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Recording button with animation
          AnimatedBuilder(
            animation: _isRecording ? _pulseAnimation : Listenable.merge([]),
            builder: (context, child) {
              return Transform.scale(
                scale: _isRecording ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.blue,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : Colors.blue)
                            .withAlpha(102),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),

          // Recording status
          if (_isRecording) ...[
            Text(
              'Recording...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'monospace',
              ),
            ),
          ] else if (_recordingPath != null) ...[
            Text(
              'Recording Ready',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'monospace',
              ),
            ),
          ] else ...[
            Text(
              'Tap to Record',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(51)
                : Colors.grey.withAlpha(51),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.audiotrack,
                color: Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Playback',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              Text(
                '${_formatDuration(_playbackPosition)} / ${_formatDuration(_playbackDuration)}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _playbackDuration.inMilliseconds > 0
                  ? _playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds
                  : 0.0,
              onChanged: (value) async {
                final position = Duration(
                  milliseconds: (value * _playbackDuration.inMilliseconds).round(),
                );
                await _audioPlayer.seek(position);
              },
              activeColor: Colors.blue,
              inactiveColor: Colors.grey[300],
            ),
          ),

          // Play/Pause button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _playRecording,
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 48,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Column(
      children: [
        if (_recordingPath != null && !_isRecording) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _deleteRecording,
              icon: const Icon(Icons.delete),
              label: const Text('Delete Recording'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isRecording ? _stopRecording : _startRecording,
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecording ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
