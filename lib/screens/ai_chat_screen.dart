import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cactus/cactus.dart';
import 'package:cactus/chat.dart'; // Use cactus ChatMessage
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

// TTS State Management
enum TtsState { stopped, playing }

class AIChatScreen extends StatefulWidget {
  @override
  _AIChatScreenState createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Core AI Components
  bool _isModelLoading = false;
  bool _isModelReady = false;
  String? _modelPath;
  bool _isVisionCapable = false;

  double? _loadingProgress;
  String _loadingMessage = "Initializing...";

  // Chat State & History Management
  final List<AppChatMessage> _messages = [];
  final List<ChatMessage> _chatHistory = []; // Use cactus ChatMessage
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  bool _isTyping = false;
  int _messageIdCounter = 0;

  // Isolate for LLM processing
  Isolate? _llmIsolate;
  ReceivePort? _llmReceivePort;
  SendPort? _llmSendPort;
  StreamSubscription? _llmStreamSubscription;
  ReceivePort? _currentResponsePort;

  // Voice Components
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  bool _speechEnabled = false;
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;

  // TTS State Management
  TtsState _ttsState = TtsState.stopped;
  String? _currentSpeakingText;

  // Image Processing
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  // Settings
  bool _autoSpeak = false;

  // User-editable System Prompts for MediBot
  String _chatSystemPrompt = "You are MediBot, a compassionate AI health assistant. Your primary goal is to provide supportive and informative guidance. When a user describes symptoms like a fever, express genuine concern for their well-being ('I'm sorry to hear you're feeling unwell.'). Offer safe, general home-care suggestions (e.g., rest, hydration). Crucially, you must ALWAYS emphasize that you are not a doctor and that they must consult a healthcare professional for a proper diagnosis and treatment. If symptoms sound severe or persistent, strongly advise them to seek immediate medical attention at a hospital or clinic.";
  String _visionSystemPrompt = "You are an AI assistant analyzing a health-related image. Express concern and **under no circumstances** attempt to diagnose. Describe the image's visual characteristics neutrally and strongly advise the user to show the image to a qualified healthcare professional for an accurate diagnosis and treatment.";

  // User-configurable LLM settings for MediBot
  int _contextSize = 4096;
  int _threads = 4;
  int _gpuLayers = 0;
  double _temperature = 0.9;  // Lowered for more factual and less random output
  double _topP = 0.9;
  int _topK = 0;
  double _repeatPenalty = 1.05; // Increased to prevent repetition
  int _maxTokens = 512;      // Reduced to prevent overly long responses

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeComponents();
  }

  void _initializeAnimations() {
    _micAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _micAnimation = Tween<double>(begin: 0.8, end: 1.3).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );

    _typingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _typingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _typingAnimationController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeComponents() async {
    try {
      await _requestAllPermissions();
      await Future.wait([
        _initializeSpeech(),
        _initializeTTS(),
      ]);
      await _loadModel();
    } catch (e) {
      _showErrorDialog('Initialization failed: $e');
    }
  }

  Future<void> _requestAllPermissions() async {
    List<Permission> permissions = [
      Permission.microphone,
      Permission.camera,
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.photos,
      Permission.videos,
    ];
    await permissions.request();
  }

  Future<void> _initializeSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          print('Speech Error: $error');
          if (mounted) {
            setState(() => _isListening = false);
            _micAnimationController.stop();
          }
        },
        onStatus: (status) {
          print('Speech Status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
              _micAnimationController.stop();
            }
          }
        },
      );
    } catch (e) {
      print('Speech initialization error: $e');
      _speechEnabled = false;
    }
  }

  Future<void> _initializeTTS() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5); // Slower, more natural rate
      await _flutterTts.setVolume(0.9);
      await _flutterTts.setPitch(0.9); // Slightly lower pitch for better quality

      if (Platform.isIOS) {
        await _flutterTts.setSharedInstance(true);
      }

      // Set up TTS event handlers
      _flutterTts.setStartHandler(() {
        if (mounted) {
          setState(() => _ttsState = TtsState.playing);
        }
      });

      _flutterTts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _ttsState = TtsState.stopped;
            _currentSpeakingText = null;
          });
        }
      });

      _flutterTts.setErrorHandler((message) {
        if (mounted) {
          setState(() {
            _ttsState = TtsState.stopped;
            _currentSpeakingText = null;
          });
        }
      });

      _flutterTts.setCancelHandler(() {
        if (mounted) {
          setState(() {
            _ttsState = TtsState.stopped;
            _currentSpeakingText = null;
          });
        }
      });
    } catch (e) {
      print('TTS initialization error: $e');
    }
  }

  Future<void> _loadModel() async {
    if (!mounted) return;
    setState(() {
      _isModelLoading = true;
      _loadingProgress = 0.0;
      _loadingMessage = "Searching for model...";
    });
    try {
      _modelPath = await _getModelFromStorage();
      await _cleanupIsolate();
      _llmReceivePort = ReceivePort();
      _llmStreamSubscription = _llmReceivePort!.asBroadcastStream().listen(_handleIsolateMessage);
      final isolateParams = IsolateParams(
        modelPath: _modelPath!,
        sendPort: _llmReceivePort!.sendPort,
        contextSize: _contextSize,
        threads: _threads,
        gpuLayers: _gpuLayers,
        temperature: _temperature,
        topP: _topP,
        topK: _topK,
        repeatPenalty: _repeatPenalty,
        maxTokens: _maxTokens,
      );
      _llmIsolate = await Isolate.spawn(_llmIsolateEntryPoint, isolateParams);
    } catch (e) {
      setState(() {
        _isModelLoading = false;
        _loadingProgress = null;
        _loadingMessage = "Failed to load model";
      });
      if (e.toString().contains('not found')) {
        _showModelNotFoundDialog();
      } else {
        _showErrorDialog('Model error: $e');
      }
    }
  }

  void _handleIsolateMessage(dynamic message) {
    if (!mounted || message is! Map) return;
    switch (message['type']) {
      case 'progress':
        setState(() {
          _loadingProgress = 0.2 + ((message['value'] ?? 0.0) * 0.8);
          _loadingMessage = message['message'] ?? '';
        });
        break;
      case 'ready':
        setState(() {
          _isModelReady = true;
          _isModelLoading = false;
          _loadingProgress = 1.0;
          _isVisionCapable = message['vision_capable'] ?? false;
        });
        _addSystemMessage(
            "🩺 MediBot is ready to help. ${_isVisionCapable ? 'You can also send images. ' : ''}How are you feeling today?");
        break;
      case 'error':
        setState(() {
          _isModelLoading = false;
          _loadingProgress = null;
          _loadingMessage = "Failed to load model";
        });
        _showErrorDialog('Model error: ${message['error']}');
        break;
      case 'prompt_port':
        _llmSendPort = message['port'];
        break;
    }
  }

  Future<String> _getModelFromStorage() async {
    final searchPaths = await _getModelSearchPaths();
    for (String path in searchPaths) {
      if (mounted) {
        setState(() => _loadingMessage = "Checking: ${path.split('/').last}");
      }
      if (await _validateModelFile(path)) {
        final file = File(path);
        final fileSize = await file.length();
        if (mounted) {
          setState(() {
            _loadingMessage = "Found: ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB";
          });
        }
        return path;
      }
    }
    throw Exception('novalife.gguf not found in any storage location');
  }

  Future<List<String>> _getModelSearchPaths() async {
    List<String> paths = [];
    if (Platform.isAndroid) {
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          paths.addAll([
            '/storage/emulated/0/Download/novalife.gguf',
            '/sdcard/Download/novalife.gguf',
            '${externalDir.parent.parent.parent.parent.path}/Download/novalife.gguf',
            '${externalDir.path}/novalife.gguf',
          ]);
        }
        final appDir = await getApplicationDocumentsDirectory();
        paths.add('${appDir.path}/novalife.gguf');
      } catch (e) {
        print('Android path error: $e');
      }
    } else if (Platform.isIOS) {
      try {
        final dirs = await Future.wait([
          getApplicationDocumentsDirectory(),
          getApplicationSupportDirectory(),
          getLibraryDirectory(),
        ]);
        for (final dir in dirs) {
          paths.addAll([
            '${dir.path}/novalife.gguf',
            '${dir.path}/models/novalife.gguf',
          ]);
        }
      } catch (e) {
        print('iOS path error: $e');
      }
    }
    return paths;
  }

  Future<bool> _validateModelFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final fileSize = await file.length();
      if (fileSize < 1024 * 1024) return false; // At least 1MB
      final handle = await file.open();
      final testBytes = await handle.read(1024);
      await handle.close();
      return testBytes.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _sendMessage(String text, {File? image}) async {
    if ((text.trim().isEmpty && image == null) || !_isModelReady || _isGenerating) return;

    final messageText = text.trim();
    _textController.clear();
    setState(() {
      _selectedImage = null;
    });

    final userMessage = AppChatMessage(
      id: _messageIdCounter++,
      text: messageText,
      isUser: true,
      timestamp: DateTime.now(),
      image: image,
      messageType: MessageType.chat,
    );

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
      _isTyping = true;
    });
    _scrollToBottom();
    _typingAnimationController.repeat();

    if (_chatHistory.isEmpty) {
      _chatHistory.clear();
      final systemPrompt = _getActiveSystemPrompt(image != null);
      _chatHistory.add(ChatMessage(role: 'system', content: systemPrompt));
    }

    String userContent = messageText;
    if (image != null) {
      userContent += "\n\n[User attached an image for analysis]";
    }
    _chatHistory.add(ChatMessage(role: 'user', content: userContent));

    final loadingMessage = AppChatMessage(
      id: _messageIdCounter++,
      text: "",
      isUser: false,
      timestamp: DateTime.now(),
      messageType: MessageType.chat,
      isLoading: true,
    );
    setState(() => _messages.add(loadingMessage));
    _scrollToBottom();

    _currentResponsePort = ReceivePort();
    _currentResponsePort!.listen(_handleResponse);

    _llmSendPort?.send({
      'chat_history': _chatHistory.map((msg) => {
        'role': msg.role,
        'content': msg.content,
      }).toList(),
      'response_port': _currentResponsePort!.sendPort,
      'has_image': image != null,
      'max_tokens': _maxTokens,
    });
  }

  String _getActiveSystemPrompt(bool hasImage) {
    if (hasImage) return _visionSystemPrompt;
    return _chatSystemPrompt;
  }

  void _handleResponse(dynamic message) {
    if (!mounted || message is! Map) return;
    setState(() {
      switch (message['type']) {
        case 'token':
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last.text += message['token'];
            _messages.last.isLoading = false;
          }
          break;
        case 'done':
          _isGenerating = false;
          _isTyping = false;
          _typingAnimationController.stop();
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            final responseText = _messages.last.text.trim();
            _messages.last.isLoading = false;
            if (responseText.isNotEmpty) {
              _chatHistory.add(ChatMessage(role: 'assistant', content: responseText));
              if (_autoSpeak) _speak(responseText);
            }
          }
          _currentResponsePort?.close();
          _currentResponsePort = null;
          break;
        case 'error':
          _isGenerating = false;
          _isTyping = false;
          _typingAnimationController.stop();
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last.text = "I encountered an error: ${message['error']}";
            _messages.last.isLoading = false;
          }
          _currentResponsePort?.close();
          _currentResponsePort = null;
          break;
      }
    });
    _scrollToBottom();
  }

  static Future<void> _llmIsolateEntryPoint(IsolateParams params) async {
    final sendPort = params.sendPort;
    CactusContext? cactusContext;
    try {
      sendPort.send({
        'type': 'progress',
        'value': 0.1,
        'message': 'Initializing LLM context...'
      });

      final initParams = CactusInitParams(
        modelPath: params.modelPath,
        nCtx: params.contextSize,
        nThreads: params.threads,
        nGpuLayers: params.gpuLayers,
        onInitProgress: (progress, message, isError) {
          sendPort.send({
            'type': 'progress',
            'value': progress ?? 0.0,
            'message': message ?? 'Loading...',
          });
          if (isError) {
            sendPort.send({
              'type': 'error',
              'error': 'Initialization failed: $message',
            });
          }
        },
      );

      cactusContext = await CactusContext.init(initParams);

      bool visionCapable = params.modelPath.toLowerCase().contains('vision') ||
          params.modelPath.toLowerCase().contains('multimodal') ||
          params.modelPath.toLowerCase().contains('llava');

      sendPort.send({
        'type': 'ready',
        'vision_capable': visionCapable,
      });

      final promptPort = ReceivePort();
      sendPort.send({
        'type': 'prompt_port',
        'port': promptPort.sendPort,
      });

      await for (final prompt in promptPort) {
        if (prompt is Map) {
          final List<dynamic> chatHistoryRaw = prompt['chat_history'] ?? [];
          final SendPort responsePort = prompt['response_port'];
          final bool hasImage = prompt['has_image'] ?? false;
          final int maxTokens = prompt['max_tokens'] ?? 256;

          // Variables for manual stop sequence detection
          String accumulatedResponse = "";
          final stopSequences = ['\nuser:', 'user:', '<|user|>', '\nMediBot:', 'assistant:'];

          try {
            final chatMessages = chatHistoryRaw.map((msg) => ChatMessage(
              role: msg['role'],
              content: msg['content'],
            )).toList();

            if (hasImage && chatMessages.isNotEmpty) {
              final lastUserMessage = chatMessages.last;
              if (lastUserMessage.role == 'user') {
                chatMessages[chatMessages.length - 1] = ChatMessage(
                  role: 'user',
                  content: "${lastUserMessage.content}\n\nPlease analyze the attached image carefully and provide detailed insights.",
                );
              }
            }

            final completionParams = CactusCompletionParams(
              messages: chatMessages,
              nPredict: maxTokens,
              temperature: params.temperature,
              topK: params.topK,
              topP: params.topP,
              penaltyRepeat: params.repeatPenalty,
              onNewToken: (token) {
                accumulatedResponse += token;
                for (final stopSeq in stopSequences) {
                  if (accumulatedResponse.trim().endsWith(stopSeq)) {
                    responsePort.send({'type': 'done'}); // Stop generation
                    return false;
                  }
                }
                responsePort.send({
                  'type': 'token',
                  'token': token,
                });
                return true;
              },
            );

            await cactusContext.completion(completionParams);
            responsePort.send({'type': 'done'});
          } catch (e) {
            responsePort.send({
              'type': 'error',
              'error': 'Generation failed: $e',
            });
          }
        }
      }
    } catch (e) {
      sendPort.send({
        'type': 'error',
        'error': 'LLM isolate error: $e',
      });
    } finally {
      cactusContext?.free();
    }
  }

  Future<void> _cleanupIsolate() async {
    _llmIsolate?.kill(priority: Isolate.immediate);
    _llmReceivePort?.close();
    await _llmStreamSubscription?.cancel();
    _currentResponsePort?.close();
    _llmIsolate = null;
    _llmReceivePort = null;
    _llmStreamSubscription = null;
    _llmSendPort = null;
    _currentResponsePort = null;
  }

  void _addSystemMessage(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(AppChatMessage(
        id: _messageIdCounter++,
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
        messageType: MessageType.system,
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _stopGeneration() {
    if (_isGenerating) {
      _currentResponsePort?.close();
      _currentResponsePort = null;
      setState(() {
        _isGenerating = false;
        _isTyping = false;
        _typingAnimationController.stop();
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          _messages.last.isLoading = false;
          if (_messages.last.text.trim().isEmpty) {
            _messages.last.text = "[Generation stopped by user]";
          }
        }
      });
    }
  }

  void _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showSnackBar('Copied to clipboard!', Icons.check_circle, Colors.blue);
  }

  Future<void> _startListening() async {
    if (!_speechEnabled || _isListening) return;
    setState(() => _isListening = true);
    _micAnimationController.repeat(reverse: true);
    await _speechToText.listen(
      onResult: (result) {
        if (mounted) setState(() => _textController.text = result.recognizedWords);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (mounted) {
      setState(() => _isListening = false);
      _micAnimationController.stop();
    }
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    if (_ttsState == TtsState.playing) {
      await _flutterTts.stop();
      setState(() {
        _ttsState = TtsState.stopped;
        _currentSpeakingText = null;
      });
      return;
    }

    final cleanText = text
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'\1')
        .replaceAll(RegExp(r'`([^`]+)`'), r'\1')
        .replaceAll(RegExp(r'#{1,6}\s+'), '')
        .replaceAll(RegExp(r'\n+'), ' ');

    setState(() => _currentSpeakingText = text);
    await _flutterTts.speak(cleanText);
  }

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        final file = File(image.path);
        final fileSize = await file.length();
        if (fileSize > 10 * 1024 * 1024) {
          _showSnackBar('Image too large (>10MB)', Icons.warning, Colors.orange);
          return;
        }
        setState(() => _selectedImage = file);
        _showSnackBar('Image selected successfully!', Icons.check_circle, Colors.blue);
      }
    } catch (e) {
      _showErrorDialog('Failed to select image: $e');
    }
  }

  void _showImagePickerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select Image Source',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImageSourceOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(source: ImageSource.camera);
                  },
                ),
                _buildImageSourceOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(source: ImageSource.gallery);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isDarkMode ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.blue[600]),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, IconData icon, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red[600]),
            const SizedBox(width: 8),
            Text('Error', style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black)),
          ],
        ),
        content: Text(message, style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showModelNotFoundDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[600], size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Model Not Found',
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The novalife.gguf model file was not found.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Please ensure you have:',
                style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 8),
              _buildBulletPoint('Downloaded novalife.gguf model file'),
              _buildBulletPoint('Placed it in the correct folder'),
              _buildBulletPoint('File is not corrupted (size > 1 MB)'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isDarkMode ? Colors.blue[900] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[300]!),
                ),
                child: Text(
                  Platform.isIOS
                      ? 'iOS: Place in Files app > On My iPhone > NovaLife > Documents'
                      : 'Android: /storage/emulated/0/Download/novalife.gguf',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isDarkMode ? Colors.blue[300] : Colors.blue[800],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('Exit App', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _loadModel();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: Colors.blue[600], fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _chatHistory.clear();
    });
    if (_isModelReady) {
      _addSystemMessage("🩺 Chat cleared. How can I assist you further?");
    }
  }

  void _showSettingsDialog() {
    int tempContext = _contextSize;
    int tempThreads = _threads;
    int tempGpu = _gpuLayers;
    double tempTemp = _temperature;
    double tempTopP = _topP;
    int tempTopK = _topK;
    double tempRepeatPenalty = _repeatPenalty;
    int tempMaxTokens = _maxTokens;
    String tempChatPrompt = _chatSystemPrompt;
    String tempVisionPrompt = _visionSystemPrompt;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
              title: Row(
                children: [
                  Icon(Icons.tune, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Model Settings',
                    style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Chat System Prompt:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      maxLines: 3,
                      controller: TextEditingController(text: tempChatPrompt),
                      onChanged: (val) => setDialogState(() => tempChatPrompt = val),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter chat system prompt...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Vision System Prompt:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      maxLines: 3,
                      controller: TextEditingController(text: tempVisionPrompt),
                      onChanged: (val) => setDialogState(() => tempVisionPrompt = val),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter vision system prompt...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Context Size: $tempContext'),
                    Slider(
                      value: tempContext.toDouble(),
                      min: 256, max: 4096, divisions: 15,
                      label: '$tempContext',
                      onChanged: (v) => setDialogState(() => tempContext = v.toInt()),
                    ),
                    Text('Threads: $tempThreads'),
                    Slider(
                      value: tempThreads.toDouble(),
                      min: 1, max: 8, divisions: 7,
                      label: '$tempThreads',
                      onChanged: (v) => setDialogState(() => tempThreads = v.toInt()),
                    ),
                    Text('GPU Layers: $tempGpu'),
                    Slider(
                      value: tempGpu.toDouble(),
                      min: 0, max: 32, divisions: 32,
                      label: '$tempGpu',
                      onChanged: (v) => setDialogState(() => tempGpu = v.toInt()),
                    ),
                    Text('Max Tokens: $tempMaxTokens'),
                    Slider(
                      value: tempMaxTokens.toDouble(),
                      min: 128, max: 2048, divisions: 15,
                      label: '$tempMaxTokens',
                      onChanged: (v) => setDialogState(() => tempMaxTokens = v.toInt()),
                    ),
                    Text('Temperature: ${tempTemp.toStringAsFixed(2)}'),
                    Slider(
                      value: tempTemp,
                      min: 0.0, max: 1.5, divisions: 30,
                      label: tempTemp.toStringAsFixed(2),
                      onChanged: (v) => setDialogState(() => tempTemp = v),
                    ),
                    Text('Top P: ${tempTopP.toStringAsFixed(2)}'),
                    Slider(
                      value: tempTopP,
                      min: 0.1, max: 1.0, divisions: 18,
                      label: tempTopP.toStringAsFixed(2),
                      onChanged: (v) => setDialogState(() => tempTopP = v),
                    ),
                    Text('Top K: $tempTopK'),
                    Slider(
                      value: tempTopK.toDouble(),
                      min: 1, max: 100, divisions: 99,
                      label: '$tempTopK',
                      onChanged: (v) => setDialogState(() => tempTopK = v.toInt()),
                    ),
                    Text('Repeat Penalty: ${tempRepeatPenalty.toStringAsFixed(2)}'),
                    Slider(
                      value: tempRepeatPenalty,
                      min: 0.5, max: 2.0, divisions: 30,
                      label: tempRepeatPenalty.toStringAsFixed(2),
                      onChanged: (v) => setDialogState(() => tempRepeatPenalty = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _chatSystemPrompt = tempChatPrompt;
                      _visionSystemPrompt = tempVisionPrompt;
                      _contextSize = tempContext;
                      _threads = tempThreads;
                      _gpuLayers = tempGpu;
                      _temperature = tempTemp;
                      _topP = tempTopP;
                      _topK = tempTopK;
                      _repeatPenalty = tempRepeatPenalty;
                      _maxTokens = tempMaxTokens;
                    });
                    Navigator.pop(context);
                    _loadModel(); // Reload with new settings
                  },
                  child: const Text('Apply & Reload Model'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: _isDarkMode ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[600],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_hospital, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'MediBot',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showSettingsDialog,
            tooltip: 'Model Settings',
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clearChat,
            tooltip: 'Clear Chat',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isModelLoading) _buildLoadingIndicator(),
            if (!_isModelReady && !_isModelLoading) _buildErrorState(),
            if (_isModelReady) Expanded(child: _buildMessageList()),
            if (_isGenerating) _buildStopGenerationBar(),
            if (_isModelReady) _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildStopGenerationBar() {
    return InkWell(
      onTap: _stopGeneration,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.red[600],
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text(
              'Generating... (Tap to Stop)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: _loadingProgress,
                  color: Colors.blue[600],
                  backgroundColor: Colors.grey[300],
                  strokeWidth: 8,
                ),
              ),
              if (_loadingProgress != null)
                Column(
                  children: [
                    Text(
                      '${(_loadingProgress! * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[600],
                      ),
                    ),
                    Icon(Icons.smart_toy, color: Colors.blue[600], size: 24),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Loading MediBot Model',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: _isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _loadingMessage,
            style: TextStyle(
              fontSize: 14,
              color: _isDarkMode ? Colors.white70 : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_loadingProgress != null)
            LinearProgressIndicator(
              value: _loadingProgress,
              color: Colors.blue[600],
              backgroundColor: Colors.grey[300],
              minHeight: 6,
            ),
          const SizedBox(height: 16),
          Text(
            'Context: $_contextSize | Threads: $_threads | GPU: $_gpuLayers',
            style: TextStyle(
              color: _isDarkMode ? Colors.white54 : Colors.grey,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[600]),
          const SizedBox(height: 16),
          Text(
            'Failed to Load AI Model',
            style: TextStyle(
              color: _isDarkMode ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your model file and try again',
            style: TextStyle(
              color: _isDarkMode ? Colors.white70 : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
                onPressed: _loadModel,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back, color: Colors.grey[600]),
                label: Text('Go Back', style: TextStyle(color: Colors.grey[600])),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return Container(
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.black : Colors.grey[50],
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return _buildMessageBubble(message);
        },
      ),
    );
  }

  Widget _buildMessageBubble(AppChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) _buildAvatar(false),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: message.isUser
                    ? LinearGradient(colors: [Colors.blue[600]!, Colors.blue[500]!])
                    : null,
                color: message.isUser
                    ? null
                    : message.messageType == MessageType.system
                    ? (_isDarkMode ? Colors.grey[800] : Colors.blue[50])
                    : (_isDarkMode ? Colors.grey[800] : Colors.white),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.image != null) _buildImagePreview(message.image!),
                  if (message.isLoading)
                    Text(
                      'Thinking...',
                      style: TextStyle(
                        color: _isDarkMode ? Colors.white70 : Colors.grey[600],
                        fontStyle: FontStyle.italic,
                        fontSize: 16,
                      ),
                    )
                  else
                    SelectionArea(
                      child: GptMarkdown(
                        message.text.isEmpty ? 'Generating response...' : message.text,
                        style: TextStyle(
                          color: message.isUser
                              ? Colors.white
                              : (_isDarkMode ? Colors.white : Colors.black87),
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (!message.isUser && message.messageType != MessageType.system && !message.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionButton(
                            icon: Icons.copy,
                            onTap: () => _copyMessage(message.text),
                            tooltip: 'Copy message',
                          ),
                          const SizedBox(width: 8),
                          _buildActionButton(
                            icon: _ttsState == TtsState.playing && _currentSpeakingText == message.text
                                ? Icons.stop
                                : Icons.volume_up,
                            onTap: () => _speak(message.text),
                            tooltip: _ttsState == TtsState.playing && _currentSpeakingText == message.text
                                ? 'Stop reading'
                                : 'Read aloud',
                            isPlaying: _ttsState == TtsState.playing && _currentSpeakingText == message.text,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 10,
                              color: _isDarkMode ? Colors.white54 : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (message.isUser) _buildAvatar(true),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool isPlaying = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isPlaying
                ? Colors.red[600]?.withOpacity(0.1)
                : Colors.blue[600]?.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isPlaying ? Colors.red[600] : Colors.blue[600],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isUser
              ? [Colors.blue[600]!, Colors.blue[500]!]
              : [Colors.grey[400]!, Colors.grey[300]!],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.transparent,
        child: Icon(
          isUser ? Icons.person : Icons.local_hospital,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildImagePreview(File image) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          image,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.grey[900] : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, -4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          if (_selectedImage != null) _buildSelectedImagePreview(),
          Row(
            children: [
              _buildInputButton(
                icon: Icons.image,
                onPressed: _showImagePickerDialog,
                tooltip: 'Add image',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  child: TextField(
                    controller: _textController,
                    style: TextStyle(
                      color: _isDarkMode ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask MediBot for health advice...',
                      hintStyle: TextStyle(color: _isDarkMode ? Colors.white54 : Colors.grey[600]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (text) => _sendMessage(text, image: _selectedImage),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _micAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isListening ? _micAnimation.value : 1.0,
                    child: _buildInputButton(
                      icon: _isListening ? Icons.mic : Icons.mic_none,
                      onPressed: _speechEnabled
                          ? (_isListening ? _stopListening : _startListening)
                          : null,
                      tooltip: _isListening ? 'Stop listening' : 'Voice input',
                      color: _isListening ? Colors.red : Colors.blue[600],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _buildInputButton(
                icon: _isGenerating ? Icons.stop : Icons.send,
                onPressed: _isGenerating
                    ? _stopGeneration
                    : () => _sendMessage(_textController.text, image: _selectedImage),
                tooltip: _isGenerating ? 'Stop generation' : 'Send message',
                color: _isGenerating ? Colors.red : Colors.blue[600],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputButton({
    IconData? icon,
    VoidCallback? onPressed,
    String? tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        decoration: BoxDecoration(
          color: (color ?? Colors.blue[600])?.withOpacity(onPressed == null ? 0.3 : 1.0),
          shape: BoxShape.circle,
          boxShadow: onPressed != null
              ? [
            BoxShadow(
              color: (color ?? Colors.blue[600])!.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSelectedImagePreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _selectedImage!,
              height: 120,
              width: 120,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () {
                if (mounted) {
                  setState(() => _selectedImage = null);
                }
              },
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speechToText.stop();
    _flutterTts.stop();
    _micAnimationController.dispose();
    _typingAnimationController.dispose();
    _cleanupIsolate();
    super.dispose();
  }
}

// UI-only message class (separate from cactus ChatMessage)
class AppChatMessage {
  final int id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  final File? image;
  MessageType messageType;
  bool isLoading;

  AppChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.image,
    this.messageType = MessageType.chat,
    this.isLoading = false,
  });
}

enum MessageType { chat, system, error }

class IsolateParams {
  final String modelPath;
  final SendPort sendPort;
  final int contextSize;
  final int threads;
  final int gpuLayers;
  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
  final int maxTokens;

  IsolateParams({
    required this.modelPath,
    required this.sendPort,
    required this.contextSize,
    required this.threads,
    required this.gpuLayers,
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.repeatPenalty,
    required this.maxTokens,
  });
}
