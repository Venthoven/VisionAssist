import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/tts_service.dart';
import '../services/database_helper.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final ImagePicker _picker = ImagePicker();

  bool _cameraReady = false;
  bool _isScanning = false;
  bool _isSpeaking = false;
  String _recognizedText = '';
  String _statusText = 'Arahkan kamera ke teks, lalu tekan Pindai';

  @override
  void initState() {
    super.initState();
    _requestPermissionAndInit();
  }

  Future<void> _requestPermissionAndInit() async {
    final camStatus = await Permission.camera.request();
    if (camStatus.isGranted) await _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _cameraController = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() => _cameraReady = true);
  }

  Future<void> _scanFromCamera() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    setState(() {
      _isScanning = true;
      _statusText = 'Memindai teks...';
    });

    try {
      final XFile photo = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(photo.path);
      final RecognizedText result = await _textRecognizer.processImage(inputImage);

      setState(() {
        _recognizedText = result.text.trim();
        _statusText = _recognizedText.isNotEmpty
            ? 'Teks berhasil dikenali (${result.text.length} karakter)'
            : 'Tidak ada teks yang ditemukan';
        _isScanning = false;
      });

      if (_recognizedText.isNotEmpty) {
        await DatabaseHelper.instance.insertHistory(
          type: 'OCR',
          result: _recognizedText,
          imagePath: photo.path,
        );
      }
    } catch (e) {
      setState(() {
        _statusText = 'Gagal memindai: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _scanFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isScanning = true;
      _statusText = 'Memindai teks dari gambar...';
    });

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText result = await _textRecognizer.processImage(inputImage);

      setState(() {
        _recognizedText = result.text.trim();
        _statusText = _recognizedText.isNotEmpty
            ? 'Teks berhasil dikenali (${result.text.length} karakter)'
            : 'Tidak ada teks yang ditemukan';
        _isScanning = false;
      });

      if (_recognizedText.isNotEmpty) {
        await DatabaseHelper.instance.insertHistory(
          type: 'OCR',
          result: _recognizedText,
          imagePath: image.path,
        );
      }
    } catch (e) {
      setState(() {
        _statusText = 'Gagal memindai: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _speakText() async {
    if (_recognizedText.isEmpty) return;
    setState(() => _isSpeaking = true);
    await TtsService.instance.speak(_recognizedText);
    setState(() => _isSpeaking = false);
  }

  Future<void> _stopSpeaking() async {
    await TtsService.instance.stop();
    setState(() => _isSpeaking = false);
  }

  void _copyText() {
    if (_recognizedText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _recognizedText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teks disalin ke clipboard'),
        backgroundColor: Color(0xFF1B4D3E),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearText() {
    setState(() {
      _recognizedText = '';
      _statusText = 'Arahkan kamera ke teks, lalu tekan Pindai';
    });
    TtsService.instance.stop();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: const [
                  Text(
                    'Pindai Teks (OCR)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Camera Preview
            Container(
              height: 240,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _cameraReady && _cameraController != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        if (_isScanning)
                          Container(
                            color: Colors.black45,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF2196F3)),
                                  SizedBox(height: 12),
                                  Text('Memindai...', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        // Scan line guide
                        Center(
                          child: Container(
                            margin: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Color(0xFF2196F3)),
                    ),
            ),

            const SizedBox(height: 12),

            // Action Buttons Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Pindai Kamera',
                      color: const Color(0xFF2196F3),
                      bgColor: const Color(0xFF0D2137),
                      onTap: _isScanning ? null : _scanFromCamera,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Dari Galeri',
                      color: const Color(0xFF9C27B0),
                      bgColor: const Color(0xFF1A0D21),
                      onTap: _isScanning ? null : _scanFromGallery,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Status bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF666666)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Result Text Box
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Row(
                        children: [
                          const Text(
                            'HASIL TEKS',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF666666),
                              letterSpacing: 1,
                            ),
                          ),
                          const Spacer(),
                          if (_recognizedText.isNotEmpty)
                            Text(
                              '${_recognizedText.length} karakter',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF666666)),
                            ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF2A2A2A), height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _recognizedText.isEmpty
                              ? 'Teks hasil OCR akan muncul di sini...'
                              : _recognizedText,
                          style: TextStyle(
                            color: _recognizedText.isEmpty
                                ? const Color(0xFF444444)
                                : Colors.white,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Bottom Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _recognizedText.isNotEmpty
                            ? (_isSpeaking ? _stopSpeaking : _speakText)
                            : null,
                        icon: Icon(_isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded, size: 18),
                        label: Text(_isSpeaking ? 'Hentikan' : 'Putar Suara'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSpeaking
                              ? const Color(0xFF8B1A1A)
                              : const Color(0xFF1B4D3E),
                          foregroundColor: const Color(0xFF7ED9B8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IconActionButton(
                    icon: Icons.copy_rounded,
                    onTap: _copyText,
                    tooltip: 'Salin',
                  ),
                  const SizedBox(width: 8),
                  _IconActionButton(
                    icon: Icons.delete_outline_rounded,
                    onTap: _clearText,
                    tooltip: 'Hapus',
                    color: const Color(0xFF8B1A1A),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color color;

  const _IconActionButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color = const Color(0xFF2A2A2A),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Icon(icon, color: Colors.white54, size: 20),
        ),
      ),
    );
  }
}
