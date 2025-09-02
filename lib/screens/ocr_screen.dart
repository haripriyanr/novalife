import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ Now used for clipboard
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

class OCRScreen extends StatefulWidget {
  const OCRScreen({super.key});

  @override
  State<OCRScreen> createState() => _OCRScreenState();
}

class _OCRScreenState extends State<OCRScreen> {
  final ImagePicker _picker = ImagePicker(); // ✅ Now used
  final TextRecognizer _textRecognizer = TextRecognizer();

  File? _image; // ✅ Now used
  String _recognizedText = ''; // ✅ Now used
  bool _isProcessing = false; // ✅ Now used

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // ✅ Scan image for text
  Future<void> _scanImage(XFile imageFile) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      setState(() {
        _recognizedText = recognizedText.text;
        _image = File(imageFile.path);
      });

      if (_recognizedText.isNotEmpty) {
        _showSuccessMessage('Text extracted successfully!');
      } else {
        _showMessage('No text found in the image', isError: true);
      }
    } catch (e) {
      _showMessage('Error processing image: $e', isError: true);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ✅ Take photo with camera
  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (photo != null) {
        await _scanImage(photo);
      }
    } catch (e) {
      _showMessage('Error accessing camera: $e', isError: true);
    }
  }

  // ✅ Pick image from gallery
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image != null) {
        await _scanImage(image);
      }
    } catch (e) {
      _showMessage('Error accessing gallery: $e', isError: true);
    }
  }

  // ✅ Copy text to clipboard (uses flutter/services.dart)
  Future<void> _copyToClipboard() async {
    if (_recognizedText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _recognizedText));
      _showSuccessMessage('Text copied to clipboard!');
    }
  }

  // ✅ Clear current scan
  void _clearScan() {
    setState(() {
      _image = null;
      _recognizedText = '';
    });
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea( // ✅ Removed unnecessary Container
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Text(
                'OCR Text Scanner',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Extract text from images using AI',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),

              // Main Content Area
              Expanded(
                child: _buildMainContent(isDark),
              ),

              // Action Buttons
              _buildActionButtons(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Processing image...',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    if (_image == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              'No image selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Take a photo or select from gallery to extract text',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Image preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _image!,
              fit: BoxFit.cover,
              height: 200,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 24),

          // Extracted text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.text_fields, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Extracted Text',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    if (_recognizedText.isNotEmpty)
                      IconButton(
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy to clipboard',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _recognizedText.isNotEmpty
                      ? _recognizedText
                      : 'No text detected in image',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: _recognizedText.isNotEmpty
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? Colors.grey[500] : Colors.grey[500]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Column(
      children: [
        if (_image != null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _clearScan,
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
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
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
