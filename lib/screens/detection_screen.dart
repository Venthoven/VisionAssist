import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../services/tts_service.dart';
import '../services/database_helper.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Interpreter? _interpreter;
  List<String> _labels = [];

  bool _cameraReady = false;
  bool _modelLoaded = false;
  bool _isDetecting = false;
  bool _isRunning = false;

  List<DetectionResult> _detections = [];
  String _statusText = 'Memuat model...';

  DateTime _lastSpokenTime = DateTime(2000);
  String _lastSpokenText = '';
  static const _ttsInterval = Duration(seconds: 3);

  // Input size model YOLOv8n
  static const int _inputSize = 320;
  // Confidence threshold
  static const double _confThreshold = 0.30;
  // IoU threshold untuk NMS
  static const double _iouThreshold = 0.45;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  Future<void> _initAll() async {
    await _loadLabels();
    await _loadModel();
    await _requestPermissionAndInitCamera();
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted && _cameraReady && _modelLoaded) {
      _startDetection();
    }
  }

  Future<void> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString('assets/coco_labels.txt');
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      debugPrint('Labels dimuat: ${_labels.length} label');
    } catch (e) {
      debugPrint('Gagal memuat label: $e');
    }
  }

  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/yolov8n.tflite',
        options: options,
      );

      // Debug: cek shape input & output
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('Input shape: $inputShape');
      debugPrint('Output shape: $outputShape');

      if (mounted) setState(() => _modelLoaded = true);
    } catch (e) {
      debugPrint('Gagal memuat model: $e');
      if (mounted) setState(() => _statusText = 'Gagal memuat model: $e');
    }
  }

  Future<void> _requestPermissionAndInitCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _statusText = 'Izin kamera diperlukan');
      return;
    }
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() => _cameraReady = true);
  }

  void _startDetection() {
    if (!_cameraReady || !_modelLoaded || _isRunning) return;
    setState(() {
      _isRunning = true;
      _statusText = 'Mendeteksi objek...';
    });
    TtsService.instance.speak('Deteksi objek dimulai', saveToHistory: false);

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting || _interpreter == null) return;
      _isDetecting = true;
      try {
        final results = await _runInference(image);
        if (!mounted) return;
        if (results.isNotEmpty) {
          final labels = results.map((r) => r.label).toSet().toList();
          final resultText = labels.join(', ');
          setState(() {
            _detections = results;
            _statusText = 'Terdeteksi: $resultText';
          });
          _autoSpeak(resultText);
        } else {
          setState(() {
            _detections = [];
            _statusText = 'Tidak ada objek terdeteksi';
          });
        }
      } catch (e) {
        debugPrint('Error deteksi: $e');
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<List<DetectionResult>> _runInference(CameraImage image) async {
    // 1. Convert YUV420 → RGB Image
    final imgLib = _yuv420ToRgb(image);
    if (imgLib == null) return [];

    // 2. Rotate 90° (kamera Android portrait)
    final rotated = img.copyRotate(imgLib, angle: 90);

    // 3. Resize ke 320x320
    final resized = img.copyResize(
      rotated,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // 4. Normalisasi ke [0.0, 1.0] → shape [1, 320, 320, 3]
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );

    // 5. Siapkan output buffer
    // YOLOv8 output shape: [1, 84, 8400]
    // 84 = 4 koordinat box + 80 class scores
    // 8400 = jumlah anchor
    final outputTensor = _interpreter!.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    debugPrint('Output shape runtime: $outputShape');

    // Buat output sesuai shape
    final int dim1 = outputShape[1]; // 84
    final int dim2 = outputShape[2]; // 8400

    final output = [
      List.generate(dim1, (_) => List.filled(dim2, 0.0))
    ];

    // 6. Jalankan inferensi
    _interpreter!.run(input, output);

    // 7. Parse output YOLOv8
    // Format: output[0][0..3][i] = cx, cy, w, h
    //         output[0][4..83][i] = class scores
    final results = <DetectionResult>[];
    final numClasses = dim1 - 4;

    for (int i = 0; i < dim2; i++) {
      // Cari class dengan score tertinggi
      double maxScore = 0.0;
      int maxClass = 0;
      for (int c = 0; c < numClasses; c++) {
        final score = output[0][4 + c][i];
        if (score > maxScore) {
          maxScore = score;
          maxClass = c;
        }
      }

      // Filter berdasarkan threshold
      if (maxScore < _confThreshold) continue;

      // Koordinat box (cx, cy, w, h) dalam skala 0-320
      // Normalisasi ke 0.0-1.0
      final cx = output[0][0][i] / _inputSize;
      final cy = output[0][1][i] / _inputSize;
      final w  = output[0][2][i] / _inputSize;
      final h  = output[0][3][i] / _inputSize;

      // Convert dari center format ke left-top format
      final left   = (cx - w / 2).clamp(0.0, 1.0);
      final top    = (cy - h / 2).clamp(0.0, 1.0);
      final right  = (cx + w / 2).clamp(0.0, 1.0);
      final bottom = (cy + h / 2).clamp(0.0, 1.0);

      final label = (maxClass < _labels.length)
          ? _labels[maxClass]
          : 'Objek $maxClass';

      results.add(DetectionResult(
        label: label,
        confidence: maxScore,
        rect: Rect.fromLTRB(left, top, right, bottom),
      ));
    }

    // 8. NMS - hapus box yang terlalu overlap
    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    final filtered = _applyNMS(results);

    debugPrint('Deteksi: ${filtered.map((r) => '${r.label}(${(r.confidence*100).toStringAsFixed(0)}%)').join(', ')}');

    return filtered.take(6).toList();
  }

  // Convert YUV420 ke RGB
  img.Image? _yuv420ToRgb(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;
      final yBuffer = image.planes[0].bytes;
      final uBuffer = image.planes[1].bytes;
      final vBuffer = image.planes[2].bytes;
      final yRowStride = image.planes[0].bytesPerRow;
      final uvRowStride = image.planes[1].bytesPerRow;
      final uvPixelStride = image.planes[1].bytesPerPixel ?? 2;

      final result = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yRowStride + x;
          final uvIndex =
              (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          if (yIndex >= yBuffer.length ||
              uvIndex >= uBuffer.length ||
              uvIndex >= vBuffer.length) continue;

          final yVal = yBuffer[yIndex];
          final uVal = uBuffer[uvIndex];
          final vVal = vBuffer[uvIndex];

          // YUV ke RGB
          final r = (yVal + 1.13983 * (vVal - 128)).round().clamp(0, 255);
          final g = (yVal - 0.39465 * (uVal - 128) - 0.58060 * (vVal - 128))
              .round()
              .clamp(0, 255);
          final b = (yVal + 2.03211 * (uVal - 128)).round().clamp(0, 255);

          result.setPixelRgb(x, y, r, g, b);
        }
      }
      return result;
    } catch (e) {
      debugPrint('YUV convert error: $e');
      return null;
    }
  }

  // Non-Maximum Suppression
  List<DetectionResult> _applyNMS(List<DetectionResult> boxes) {
    final selected = <DetectionResult>[];
    final suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      selected.add(boxes[i]);
      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        if (_computeIoU(boxes[i].rect, boxes[j].rect) > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return selected;
  }

  double _computeIoU(Rect a, Rect b) {
    final intersect = a.intersect(b);
    if (intersect.isEmpty) return 0.0;
    final interArea = intersect.width * intersect.height;
    final unionArea = a.width * a.height + b.width * b.height - interArea;
    return unionArea <= 0 ? 0.0 : interArea / unionArea;
  }

  void _autoSpeak(String text) {
    final now = DateTime.now();
    if (text != _lastSpokenText &&
        now.difference(_lastSpokenTime) > _ttsInterval) {
      _lastSpokenText = text;
      _lastSpokenTime = now;
      TtsService.instance.speak('Terdeteksi: $text', saveToHistory: false);
    }
  }

  void _stopDetection() {
    _cameraController?.stopImageStream();
    TtsService.instance.stop();
    setState(() {
      _isRunning = false;
      _detections = [];
      _statusText = 'Deteksi dihentikan';
      _lastSpokenText = '';
    });
  }

  void _toggleDetection() {
    if (_isRunning) {
      _stopDetection();
    } else {
      _startDetection();
    }
  }

  Future<void> _saveResult() async {
  if (_detections.isEmpty) return;

  // Simpan ke detection_history dengan confidence asli dari model
  await DatabaseHelper.instance.insertDetection(
    detectedObject: _detections.map((d) => d.label).join(', '),
    confidenceScore: _detections.first.confidence, // ← bukan 0.0 lagi
  );

  // Speak tanpa simpan ke TTS history
  await TtsService.instance.speak(_statusText, saveToHistory: false);

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hasil disimpan ke riwayat'),
        backgroundColor: Color(0xFF1B4D3E),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

  Color _labelColor(int index) {
    const colors = [
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFFFF9800),
      Color(0xFFE91E63),
      Color(0xFF9C27B0),
      Color(0xFF00BCD4),
    ];
    return colors[index % colors.length];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopDetection();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera().then((_) {
        if (_modelLoaded) _startDetection();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDetection();
    _cameraController?.dispose();
    _interpreter?.close();
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
                children: [
                  const Text(
                    'Deteksi Objek',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isRunning
                          ? const Color(0xFF1B4D3E)
                          : _modelLoaded
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFF2A1A00),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRunning
                                ? const Color(0xFF4CAF50)
                                : _modelLoaded
                                    ? const Color(0xFF666666)
                                    : const Color(0xFFFF9800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isRunning ? 'LIVE' : _modelLoaded ? 'SIAP' : 'MEMUAT...',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isRunning
                                ? const Color(0xFF4CAF50)
                                : _modelLoaded
                                    ? const Color(0xFF888888)
                                    : const Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Camera View
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isRunning
                        ? const Color(0xFF4CAF50).withOpacity(0.4)
                        : const Color(0xFF2A2A2A),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _cameraReady && _cameraController != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_cameraController!),
                          if (_detections.isNotEmpty)
                            LayoutBuilder(
                              builder: (ctx, constraints) => CustomPaint(
                                painter: YoloPainter(
                                  detections: _detections,
                                  screenWidth: constraints.maxWidth,
                                  screenHeight: constraints.maxHeight,
                                  colorFn: _labelColor,
                                ),
                              ),
                            ),
                          if (_isRunning && _detections.isEmpty)
                            const _ScanLine(),
                          ..._buildCorners(),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined,
                                size: 48,
                                color: Colors.white.withOpacity(0.15)),
                            const SizedBox(height: 16),
                            Text(
                              !_modelLoaded ? 'Memuat model YOLO...' : 'Memuat kamera...',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            const SizedBox(
                              width: 28, height: 28,
                              child: CircularProgressIndicator(
                                  color: Color(0xFF4CAF50), strokeWidth: 2),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            // Label chips
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _detections.isNotEmpty ? 44 : 0,
              child: _detections.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _detections.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          final d = _detections[i];
                          final color = _labelColor(i);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: color.withOpacity(0.5)),
                            ),
                            child: Text(
                              '${d.label}  ${(d.confidence * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                      ),
                    )
                  : const SizedBox(),
            ),

            // Result Bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _detections.isNotEmpty
                          ? const Color(0xFF1B4D3E)
                          : const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _detections.isNotEmpty
                          ? Icons.check_circle_outline
                          : Icons.search,
                      color: _detections.isNotEmpty
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF666666),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HASIL DETEKSI',
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF666666),
                                letterSpacing: 1)),
                        const SizedBox(height: 3),
                        Text(_statusText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _saveResult,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B4D3E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.volume_up_rounded,
                          color: Color(0xFF7ED9B8), size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Tombol Start/Stop
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_cameraReady && _modelLoaded) ? _toggleDetection : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRunning
                        ? const Color(0xFF8B1A1A)
                        : const Color(0xFF1B4D3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFF1A1A1A),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRunning
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outlined,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        !_modelLoaded
                            ? 'Memuat Model YOLO...'
                            : _isRunning
                                ? 'Hentikan Deteksi'
                                : 'Mulai Deteksi',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCorners() => [
        const Positioned(top: 16, left: 16,
            child: _CornerGuide(corner: _Corner.topLeft)),
        const Positioned(top: 16, right: 16,
            child: _CornerGuide(corner: _Corner.topRight)),
        const Positioned(bottom: 16, left: 16,
            child: _CornerGuide(corner: _Corner.bottomLeft)),
        const Positioned(bottom: 16, right: 16,
            child: _CornerGuide(corner: _Corner.bottomRight)),
      ];
}

// Model data
class DetectionResult {
  final String label;
  final double confidence;
  final Rect rect;
  DetectionResult({required this.label, required this.confidence, required this.rect});
}

// YOLO Bounding Box Painter
class YoloPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final double screenWidth;
  final double screenHeight;
  final Color Function(int) colorFn;

  YoloPainter({
    required this.detections,
    required this.screenWidth,
    required this.screenHeight,
    required this.colorFn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      final color = colorFn(i);
      final rect = Rect.fromLTRB(
        d.rect.left * screenWidth,
        d.rect.top * screenHeight,
        d.rect.right * screenWidth,
        d.rect.bottom * screenHeight,
      );

      // Fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = color.withOpacity(0.10),
      );

      // Border
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Label
      final text = '${d.label}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(rect.left, rect.top - 24, tp.width + 16, 22),
            const Radius.circular(4)),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(rect.left + 8, rect.top - 22));
    }
  }

  @override
  bool shouldRepaint(YoloPainter old) => true;
}

// Scan Line
class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.05, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (ctx, _) => Positioned(
        top: MediaQuery.of(ctx).size.height * _anim.value,
        left: 0, right: 0,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              const Color(0xFF4CAF50).withOpacity(0.8),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    );
  }
}

// Corner Guides
enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerGuide extends StatelessWidget {
  final _Corner corner;
  const _CornerGuide({super.key, required this.corner});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 24, height: 24,
        child: CustomPaint(painter: _CornerPainter(corner: corner)),
      );
}

class _CornerPainter extends CustomPainter {
  final _Corner corner;
  _CornerPainter({required this.corner});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const len = 14.0;
    switch (corner) {
      case _Corner.topLeft:
        canvas.drawLine(Offset.zero, const Offset(len, 0), p);
        canvas.drawLine(Offset.zero, const Offset(0, len), p);
      case _Corner.topRight:
        canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), p);
        canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), p);
      case _Corner.bottomLeft:
        canvas.drawLine(Offset(0, size.height), Offset(len, size.height), p);
        canvas.drawLine(Offset(0, size.height), Offset(0, size.height - len), p);
      case _Corner.bottomRight:
        canvas.drawLine(Offset(size.width, size.height),
            Offset(size.width - len, size.height), p);
        canvas.drawLine(Offset(size.width, size.height),
            Offset(size.width, size.height - len), p);
    }
  }
  @override
  bool shouldRepaint(_CornerPainter old) => false;
}