import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService instance = TtsService._init();
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _stopRequested = false;
  Completer<void>? _speakCompleter;

  // Batas aman karakter per panggilan speak() untuk TTS engine Android.
  // Android TextToSpeech punya limit internal sekitar 4000 karakter
  // (TextToSpeech.getMaxSpeechInputLength()), jadi kita pakai batas
  // yang lebih kecil agar aman dan tidak terpotong di tengah kata.
  static const int _maxChunkLength = 1000;

  TtsService._init() {
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() => _isSpeaking = true);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    });
  }

  bool get isSpeaking => _isSpeaking;

  /// Membacakan teks singkat (di bawah limit). Untuk teks panjang
  /// (dokumen, hasil OCR banyak halaman), gunakan [speakLong] sebagai gantinya.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await stop();
    _stopRequested = false;
    _speakCompleter = Completer<void>();
    await _tts.speak(text);
  }

  /// Membacakan teks panjang (misalnya hasil OCR dari dokumen 30-40 halaman)
  /// dengan cara memecahnya menjadi beberapa potongan (chunk) kecil yang
  /// dibacakan satu per satu secara berurutan. Ini diperlukan karena TTS
  /// engine Android memiliki batas maksimal karakter per panggilan speak(),
  /// sehingga teks yang sangat panjang akan gagal diam-diam jika dikirim
  /// sekaligus tanpa dipecah.
  Future<void> speakLong(String text) async {
    if (text.isEmpty) return;
    await stop();
    _stopRequested = false;

    final chunks = _splitIntoChunks(text, _maxChunkLength);

    for (final chunk in chunks) {
      if (_stopRequested) break;
      _isSpeaking = true;
      _speakCompleter = Completer<void>();
      await _tts.speak(chunk);
      await waitUntilDone();
      if (_stopRequested) break;
      // Jeda singkat antar potongan agar terdengar natural
      await Future.delayed(const Duration(milliseconds: 150));
    }

    _isSpeaking = false;
  }

  /// Memecah teks panjang menjadi potongan-potongan yang aman dibacakan TTS.
  /// Pemecahan dilakukan di batas kalimat (titik, tanda seru, tanda tanya)
  /// atau baris baru jika memungkinkan, supaya tidak memotong di tengah kata
  /// atau kalimat yang sedang berlangsung.
  List<String> _splitIntoChunks(String text, int maxLength) {
    final chunks = <String>[];
    final paragraphs = text.split('\n');

    var buffer = StringBuffer();

    void flushBuffer() {
      final content = buffer.toString().trim();
      if (content.isNotEmpty) chunks.add(content);
      buffer = StringBuffer();
    }

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) continue;

      // Kalau paragraf saja sudah lebih panjang dari maxLength,
      // pecah lagi berdasarkan kalimat (titik/tanda baca akhir kalimat)
      if (paragraph.length > maxLength) {
        final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
        for (final sentence in sentences) {
          if (buffer.length + sentence.length > maxLength) {
            flushBuffer();
          }
          if (sentence.length > maxLength) {
            // Kalimat tunggal masih terlalu panjang, potong paksa per kata
            final words = sentence.split(' ');
            for (final word in words) {
              if (buffer.length + word.length + 1 > maxLength) {
                flushBuffer();
              }
              buffer.write('$word ');
            }
          } else {
            buffer.write('$sentence ');
          }
        }
      } else {
        if (buffer.length + paragraph.length > maxLength) {
          flushBuffer();
        }
        buffer.write('$paragraph. ');
      }
    }
    flushBuffer();

    return chunks;
  }

  /// Menunggu sampai ucapan TTS yang sedang berjalan benar-benar selesai.
  Future<void> waitUntilDone() async {
    if (_speakCompleter == null || _speakCompleter!.isCompleted) return;
    await _speakCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
  }

  Future<void> stop() async {
    _stopRequested = true;
    await _tts.stop();
    _isSpeaking = false;
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
  }

  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
  }

  Future<void> setLanguage(String lang) async {
    await _tts.setLanguage(lang);
  }

  Future<List<dynamic>> getAvailableLanguages() async {
    return await _tts.getLanguages;
  }
}