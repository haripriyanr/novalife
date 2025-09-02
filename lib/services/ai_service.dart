import 'dart:io';
import 'dart:async';
import 'package:cactus/cactus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'model_path_service.dart';
import 'external_storage_helper.dart';
import 'ai_settings_service.dart';
import '../widgets/enhanced_download_dialog.dart';

class AIService extends ChangeNotifier {
  static const String modelName = 'medgemma-4b-it-Q4_K_M.gguf';
  static const String huggingFaceUrl = 'https://huggingface.co/unsloth/medgemma-4b-it-GGUF/resolve/main/medgemma-4b-it-Q4_K_M.gguf';

  CactusLM? _cactusLM;
  bool _isModelLoaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _modelPath = '';
  String? _customModelPath;

  AIModelSettings _settings = AIModelSettings();

  bool get isModelLoaded => _isModelLoaded;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get currentModelPath => _customModelPath ?? _modelPath;
  AIModelSettings get settings => _settings;

  Future<void> initialize({BuildContext? context}) async {
    await _requestStoragePermissions();
    await _setupExternalModelPath();
    await _loadSettings();

    _customModelPath = await ModelPathService.loadModelPath();

    if (_customModelPath != null && File(_customModelPath!).existsSync()) {
      debugPrint('Using saved custom model: $_customModelPath');
      _modelPath = _customModelPath!;
      await _loadModel();
    } else if (await _checkModelExists()) {
      debugPrint('Using external storage model: $_modelPath');
      await _loadModel();
    } else if (context != null && context.mounted) {
      await _showEnhancedModelDialog(context);
    } else {
      throw Exception('Model not found and no context provided for dialog');
    }
  }

  Future<void> initializeQuietly() async {
    try {
      await Future.any([
        _initializeQuietlyInternal(),
        Future.delayed(const Duration(seconds: 15), () => throw TimeoutException('Initialization timeout', const Duration(seconds: 15))),
      ]);
    } catch (e) {
      debugPrint('Quiet initialization failed: $e');
    }
  }

  Future<void> _initializeQuietlyInternal() async {
    await _requestStoragePermissions();
    await _setupExternalModelPath();
    await _loadSettings();

    _customModelPath = await ModelPathService.loadModelPath();

    if (_customModelPath != null && File(_customModelPath!).existsSync()) {
      debugPrint('Using saved custom model: $_customModelPath');
      _modelPath = _customModelPath!;
      await _loadModel();
    } else if (await _checkModelExists()) {
      debugPrint('Using external storage model: $_modelPath');
      await _loadModel();
    }
  }

  Future<void> showModelDialog(BuildContext context) async {
    if (!context.mounted) return;
    await _showEnhancedModelDialog(context);
  }

  Future<void> _requestStoragePermissions() async {
    final hasPermissions = await ExternalStorageHelper.requestStoragePermissions();
    if (!hasPermissions) {
      debugPrint('Storage permissions not granted');
    }
  }

  Future<void> _setupExternalModelPath() async {
    try {
      _modelPath = await ExternalStorageHelper.getModelFilePath();
      debugPrint('Model will be saved to: $_modelPath');
    } catch (e) {
      debugPrint('Error setting up external model path: $e');
      throw Exception('Failed to setup external storage path: $e');
    }
  }

  Future<void> _loadSettings() async {
    _settings = await AISettingsService.loadSettings();
    notifyListeners();
  }

  Future<void> updateSettings(AIModelSettings newSettings) async {
    _settings = newSettings;
    await AISettingsService.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> _showEnhancedModelDialog(BuildContext context) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return EnhancedDownloadDialog(
          onModelPathSelected: (path) async {
            _customModelPath = path;
            _modelPath = path;

            try {
              await _loadModel();
              debugPrint('Model loaded successfully from: $path');

              notifyListeners();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('AI Model loaded and ready!'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Failed to load model: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to load model: $e'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
          onDownloadStarted: (progressCallback, speedCallback, totalBytesCallback, cancelToken) {
            debugPrint('Download started callback triggered');
            _downloadWithProgress(progressCallback, speedCallback, totalBytesCallback, cancelToken, dialogContext);
          },
        );
      },
    );
  }

  Future<bool> _checkModelExists() async {
    return File(_modelPath).existsSync();
  }

  Future<void> _downloadWithProgress(
      Function(double) progressCallback,
      Function(String) speedCallback,
      Function(int) totalBytesCallback,
      CancelToken cancelToken,
      BuildContext dialogContext,
      ) async {
    debugPrint('Starting download process...');

    _isDownloading = true;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(seconds: 30),
      ));

      int lastReceivedBytes = 0;
      int lastTime = DateTime.now().millisecondsSinceEpoch;

      debugPrint('Starting download to: $_modelPath');

      await dio.download(
        huggingFaceUrl,
        _modelPath,
        cancelToken: cancelToken,
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          debugPrint('Progress: $received / $total');

          if (total != -1 && total > 0) {
            totalBytesCallback(total);

            _downloadProgress = received / total;
            progressCallback(_downloadProgress);

            final now = DateTime.now().millisecondsSinceEpoch;
            final timeDiff = now - lastTime;

            if (timeDiff >= 1000 && received > lastReceivedBytes) {
              final bytesDiff = received - lastReceivedBytes;
              final bytesPerSecond = bytesDiff / (timeDiff / 1000);
              final mbPerSecond = bytesPerSecond / (1024 * 1024);

              speedCallback("${mbPerSecond.toStringAsFixed(2)} MB/s");

              lastReceivedBytes = received;
              lastTime = now;
            }

            notifyListeners();
          } else {
            totalBytesCallback(2500 * 1024 * 1024);
            speedCallback("Downloading...");
          }
        },
      );

      await ModelPathService.saveModelPath(_modelPath);
      _customModelPath = _modelPath;

      _isDownloading = false;
      notifyListeners();

      await _loadModel();

      if (dialogContext.mounted) {
        final storageLocation = await ExternalStorageHelper.getStorageLocationDescription();

        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Model downloaded successfully!'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saved to: $storageLocation',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

    } on DioException catch (e) {
      _isDownloading = false;
      notifyListeners();

      if (e.type == DioExceptionType.cancel) {
        debugPrint('Download cancelled by user');
      } else {
        debugPrint('Download error: ${e.message}');
        throw Exception('Failed to download model: ${e.message}');
      }
    } catch (e) {
      _isDownloading = false;
      notifyListeners();
      debugPrint('Unexpected download error: $e');
      throw Exception('Unexpected error during download: $e');
    }
  }

  // ✅ Fixed: Correct Cactus model loading without contextSize parameter
  Future<void> _loadModel() async {
    try {
      debugPrint('Loading model with Cactus from: $_modelPath');

      // ✅ Fixed: Use correct Cactus API without contextSize
      _cactusLM = CactusLM();
      await _cactusLM!.download(
        modelUrl: _modelPath, // Use local file path
        // ✅ Removed contextSize parameter - not supported in this API
      );

      await _cactusLM!.init();

      _isModelLoaded = true;
      notifyListeners();
      debugPrint('Cactus model loaded successfully!');
    } catch (e) {
      debugPrint('Failed to load Cactus model: $e');
      _isModelLoaded = false;
      notifyListeners();
      throw Exception('Failed to load model with Cactus: $e');
    }
  }

  Future<void> setModelPath(String path) async {
    _customModelPath = path;
    _modelPath = path;
    await ModelPathService.saveModelPath(path);
    notifyListeners();
  }

  Future<String> generateResponse(String prompt, {String? systemPrompt}) async {
    if (!_isModelLoaded || _cactusLM == null) {
      throw Exception('Model not loaded');
    }

    try {
      final messages = <ChatMessage>[];

      if (systemPrompt != null) {
        messages.add(ChatMessage(role: 'system', content: systemPrompt));
      }
      messages.add(ChatMessage(role: 'user', content: prompt));

      final completion = await _cactusLM!.completion(
        messages,
        maxTokens: _settings.maxTokens,
        temperature: _settings.temperature,
      );

      return completion.toString();
    } catch (e) {
      throw Exception('Failed to generate response: $e');
    }
  }

  Future<String> generateMedicalResponse(String query) async {
    const systemPrompt = '''You are MedGemma 4B, a helpful medical AI assistant. 
Provide accurate, evidence-based medical information. Always recommend consulting 
healthcare professionals for serious concerns. Be empathetic and clear.''';

    return await generateResponse(query, systemPrompt: systemPrompt);
  }

  String getModelInfo() {
    if (_customModelPath != null && File(_customModelPath!).existsSync()) {
      final file = File(_customModelPath!);
      final size = file.lengthSync();
      final fileName = _customModelPath!.split('/').last;

      String displayPath = _customModelPath!;
      if (displayPath.contains('/storage/emulated/0/')) {
        displayPath = displayPath.replaceFirst('/storage/emulated/0/', 'Internal Storage/');
      }
      if (displayPath.contains('/Download/')) {
        displayPath = displayPath.replaceFirst('/Download/', 'Downloads/');
      }

      return 'Model: MedGemma 4B ($fileName)\n'
          'Size: ${(size / (1024 * 1024)).toStringAsFixed(1)} MB\n'
          'Path: $displayPath\n'
          'Framework: Cactus AI\n'
          'Status: ${_isModelLoaded ? "Loaded ✅" : "Downloaded ⚠️"}';
    }

    return 'Model: Not found\n'
        'Framework: Cactus AI\n'
        'Status: Not Loaded ❌';
  }

  @override
  void dispose() {
    _cactusLM?.dispose();
    super.dispose();
  }
}
