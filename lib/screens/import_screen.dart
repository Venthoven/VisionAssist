import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/tts_service.dart';
import '../services/database_helper.dart';
import '../services/document_reader_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _isProcessing = false;
  bool _isSpeaking = false;
  String _resultText = '';
  String _statusText = 'Pilih sumber file untuk diimpor';
  String? _importedImagePath;
  String _importedFileName = '';
  DocumentType? _importedFileType;

  // Progress untuk dokumen panjang (PDF banyak halaman)
  int _progressCurrent = 0;
  int _progressTotal = 0;

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ImportBottomSheet(
        onImportFile: () {
          Navigator.pop(ctx);
          _pickFileFromManager();
        },
        onImportImage: () {
          Navigator.pop(ctx);
          _pickImage();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  /// Membuka file manager sungguhan (bukan galeri) sehingga pengguna bisa
  /// memilih file PDF, Word (.docx), atau gambar dari mana saja di
  /// penyimpanan perangkat — termasuk Download, Dokumen, Google Drive, dll.
  Future<void> _pickFileFromManager() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
    );

    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final name = result.files.single.name;
    _processDocument(path, name);
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (image == null) return;
    _processDocument(image.path, image.name);
  }

  /// Memproses dokumen apa pun (PDF, Word, atau gambar) dengan otomatis
  /// mendeteksi jenis filenya lalu memanggil pembaca yang sesuai.
  Future<void> _processDocument(String path, String name) async {
    final fileType = DocumentReaderService.detectType(path);

    if (fileType == DocumentType.unsupported) {
      setState(() {
        _statusText = 'Jenis file tidak didukung. Gunakan PDF, Word, atau gambar.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _importedImagePath = fileType == DocumentType.image ? path : null;
      _importedFileName = name;
      _importedFileType = fileType;
      _statusText = _statusLabelFor(fileType);
      _resultText = '';
      _progressCurrent = 0;
      _progressTotal = 0;
    });

    try {
      final result = await DocumentReaderService.readDocument(
        path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _progressCurrent = current;
            _progressTotal = total;
            _statusText = 'Memproses halaman $current dari $total...';
          });
        },
      );

      setState(() {
        _resultText = result.text;
        _statusText = _resultText.isNotEmpty
            ? 'Teks berhasil diekstrak (${_resultText.length} karakter${result.totalPages > 1 ? ', ${result.totalPages} halaman' : ''})'
            : 'Tidak ada teks ditemukan dalam file';
        _isProcessing = false;
      });

      if (_resultText.isNotEmpty) {
        await DatabaseHelper.instance.insertHistory(
          type: 'Impor File',
          result: _resultText,
          imagePath: fileType == DocumentType.image ? path : null,
        );
      }
    } catch (e) {
      setState(() {
        _statusText = 'Gagal memproses file: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  String _statusLabelFor(DocumentType type) {
    switch (type) {
      case DocumentType.pdf:
        return 'Membaca dokumen PDF...';
      case DocumentType.docx:
        return 'Membaca dokumen Word...';
      case DocumentType.image:
        return 'Memproses gambar...';
      case DocumentType.unsupported:
        return 'Jenis file tidak didukung';
    }
  }

  IconData _iconFor(DocumentType? type) {
    switch (type) {
      case DocumentType.pdf:
        return Icons.picture_as_pdf_rounded;
      case DocumentType.docx:
        return Icons.description_rounded;
      case DocumentType.image:
        return Icons.image_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _speakText() async {
    if (_resultText.isEmpty) return;
    setState(() => _isSpeaking = true);

    // speakLong() memecah teks panjang (dokumen 30-40 halaman bisa berisi
    // puluhan ribu karakter) menjadi potongan kecil yang aman dibacakan
    // TTS engine Android secara berurutan, tanpa gagal diam-diam.
    await TtsService.instance.speakLong(_resultText);

    if (mounted) setState(() => _isSpeaking = false);
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
      _importedFileType = null;
      _statusText = 'Pilih sumber file untuk diimpor';
      _progressCurrent = 0;
      _progressTotal = 0;
    });
    TtsService.instance.stop();
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
                  const Text(
                    'Impor File',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0D21),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded, color: Color(0xFF9C27B0), size: 12),
                        SizedBox(width: 5),
                        Text(
                          'IMPOR',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9C27B0),
                            letterSpacing: 1,
                          ),
                        ),
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
              child: _importedFileName.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_importedImagePath != null)
                          Image.file(File(_importedImagePath!), fit: BoxFit.cover)
                        else
                          Container(
                            color: const Color(0xFF1A1A1A),
                            child: Center(
                              child: Icon(
                                _iconFor(_importedFileType),
                                size: 64,
                                color: const Color(0xFF9C27B0).withOpacity(0.3),
                              ),
                            ),
                          ),
                        Container(color: Colors.black38),
                        if (_isProcessing)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: Color(0xFF9C27B0)),
                                const SizedBox(height: 12),
                                Text(
                                  _progressTotal > 0
                                      ? 'Halaman $_progressCurrent / $_progressTotal'
                                      : 'Mengekstrak teks...',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(_iconFor(_importedFileType),
                                    color: const Color(0xFF9C27B0), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _importedFileName,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                            border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.upload_file_rounded,
                              color: Color(0xFF9C27B0), size: 32),
                        ),
                        const SizedBox(height: 12),
                        const Text('Belum ada file diimpor',
                            style: TextStyle(color: Colors.white54, fontSize: 14)),
                        const SizedBox(height: 6),
                        const Text('Mendukung PDF, Word (.docx), dan gambar',
                            style: TextStyle(color: Colors.white24, fontSize: 11)),
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0D21),
                    foregroundColor: const Color(0xFF9C27B0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: const Color(0xFF9C27B0).withOpacity(0.5)),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 15, color: Color(0xFF666666)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_statusText,
                          style: const TextStyle(color: Color(0xFF999999), fontSize: 12)),
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
                                  fontSize: 10, color: Color(0xFF666666), letterSpacing: 1)),
                          const Spacer(),
                          if (_resultText.isNotEmpty)
                            Text('${_resultText.length} karakter',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF666666))),
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
                            color: _resultText.isEmpty ? const Color(0xFF444444) : Colors.white,
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
                        icon: Icon(_isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                            size: 18),
                        label: Text(_isSpeaking ? 'Hentikan' : 'Putar Suara'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isSpeaking ? const Color(0xFF8B1A1A) : const Color(0xFF1B4D3E),
                          foregroundColor:
                              _isSpeaking ? Colors.white : const Color(0xFF7ED9B8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
            label: 'Impor File (PDF / Word)',
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
            label: 'Membatalkan',
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
            color: isCancel ? const Color(0xFF2A2A2A) : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isCancel ? Colors.white38 : Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isCancel ? Colors.white38 : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}