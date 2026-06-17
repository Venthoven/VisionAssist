import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Utility untuk menyusun ulang hasil OCR berdasarkan posisi baris (top-to-bottom,
/// left-to-right), bukan urutan blok asli dari ML Kit yang kadang tidak berurutan
/// terutama pada struk belanja dengan 2 kolom (misal: "Antrian 34" dan "Bawa Pulang").
class OcrTextSorter {
  /// Mengembalikan teks yang sudah diurutkan ulang per baris.
  static String sortByLine(RecognizedText recognizedText) {
    // Kumpulkan semua baris (TextLine) dari seluruh blok, lengkap dengan posisi Y
    final allLines = <_LineWithPosition>[];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        allLines.add(_LineWithPosition(
          text: line.text,
          top: line.boundingBox.top,
          left: line.boundingBox.left,
          bottom: line.boundingBox.bottom,
        ));
      }
    }

    if (allLines.isEmpty) return recognizedText.text.trim();

    // Urutkan dulu berdasarkan posisi Y (atas ke bawah)
    allLines.sort((a, b) => a.top.compareTo(b.top));

    // Kelompokkan baris yang berada di ketinggian (Y) yang berdekatan
    // menjadi satu "baris gabungan" — ini menangani kasus 2 kolom
    // seperti "Antrian 34" (kiri) dan "Bawa Pulang" (kanan) yang
    // sebenarnya satu baris yang sama secara visual.
    final groupedLines = <List<_LineWithPosition>>[];
    const lineHeightTolerance = 15.0; // toleransi piksel untuk dianggap 1 baris

    for (final line in allLines) {
      bool addedToGroup = false;
      for (final group in groupedLines) {
        final refLine = group.first;
        final avgHeight = (refLine.bottom - refLine.top).abs();
        final tolerance = avgHeight > 0 ? avgHeight * 0.6 : lineHeightTolerance;

        if ((line.top - refLine.top).abs() <= tolerance) {
          group.add(line);
          addedToGroup = true;
          break;
        }
      }
      if (!addedToGroup) {
        groupedLines.add([line]);
      }
    }

    // Dalam setiap grup (baris gabungan), urutkan dari kiri ke kanan
    for (final group in groupedLines) {
      group.sort((a, b) => a.left.compareTo(b.left));
    }

    // Gabungkan jadi teks final: setiap grup = 1 baris,
    // dalam grup digabung dengan spasi (karena posisinya sejajar horizontal)
    final resultLines = groupedLines.map((group) {
      return group.map((l) => l.text).join('   ');
    }).toList();

    return resultLines.join('\n');
  }
}

class _LineWithPosition {
  final String text;
  final double top;
  final double left;
  final double bottom;

  _LineWithPosition({
    required this.text,
    required this.top,
    required this.left,
    required this.bottom,
  });
}