import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('visionassist.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    print('📂 DB PATH: $path');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // ── Tabel 1: detection_history ──
    await db.execute('''
      CREATE TABLE detection_history (
        id_detection  INTEGER PRIMARY KEY AUTOINCREMENT,
        detected_object   TEXT NOT NULL,
        confidence_score  REAL NOT NULL,
        image_path        TEXT,
        detection_time    TEXT NOT NULL
      )
    ''');

    // ── Tabel 2: ocr_history ──
    // Relasi: id_detection → detection_history (menghasilkan)
    await db.execute('''
      CREATE TABLE ocr_history (
        id_ocr          INTEGER PRIMARY KEY AUTOINCREMENT,
        id_detection    INTEGER,
        extracted_text  TEXT NOT NULL,
        ocr_time        TEXT NOT NULL,
        processing_time REAL,
        FOREIGN KEY (id_detection) REFERENCES detection_history(id_detection)
          ON DELETE SET NULL
      )
    ''');

    // ── Tabel 3: tts_history ──
    // Relasi: id_ocr → ocr_history (menghasilkan)
    await db.execute('''
      CREATE TABLE tts_history (
        id_tts      INTEGER PRIMARY KEY AUTOINCREMENT,
        id_ocr      INTEGER,
        spoken_text TEXT NOT NULL,
        tts_time    TEXT NOT NULL,
        audio_path  TEXT,
        FOREIGN KEY (id_ocr) REFERENCES ocr_history(id_ocr)
          ON DELETE SET NULL
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
  // Hapus tabel lama
  await db.execute('DROP TABLE IF EXISTS history');
  await db.execute('DROP TABLE IF EXISTS detection_history');
  await db.execute('DROP TABLE IF EXISTS ocr_history');
  await db.execute('DROP TABLE IF EXISTS tts_history');
  // Buat ulang tabel baru
  await _createDB(db, newVersion);
}

  // ═══════════════════════════════════════════
  // DETECTION HISTORY - CRUD
  // ═══════════════════════════════════════════

  /// Simpan hasil deteksi objek
  Future<int> insertDetection({
    required String detectedObject,
    required double confidenceScore,
    String? imagePath,
  }) async {
    final db = await database;
    return await db.insert('detection_history', {
      'detected_object':  detectedObject,
      'confidence_score': confidenceScore,
      'image_path':       imagePath,
      'detection_time':   DateTime.now().toIso8601String(),
    });
  }

  /// Ambil semua riwayat deteksi (terbaru dulu)
  Future<List<Map<String, dynamic>>> getAllDetections() async {
    final db = await database;
    return await db.query(
      'detection_history',
      orderBy: 'detection_time DESC',
    );
  }

  /// Ambil 1 deteksi berdasarkan id
  Future<Map<String, dynamic>?> getDetectionById(int id) async {
    final db = await database;
    final result = await db.query(
      'detection_history',
      where: 'id_detection = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Hapus 1 riwayat deteksi
  Future<int> deleteDetection(int id) async {
    final db = await database;
    return await db.delete(
      'detection_history',
      where: 'id_detection = ?',
      whereArgs: [id],
    );
  }

  // ═══════════════════════════════════════════
  // OCR HISTORY - CRUD
  // ═══════════════════════════════════════════

  /// Simpan hasil OCR
  /// [idDetection] opsional — jika OCR berasal dari hasil deteksi
  Future<int> insertOcr({
    required String extractedText,
    int? idDetection,
    double? processingTime,
  }) async {
    final db = await database;
    return await db.insert('ocr_history', {
      'id_detection':   idDetection,
      'extracted_text': extractedText,
      'ocr_time':       DateTime.now().toIso8601String(),
      'processing_time': processingTime,
    });
  }

  /// Ambil semua riwayat OCR (terbaru dulu)
  Future<List<Map<String, dynamic>>> getAllOcr() async {
    final db = await database;
    return await db.query(
      'ocr_history',
      orderBy: 'ocr_time DESC',
    );
  }

  /// Ambil OCR berdasarkan id_detection (relasi)
  Future<List<Map<String, dynamic>>> getOcrByDetection(int idDetection) async {
    final db = await database;
    return await db.query(
      'ocr_history',
      where: 'id_detection = ?',
      whereArgs: [idDetection],
      orderBy: 'ocr_time DESC',
    );
  }

  /// Ambil 1 OCR berdasarkan id
  Future<Map<String, dynamic>?> getOcrById(int id) async {
    final db = await database;
    final result = await db.query(
      'ocr_history',
      where: 'id_ocr = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Hapus 1 riwayat OCR
  Future<int> deleteOcr(int id) async {
    final db = await database;
    return await db.delete(
      'ocr_history',
      where: 'id_ocr = ?',
      whereArgs: [id],
    );
  }

  // ═══════════════════════════════════════════
  // TTS HISTORY - CRUD
  // ═══════════════════════════════════════════

  /// Simpan riwayat TTS
  /// [idOcr] opsional — jika TTS berasal dari hasil OCR
  Future<int> insertTts({
    required String spokenText,
    int? idOcr,
    String? audioPath,
  }) async {
    final db = await database;
    return await db.insert('tts_history', {
      'id_ocr':       idOcr,
      'spoken_text':  spokenText,
      'tts_time':     DateTime.now().toIso8601String(),
      'audio_path':   audioPath,
    });
  }

  /// Ambil semua riwayat TTS (terbaru dulu)
  Future<List<Map<String, dynamic>>> getAllTts() async {
    final db = await database;
    return await db.query(
      'tts_history',
      orderBy: 'tts_time DESC',
    );
  }

  /// Ambil TTS berdasarkan id_ocr (relasi)
  Future<List<Map<String, dynamic>>> getTtsByOcr(int idOcr) async {
    final db = await database;
    return await db.query(
      'tts_history',
      where: 'id_ocr = ?',
      whereArgs: [idOcr],
      orderBy: 'tts_time DESC',
    );
  }

  /// Hapus 1 riwayat TTS
  Future<int> deleteTts(int id) async {
    final db = await database;
    return await db.delete(
      'tts_history',
      where: 'id_tts = ?',
      whereArgs: [id],
    );
  }

  // ═══════════════════════════════════════════
  // QUERY GABUNGAN (JOIN)
  // ═══════════════════════════════════════════

  /// Ambil semua riwayat gabungan untuk halaman Perpustakaan
  /// Menggabungkan detection, ocr, dan tts dalam satu query
  Future<List<Map<String, dynamic>>> getAllHistory() async {
    final db = await database;

    // Gabungkan semua tabel dengan UNION
    final detections = await db.rawQuery('''
      SELECT
        'Deteksi Objek'   AS type,
        id_detection      AS id,
        detected_object   AS result,
        confidence_score  AS extra,
        image_path,
        detection_time    AS created_at
      FROM detection_history
      ORDER BY detection_time DESC
    ''');

    final ocrs = await db.rawQuery('''
      SELECT
        'OCR'           AS type,
        id_ocr          AS id,
        extracted_text  AS result,
        processing_time AS extra,
        NULL            AS image_path,
        ocr_time        AS created_at
      FROM ocr_history
      ORDER BY ocr_time DESC
    ''');

    final tts = await db.rawQuery('''
      SELECT
        'TTS'         AS type,
        id_tts        AS id,
        spoken_text   AS result,
        NULL          AS extra,
        audio_path    AS image_path,
        tts_time      AS created_at
      FROM tts_history
      ORDER BY tts_time DESC
    ''');

    // Gabungkan & urutkan berdasarkan waktu terbaru
    final all = [...detections, ...ocrs, ...tts];
    all.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));

    return all;
  }

  /// Ambil rantai lengkap: detection → ocr → tts
  Future<Map<String, dynamic>> getFullChain(int idDetection) async {
    final detection = await getDetectionById(idDetection);
    final ocrs      = await getOcrByDetection(idDetection);

    final ocrWithTts = <Map<String, dynamic>>[];
    for (final ocr in ocrs) {
      final ttsList = await getTtsByOcr(ocr['id_ocr'] as int);
      ocrWithTts.add({...ocr, 'tts_list': ttsList});
    }

    return {
      'detection': detection,
      'ocr_list':  ocrWithTts,
    };
  }

  // ═══════════════════════════════════════════
  // HAPUS SEMUA DATA
  // ═══════════════════════════════════════════

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('tts_history');
    await db.delete('ocr_history');
    await db.delete('detection_history');
  }

  Future<void> clearDetections() async {
    final db = await database;
    await db.delete('detection_history');
  }

  Future<void> clearOcr() async {
    final db = await database;
    await db.delete('ocr_history');
  }

  Future<void> clearTts() async {
    final db = await database;
    await db.delete('tts_history');
  }

  // Untuk kompatibilitas dengan kode lama (history_screen.dart)
  Future<int> insertHistory({
    required String type,
    required String result,
    String? imagePath,
  }) async {
    if (type == 'Deteksi Objek') {
      return await insertDetection(
        detectedObject:  result,
        confidenceScore: 0.0,
        imagePath:       imagePath,
      );
    } else if (type == 'OCR' || type == 'Impor File') {
      return await insertOcr(
        extractedText: result,
      );
    } else {
      return await insertTts(
        spokenText: result,
      );
    }
  }
}