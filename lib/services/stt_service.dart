import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Speech-to-text service for the deaf/hearing-assist mode.
///
/// On Windows, uses SAPI via PowerShell to avoid the speech_to_text_windows
/// plugin threading crash.  On all other platforms uses `speech_to_text`.
class SttService {
  static final SttService instance = SttService._internal();
  SttService._internal();

  // ── cross-platform plugin path ──────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool _available = false;

  // ── Windows fallback path ──────────────────────────────────────────────
  bool _useWindowsFallback = false;
  Process? _windowsProcess;
  bool _windowsListening = false;

  /// Called with partial (in-progress) transcription text.
  void Function(String text)? onPartialResult;

  /// Called when a final (committed) transcription segment is ready.
  void Function(String text)? onFinalResult;

  /// Called on recognition errors.
  void Function(String error)? onError;

  bool get isListening =>
      _useWindowsFallback ? _windowsListening : _speech.isListening;

  /// Initialize the speech engine.
  Future<bool> init() async {
    if (_initialized) return _available;
    _initialized = true;

    // On Windows, use SAPI directly to avoid native threading crash.
    if (!kIsWeb && Platform.isWindows) {
      _useWindowsFallback = true;
      _available = true;
      debugPrint('SttService: using Windows SAPI fallback');
      return true;
    }

    try {
      _available = await _speech.initialize(
        onError: (error) {
          debugPrint('SttService error: ${error.errorMsg}');
          onError?.call(error.errorMsg);
        },
        onStatus: (status) {
          debugPrint('SttService status: $status');
        },
      );
    } catch (e) {
      debugPrint('SttService init failed: $e');
      _available = false;
    }

    return _available;
  }

  /// Start listening for speech.
  Future<void> startListening() async {
    if (!_available) return;

    if (_useWindowsFallback) {
      await _startWindowsListening();
      return;
    }

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onFinalResult?.call(result.recognizedWords);
        } else {
          onPartialResult?.call(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  /// Stop listening.
  Future<void> stopListening() async {
    if (_useWindowsFallback) {
      _stopWindowsListening();
      return;
    }
    await _speech.stop();
  }

  // ── Windows SAPI implementation ─────────────────────────────────────────

  Future<void> _startWindowsListening() async {
    _stopWindowsListening();

    _windowsListening = true;

    try {
      // Inline C# speech recognizer that writes to stdout.
      // Using C# instead of PowerShell event handlers because
      // Register-ObjectEvent runs in a separate runspace where
      // Console.Out doesn't reach the parent process stdout.
      const script = r'''
Add-Type -AssemblyName System.Speech
Add-Type -ReferencedAssemblies System.Speech -TypeDefinition @"
using System;
using System.Speech.Recognition;

public class SpeechHelper {
    private SpeechRecognitionEngine engine;

    public SpeechHelper() {
        engine = new SpeechRecognitionEngine();
        engine.SetInputToDefaultAudioDevice();
        engine.LoadGrammar(new DictationGrammar());

        engine.SpeechRecognized += (s, e) => {
            if (e.Result != null && e.Result.Confidence >= 0.3) {
                Console.Out.WriteLine("FINAL:" + e.Result.Text);
                Console.Out.Flush();
            }
        };

        engine.SpeechHypothesized += (s, e) => {
            if (e.Result != null) {
                Console.Out.WriteLine("PARTIAL:" + e.Result.Text);
                Console.Out.Flush();
            }
        };
    }

    public void Start() {
        engine.RecognizeAsync(RecognizeMode.Multiple);
    }

    public void Stop() {
        engine.RecognizeAsyncCancel();
        engine.Dispose();
    }
}
"@

$helper = New-Object SpeechHelper
$helper.Start()
try {
    while ($true) { Start-Sleep -Milliseconds 200 }
} finally {
    $helper.Stop()
}
''';

      final process = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        script,
      ]);

      _windowsProcess = process;

      // Read stdout lines and forward as partial/final results.
      process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.startsWith('FINAL:')) {
            final text = trimmed.substring(6).trim();
            if (text.isNotEmpty) onFinalResult?.call(text);
          } else if (trimmed.startsWith('PARTIAL:')) {
            final text = trimmed.substring(8).trim();
            if (text.isNotEmpty) onPartialResult?.call(text);
          } else if (trimmed.isNotEmpty) {
            // Legacy fallback — treat plain lines as final results.
            onFinalResult?.call(trimmed);
          }
        },
        onError: (e) {
          debugPrint('SttService Windows stdout error: $e');
          onError?.call(e.toString());
        },
      );

      // Read stderr for diagnostics.
      process.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('SttService Windows stderr: $line');
      });

      // Handle process exit.
      process.exitCode.then((_) {
        if (_windowsProcess == process) {
          _windowsListening = false;
          _windowsProcess = null;
        }
      });
    } catch (e) {
      debugPrint('SttService Windows start error: $e');
      _windowsListening = false;
      onError?.call(e.toString());
    }
  }

  void _stopWindowsListening() {
    _windowsProcess?.kill();
    _windowsProcess = null;
    _windowsListening = false;
  }
}
