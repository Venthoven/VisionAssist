import 'dart:io';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:pdf_render_plus/pdf_render.dart' as render;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:image/image.dart' as img;
import '../services/ocr_text_sorter.dart';

/// Jenis file dokumen yang didukung untuk fitur Impor File.
enum DocumentType { pdf, docx, image, unsupported }

/// Hasil pembacaan dokumen, termasuk progress untuk dokumen panjang
/// (PDF/Word berhalaman banyak) supaya UI bisa menampilkan progress bar.
class DocumentReadResult {
  final String text;
  final int totalPages;

  DocumentReadResult({required this.text, this.totalPages = 1});
}

class DocumentReaderService {
  static final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Menentukan jenis dokumen berdasarkan ekstensi file.
  static DocumentType detectType(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return DocumentType.pdf;
      case 'docx':
        return DocumentType.docx;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'bmp':
      case 'webp':
        return DocumentType.image;
      default:
        return DocumentType.unsupported;
    }
  }

  /// Membaca isi file Word (.docx) secara langsung sebagai teks.
  static Future<DocumentReadResult> readDocx(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final text = docxToText(bytes);
    return DocumentReadResult(text: text.trim());
  }

  /// Membaca isi file PDF. Ada dua jenis PDF:
  /// 1. PDF berbasis teks asli (dibuat dari Word/aplikasi office) — teks
  ///    bisa diambil langsung tanpa OCR menggunakan Syncfusion PDF.
  /// 2. PDF hasil scan (berupa gambar halaman) — perlu dirender per halaman
  ///    menjadi gambar lalu diproses dengan OCR satu per satu menggunakan
  ///    package pdf_render.
  ///
  /// [onProgress] dipanggil setiap kali satu halaman selesai diproses,
  /// berguna untuk menampilkan progress bar pada dokumen 30-40 halaman.
  static Future<DocumentReadResult> readPdf(
    String filePath, {
    void Function(int current, int total)? onProgress,
  }) async {
    final bytes = await File(filePath).readAsBytes();

    // Tahap 1: coba ekstrak teks langsung (PDF berbasis teks asli)
    // menggunakan Syncfusion PdfDocument. Jauh lebih cepat dan akurat
    // dibanding OCR, jadi diprioritaskan.
    try {
      final document = syncfusion.PdfDocument(inputBytes: bytes);
      final extractor = syncfusion.PdfTextExtractor(document);
      final directText = extractor.extractText();
      document.dispose();

      // Kalau hasil ekstraksi langsung cukup banyak (bukan PDF hasil scan
      // yang biasanya menghasilkan teks kosong/sangat sedikit), pakai ini.
      if (directText.trim().length > 50) {
        return DocumentReadResult(text: directText.trim());
      }
    } catch (_) {
      // Lanjut ke metode OCR per halaman di bawah jika ekstraksi gagal
    }

    // Tahap 2: PDF hasil scan (gambar) — render setiap halaman jadi
    // gambar menggunakan pdf_render, lalu jalankan OCR pada masing-masing
    // halaman secara berurutan.
    final pdfDoc = await render.PdfDocument.openFile(filePath);
    final totalPages = pdfDoc.pageCount;
    final allPageTexts = <String>[];

    for (int i = 1; i <= totalPages; i++) {
      onProgress?.call(i, totalPages);

      final page = await pdfDoc.getPage(i);

      // Render halaman PDF menjadi gambar RGBA mentah pada resolusi 2x
      // supaya hasil OCR lebih akurat untuk teks berukuran kecil.
      final pageImage = await page.render(
        width: (page.width * 2).toInt(),
        height: (page.height * 2).toInt(),
      );

      // pageImage.pixels berisi data RGBA mentah (bukan format file gambar
      // seperti PNG/JPEG), sehingga perlu dikonversi menggunakan package
      // `image` menjadi file PNG yang baru bisa dibaca oleh ML Kit OCR.
      final rgbaImage = img.Image.fromBytes(
        width: pageImage.width,
        height: pageImage.height,
        bytes: pageImage.pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final pngBytes = img.encodePng(rgbaImage);

      final tempPath = '${filePath}_page$i.png';
      await File(tempPath).writeAsBytes(pngBytes);

      final inputImage = InputImage.fromFilePath(tempPath);
      final recognized = await _textRecognizer.processImage(inputImage);
      final sortedText = OcrTextSorter.sortByLine(recognized);

      if (sortedText.trim().isNotEmpty) {
        allPageTexts.add(sortedText.trim());
      }

      // Bersihkan file sementara
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }

    pdfDoc.dispose();

    return DocumentReadResult(
      text: allPageTexts.join('\n\n'),
      totalPages: totalPages,
    );
  }

  /// Membaca gambar biasa (jpg, png, dll) menggunakan OCR seperti biasa.
  static Future<DocumentReadResult> readImage(String filePath) async {
    final inputImage = InputImage.fromFilePath(filePath);
    final recognized = await _textRecognizer.processImage(inputImage);
    final sortedText = OcrTextSorter.sortByLine(recognized);
    return DocumentReadResult(text: sortedText.trim());
  }

  /// Fungsi utama yang otomatis mendeteksi jenis file dan memanggil
  /// pembaca yang sesuai (PDF, Word, atau gambar).
  static Future<DocumentReadResult> readDocument(
    String filePath, {
    void Function(int current, int total)? onProgress,
  }) async {
    final type = detectType(filePath);
    switch (type) {
      case DocumentType.pdf:
        return readPdf(filePath, onProgress: onProgress);
      case DocumentType.docx:
        return readDocx(filePath);
      case DocumentType.image:
        return readImage(filePath);
      case DocumentType.unsupported:
        throw Exception(
            'Jenis file tidak didukung. Gunakan PDF, Word (.docx), atau gambar.');
    }
  }
}