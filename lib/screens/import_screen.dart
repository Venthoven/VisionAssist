import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/tts_service.dart';
import '../services/database_helper.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  bool _isProcessing = false;
  bool _isSpeaking = false;
  String _resultText = '';
  String _statusText = 'Pilih sumber file untuk diimpor';
  String? _importedImagePath;
  String _importedFileName = '';

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ImportBottomSheet(
        onImportFile: () {
          Navigator.pop(ctx);
          _pickFile();
        },
        onImportImage: () {
          Navigator.pop(ctx);
          _pickImage();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (image == null) return;
    _processImage(image.path, image.name);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'png', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    final ext = file.extension?.toLowerCase() ?? '';

    // File Word (.docx / .doc)
    if (ext == 'docx' || ext == 'doc') {
      setState(() {
        _isProcessing = true;
        _importedFileName = file.name;
        _importedImagePath = null;
        _statusText = 'Memproses file Word...';
        _resultText = '';
      });
      try {
        final bytes = await File(file.path!).readAsBytes();
        final text = docxToText(bytes);
        setState(() {
          _resultText = text.trim();
          _importedFileName = file.name;
          _statusText = _resultText.isNotEmpty
              ? 'Teks berhasil diekstrak (${_resultText.length} karakter)'
              : 'Tidak ada teks ditemukan dalam file';
          _isProcessing = false;
        });
        if (_resultText.isNotEmpty) {
          await DatabaseHelper.instance.insertOcr(extractedText: _resultText);
        }
      } catch (e) {
        setState(() {
          _statusText = 'Gagal membaca file Word';
          _isProcessing = false;
        });
      }
      return;
    }

    // File teks biasa (.txt)
    if (ext == 'txt') {
      final text = await File(file.path!).readAsString();
      setState(() {
        _resultText = text.trim();
        _importedFileName = file.name;
        _importedImagePath = null;
        _statusText = 'Teks berhasil diekstrak (${_resultText.length} karakter)';
        _isProcessing = false;
      });
      if (_resultText.isNotEmpty) {
        await DatabaseHelper.instance.insertOcr(extractedText: _resultText);
      }
      return;
    }

    // Gambar & PDF → ML Kit OCR
    if (['png', 'jpg', 'jpeg', 'pdf'].contains(ext)) {
      _processImage(file.path!, file.name);
      return;
    }

    setState(() {
      _statusText = 'Format file belum didukung: .$ext';
    });
  }

  Future<void> _processImage(String path, String name) async {
    setState(() {
      _isProcessing = true;
      _importedImagePath = path;
      _importedFileName = name;
      _statusText = 'Memproses file...';
      _resultText = '';
    });

    try {
      final inputImage = InputImage.fromFilePath(path);
      final RecognizedText result =
          await _textRecognizer.processImage(inputImage);

      setState(() {
        _resultText = result.text.trim();
        _statusText = _resultText.isNotEmpty
            ? 'Teks berhasil diekstrak (${_resultText.length} karakter)'
            : 'Tidak ada teks ditemukan dalam file';
        _isProcessing = false;
      });

      if (_resultText.isNotEmpty) {
        await DatabaseHelper.instance.insertOcr(extractedText: _resultText);
      }
    } catch (e) {
      setState(() {
        _statusText = 'Gagal memproses file';
        _isProcessing = false;
      });
    }
  }

  Future<void> _speakText() async {
    if (_resultText.isEmpty) return;
    setState(() => _isSpeaking = true);
    await TtsService.instance.speak(_resultText);
    setState(() => _isSpeaking = false);
  }

  Future<void> _stopSpeaking() async {
    await TtsService.instance.stop();
    setState(() => _isSpeaking = false);
  }

  void _clearResult() {
    setState(() {
      _resultText = '';
      _importedImagePath = null;
      _importedFileName = '';
      _statusText = 'Pilih sumber file untuk diimpor';
    });
    TtsService.instance.stop();
  }

  @override
  void dispose() {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('Impor File',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0D21),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF9C27B0).withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded,
                            color: Color(0xFF9C27B0), size: 12),
                        SizedBox(width: 5),
                        Text('IMPOR',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9C27B0),
                                letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Preview area
            Container(
              height: 200,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _importedImagePath != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_importedImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.insert_drive_file_rounded,
                                color: Color(0xFF9C27B0), size: 48),
                          ),
                        ),
                        Container(color: Colors.black38),
                        if (_isProcessing)
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFF9C27B0)),
                                SizedBox(height: 12),
                                Text('Mengekstrak teks...',
                                    style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.insert_drive_file_rounded,
                                    color: Color(0xFF9C27B0), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(_importedFileName,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _importedFileName.isNotEmpty
                      // Tampilan untuk file non-gambar (docx, txt, pdf)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isProcessing)
                                const CircularProgressIndicator(
                                    color: Color(0xFF9C27B0))
                              else
                                const Icon(Icons.insert_drive_file_rounded,
                                    color: Color(0xFF9C27B0), size: 48),
                              const SizedBox(height: 12),
                              Text(_importedFileName,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                              if (_isProcessing)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text('Mengekstrak teks...',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 11)),
                                ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: const Color(0xFF9C27B0)
                                        .withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.upload_file_rounded,
                                  color: Color(0xFF9C27B0), size: 32),
                            ),
                            const SizedBox(height: 12),
                            const Text('Belum ada file diimpor',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 14)),
                            const SizedBox(height: 6),
                            const Text(
                                'Ketuk tombol di bawah untuk memilih file',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 11)),
                          ],
                        ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _showImportOptions,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text('Pilih Sumber Impor',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0D21),
                    foregroundColor: const Color(0xFF9C27B0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: const Color(0xFF9C27B0).withOpacity(0.5)),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: Color(0xFF666666)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_statusText,
                          style: const TextStyle(
                              color: Color(0xFF999999), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

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
                          const Text('HASIL EKSTRAKSI TEKS',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF666666),
                                  letterSpacing: 1)),
                          const Spacer(),
                          if (_resultText.isNotEmpty)
                            Text('${_resultText.length} karakter',
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF666666))),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF2A2A2A), height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _resultText.isEmpty
                              ? 'Hasil ekstraksi teks dari file akan muncul di sini...'
                              : _resultText,
                          style: TextStyle(
                            color: _resultText.isEmpty
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

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _resultText.isNotEmpty
                            ? (_isSpeaking ? _stopSpeaking : _speakText)
                            : null,
                        icon: Icon(
                          _isSpeaking
                              ? Icons.stop_rounded
                              : Icons.volume_up_rounded,
                          size: 18,
                        ),
                        label: Text(_isSpeaking ? 'Hentikan' : 'Putar Suara'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSpeaking
                              ? const Color(0xFF8B1A1A)
                              : const Color(0xFF1B4D3E),
                          foregroundColor: _isSpeaking
                              ? Colors.white
                              : const Color(0xFF7ED9B8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _clearResult,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white54, size: 20),
                    ),
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

// ── Bottom Sheet Pilihan Impor ──
class _ImportBottomSheet extends StatelessWidget {
  final VoidCallback onImportFile;
  final VoidCallback onImportImage;
  final VoidCallback onCancel;

  const _ImportBottomSheet({
    required this.onImportFile,
    required this.onImportImage,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _SheetOption(
            icon: Icons.insert_drive_file_outlined,
            label: 'Impor File (PDF, TXT, Word)',
            onTap: onImportFile,
          ),
          const SizedBox(height: 10),
          _SheetOption(
            icon: Icons.image_outlined,
            label: 'Impor Gambar',
            onTap: onImportImage,
          ),
          const SizedBox(height: 10),
          _SheetOption(
            icon: Icons.close_rounded,
            label: 'Batal',
            onTap: onCancel,
            isCancel: true,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isCancel;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isCancel = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: isCancel ? const Color(0xFF1A1A1A) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCancel
                ? const Color(0xFF2A2A2A)
                : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isCancel ? Colors.white38 : Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                  color: isCancel ? Colors.white38 : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }
}