import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech service for the blind/vision-assist mode.
///
/// On Windows, uses SAPI via PowerShell to avoid flutter_tts threading crash.
/// On all other platforms, uses `flutter_tts`.
class TtsService {
  static final TtsService instance = TtsService._internal();
  TtsService._internal();

  FlutterTts? _tts;
  bool _speaking = false;
  bool _initialized = false;
  bool _useWindowsFallback = false;
  Process? _windowsProcess;

  bool get isSpeaking => _speaking;

  /// Initialize the TTS engine.  Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // On Windows, flutter_tts sends channel messages from a non-platform
    // thread which crashes the engine.  Use SAPI via PowerShell instead.
    if (!kIsWeb && Platform.isWindows) {
      _useWindowsFallback = true;
      debugPrint('TtsService: using Windows SAPI fallback');
      return;
    }

    try {
      final tts = FlutterTts();

      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);

      tts.setStartHandler(() => _speaking = true);
      tts.setCompletionHandler(() => _speaking = false);
      tts.setCancelHandler(() => _speaking = false);
      tts.setErrorHandler((msg) {
        debugPrint('TtsService error: $msg');
        _speaking = false;
      });

      _tts = tts;
    } catch (e) {
      debugPrint('TtsService init failed: $e');
      _tts = null;
    }
  }

  /// Speak [text].  If already speaking, stops current utterance first.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    if (_useWindowsFallback) {
      await _speakWindows(text);
      return;
    }

    if (_tts == null) return;
    try {
      await _tts!.stop();
      _speaking = true;
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('TtsService speak error: $e');
      _speaking = false;
    }
  }

  /// Stop any current speech.
  Future<void> stop() async {
    if (_useWindowsFallback) {
      _windowsProcess?.kill();
      _windowsProcess = null;
      _speaking = false;
      return;
    }

    _speaking = false;
    try {
      await _tts?.stop();
    } catch (e) {
      debugPrint('TtsService stop error: $e');
    }
  }

  /// Windows SAPI TTS via PowerShell.  Non-blocking — runs as a separate
  /// process so the Dart event loop is not blocked.
  Future<void> _speakWindows(String text) async {
    // Kill any running speech process first.
    _windowsProcess?.kill();
    _windowsProcess = null;

    _speaking = true;

    // Sanitise input for PowerShell single-quoted string.
    final escaped = text.replaceAll("'", "''");

    try {
      final process = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        "Add-Type -AssemblyName System.Speech; "
            "\$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            "\$synth.Rate = 1; "
            "\$synth.Speak('$escaped')",
      ]);

      _windowsProcess = process;

      // When the process finishes, clear the speaking flag.
      process.exitCode.then((_) {
        if (_windowsProcess == process) {
          _speaking = false;
          _windowsProcess = null;
        }
      });
    } catch (e) {
      debugPrint('Windows TTS error: $e');
      _speaking = false;
    }
  }

  /// Select a voice by name (platform-dependent).
  Future<void> setVoice(String voice) async {
    // Voice selection is platform-dependent; stored for future use.
  }
}
