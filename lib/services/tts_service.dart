import 'package:flutter_tts/flutter_tts.dart';
import 'database_helper.dart'; // tambah import ini

class TtsService {
  static final TtsService instance = TtsService._init();
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  TtsService._init() {
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
  }

  bool get isSpeaking => _isSpeaking;

  Future<void> speak(String text, {bool saveToHistory = true}) async { // ← tambah parameter
    if (text.isEmpty) return;
    await stop();
    await _tts.speak(text);
    if (saveToHistory) { // ← simpan ke database
      await DatabaseHelper.instance.insertTts(spokenText: text);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
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