import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech guidance service for hands-free indoor navigation.
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool isMuted = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5); // Clear, steady pacing for accessibility
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        debugPrint('[TTS] Started vocalizing');
      });

      _flutterTts.setCompletionHandler(() {
        debugPrint('[TTS] Finished vocalizing');
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[TTS] Error: $msg');
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('[TTS] Initialization error: $e');
    }
  }

  /// Speaks regular navigation instructions.
  Future<void> speak(String text) async {
    if (isMuted || text.isEmpty) return;
    try {
      if (!_isInitialized) await init();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[TTS] Speak error: $e');
    }
  }

  /// Interrupts any current speech immediately to vocalize an urgent hazard or obstacle alert.
  Future<void> speakUrgent(String text) async {
    if (isMuted) return;
    try {
      if (!_isInitialized) await init();
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[TTS] Urgent speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('[TTS] Stop error: $e');
    }
  }
}
