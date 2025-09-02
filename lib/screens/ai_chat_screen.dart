import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart'; // ✅ Add UUID import
import 'dart:io';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/voice_service.dart';
import '../services/ocr_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/voice_button.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final AIService _aiService = AIService();
  final VoiceService _voiceService = VoiceService();
  final OCRService _ocrService = OCRService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final Uuid _uuid = const Uuid(); // ✅ Add UUID generator

  bool _isInitialized = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeServicesQuietly();
  }

  Future<void> _initializeServicesQuietly() async {
    try {
      await _voiceService.initialize();
      await OCRService.initialize();
      await _aiService.initializeQuietly();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        if (_aiService.isModelLoaded) {
          _addMessage(ChatMessage(
            id: _uuid.v4(), // ✅ Use UUID
            content: "Hello! I'm your AI medical assistant powered by MedGemma 4B. I can help with medical questions, analyze images with OCR, or listen to your voice.\n\n${_aiService.getModelInfo()}",
            role: MessageRole.assistant,
            timestamp: DateTime.now(),
          ));
        } else {
          _showModelSetupPrompt();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        _addMessage(ChatMessage(
          id: _uuid.v4(), // ✅ Use UUID
          content: "⚠️ AI initialization failed: $e\n\nPlease try restarting the app or check your device storage.",
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  void _showModelSetupPrompt() {
    _addMessage(ChatMessage(
      id: _uuid.v4(), // ✅ Use UUID
      content: "🤖 AI Model Setup Required\n\nTo use the AI assistant, I need to download the MedGemma 4B model (~2.4 GB). This will be saved to your Downloads folder for easy access.\n\nTap the button below to begin setup.",
      role: MessageRole.system,
      timestamp: DateTime.now(),
      showSetupButton: true,
      onSetupPressed: () => _showModelDialog(),
    ));
  }

  Future<void> _showModelDialog() async {
    if (!mounted) return;

    await _aiService.showModelDialog(context);

    // ✅ Check if model is actually loaded and show proper message
    if (mounted) {
      if (_aiService.isModelLoaded) {
        // ✅ Remove the old setup prompt and add success message
        setState(() {
          // Remove any system messages about setup
          _messages.removeWhere((msg) =>
          msg.role == MessageRole.system &&
              msg.content.contains('AI Model Setup Required'));
        });

        _addMessage(ChatMessage(
          id: _uuid.v4(),
          content: "✅ **Model loaded successfully!**\n\nI'm ready to help with your medical questions. You can:\n• Ask me medical questions\n• Use voice input with the microphone\n• Analyze images with OCR\n\nHow can I assist you today?",
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        ));
      } else {
        // Model still not loaded, show error
        _addMessage(ChatMessage(
          id: _uuid.v4(),
          content: "❌ **Model loading failed**\n\nThere was an issue loading the AI model. Please try again or check your model file.",
          role: MessageRole.system,
          timestamp: DateTime.now(),
          showSetupButton: true,
          onSetupPressed: () => _showModelDialog(),
        ));
      }
    }
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
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

  // ✅ Enhanced message operations with UUIDs
  void _deleteMessage(String messageId) {
    setState(() {
      _messages.removeWhere((msg) => msg.id == messageId);
    });
  }

  void _regenerateResponse(String messageId) async {
    final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
    if (messageIndex == -1 || messageIndex == 0) return;

    final userMessage = _messages[messageIndex - 1];
    if (userMessage.role != MessageRole.user) return;

    setState(() {
      _messages.removeAt(messageIndex);
    });

    await _sendTextMessage(userMessage.content);
  }

  Future<void> _sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (!_aiService.isModelLoaded) {
      _addMessage(ChatMessage(
        id: _uuid.v4(), // ✅ Use UUID
        content: "Please set up the AI model first by tapping the setup button above.",
        role: MessageRole.system,
        timestamp: DateTime.now(),
      ));
      return;
    }

    // ✅ Create user message with unique ID
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      content: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );
    _addMessage(userMessage);

    // ✅ Create loading message with unique ID
    final loadingMessageId = _uuid.v4();
    final loadingMessage = ChatMessage(
      id: loadingMessageId,
      content: "",
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isLoading: true,
    );
    _addMessage(loadingMessage);

    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await _aiService.generateMedicalResponse(text);

      setState(() {
        _messages.removeWhere((msg) => msg.id == loadingMessageId); // ✅ Remove by ID
        _isProcessing = false;
      });

      _addMessage(ChatMessage(
        id: _uuid.v4(), // ✅ Use UUID
        content: response,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      setState(() {
        _messages.removeWhere((msg) => msg.id == loadingMessageId); // ✅ Remove by ID
        _isProcessing = false;
      });

      _addMessage(ChatMessage(
        id: _uuid.v4(), // ✅ Use UUID
        content: "I apologize, but I'm having trouble processing your request right now. Please try again or check if the model is properly loaded.",
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      ));
    }

    _textController.clear();
  }

  Future<void> _handleVoiceInput() async {
    if (!_voiceService.isAvailable) {
      _showSnackBar("Voice input is not available on this device", Colors.orange);
      return;
    }

    try {
      final voiceText = await _voiceService.startListening();
      if (voiceText != null && voiceText.isNotEmpty) {
        _textController.text = voiceText;
        await _sendTextMessage(voiceText);
      }
    } catch (e) {
      _showSnackBar("Voice input failed: $e", Colors.red);
    }
  }

  Future<void> _handleImageOCR() async {
    try {
      final ImagePicker picker = ImagePicker();

      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? image = await picker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _isProcessing = true;
      });

      _addMessage(ChatMessage(
        id: _uuid.v4(), // ✅ Use UUID
        content: "📷 Analyzing image...",
        role: MessageRole.user,
        timestamp: DateTime.now(),
        imagePath: image.path,
      ));

      final ocrText = await _ocrService.extractText(File(image.path));

      setState(() {
        _isProcessing = false;
      });

      if (ocrText.isNotEmpty) {
        _addMessage(ChatMessage(
          id: _uuid.v4(), // ✅ Use UUID
          content: "📝 **Text extracted from image:**\n\n$ocrText",
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        ));

        if (_aiService.isModelLoaded) {
          await _sendTextMessage("Please analyze this medical text: $ocrText");
        }
      } else {
        _addMessage(ChatMessage(
          id: _uuid.v4(), // ✅ Use UUID
          content: "No text found in the image. Please try with a clearer image containing text.",
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showSnackBar("Image processing failed: $e", Colors.red);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Medical Assistant'),
        elevation: 0,
        // ✅ Add back button to navigate to home
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back to home screen (assuming it's the first tab)
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          ListenableBuilder(
            listenable: _aiService,
            builder: (context, _) {
              Widget statusWidget;
              String tooltip;

              if (_aiService.isDownloading) {
                statusWidget = Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _aiService.downloadProgress,
                        ),
                      ),
                      Text(
                        '${(_aiService.downloadProgress * 100).toInt()}',
                        style: const TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                );
                tooltip = 'Downloading model: ${(_aiService.downloadProgress * 100).toStringAsFixed(1)}%';
              } else if (!_aiService.isModelLoaded && _isInitialized) {
                statusWidget = const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange),
                );
                tooltip = 'AI model not loaded';
              } else if (_aiService.isModelLoaded) {
                statusWidget = const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(Icons.check_circle, color: Colors.green),
                );
                tooltip = 'AI model ready';
              } else {
                statusWidget = const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
                tooltip = 'Initializing...';
              }

              return Tooltip(
                message: tooltip,
                child: statusWidget,
              );
            },
          ),
          IconButton(
            onPressed: () => _showInfoDialog(),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Model Information',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isInitialized
                ? Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return MessageBubble(
                    message: _messages[index],
                    onSpeak: (text) => _voiceService.speak(text),
                    onDelete: _messages[index].role != MessageRole.system ? _deleteMessage : null, // ✅ Add delete
                    onRegenerate: _messages[index].role == MessageRole.assistant ? _regenerateResponse : null, // ✅ Add regenerate
                  );
                },
              ),
            )
                : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing AI Assistant...'),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withAlpha(77),
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  VoiceButton(
                    onPressed: _handleVoiceInput,
                    isListening: _voiceService.isListening,
                    isEnabled: _voiceService.isAvailable && !_isProcessing,
                  ),
                  const SizedBox(width: 8),

                  IconButton(
                    onPressed: _isProcessing ? null : _handleImageOCR,
                    icon: const Icon(Icons.camera_alt),
                    tooltip: 'Analyze Image Text',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything about health...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          onPressed: _isProcessing || _textController.text.trim().isEmpty
                              ? null
                              : () => _sendTextMessage(_textController.text),
                          icon: Icon(
                            Icons.send_rounded,
                            color: _isProcessing || _textController.text.trim().isEmpty
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _isProcessing ? null : _sendTextMessage,
                      onChanged: (text) {
                        setState(() {});
                      },
                      enabled: !_isProcessing,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Model Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_aiService.getModelInfo()),
              const SizedBox(height: 16),
              if (!_aiService.isModelLoaded) ...[
                const Text(
                  'Features available without model:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• Voice input\n• Image text extraction (OCR)\n• Basic chat interface'),
                const SizedBox(height: 12),
                const Text(
                  'Features requiring model:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• AI medical responses\n• Text analysis\n• Medical Q&A'),
              ] else ...[
                const Text(
                  'Available features:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• AI medical responses\n• Voice input\n• Image text extraction\n• Medical analysis\n• Voice output'),
              ],
            ],
          ),
        ),
        actions: [
          if (!_aiService.isModelLoaded)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showModelDialog();
              },
              child: const Text('Setup Model'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _aiService.dispose();
    _voiceService.dispose();
    OCRService.dispose();
    super.dispose();
  }
}
