import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:sos_system/common/views/safety_dialogs.dart';
import 'package:sos_system/core/app_navigator.dart';
import 'package:sos_system/services/sos_service.dart';

/// Hands-free SOS: keeps the speech recogniser listening while the app is
/// open and triggers SOS (after a 5 s cancellable countdown) on a key phrase.
class VoiceSosService {
  VoiceSosService._();
  static final VoiceSosService instance = VoiceSosService._();

  static const prefKey = 'voiceSosEnabled';
  static const phrases = ['help me', 'save me', 'bachao', 'emergency', 'sos', 's o s'];

  final SpeechToText _speech = SpeechToText();
  bool _initialised = false;
  bool _enabled = false;
  bool _handling = false;
  final ValueNotifier<bool> listening = ValueNotifier(false);

  bool get enabled => _enabled;

  static Future<bool> isEnabledInPrefs() async =>
      (await SharedPreferences.getInstance()).getBool(prefKey) ?? false;

  static Future<void> saveEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(prefKey, value);

  /// Returns false if the microphone or speech recogniser is unavailable.
  Future<bool> start() async {
    if (_enabled) return true;
    if (!(await Permission.microphone.request()).isGranted) return false;
    if (!_initialised) {
      _initialised = await _speech.initialize(
        onStatus: _onStatus,
        onError: (_) => _restartSoon(),
      );
    }
    if (!_initialised) return false;
    _enabled = true;
    _listen();
    return true;
  }

  Future<void> stop() async {
    _enabled = false;
    listening.value = false;
    if (_initialised) await _speech.stop();
  }

  void _listen() {
    if (!_enabled || _handling || _speech.isListening) return;
    _speech.listen(
      onResult: _onResult,
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 10),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
    );
    listening.value = true;
  }

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      listening.value = false;
      _restartSoon();
    }
  }

  void _restartSoon() {
    if (!_enabled || _handling) return;
    Future.delayed(const Duration(milliseconds: 800), _listen);
  }

  void _onResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.toLowerCase();
    if (phrases.any((p) => words.contains(p))) _handleTrigger(words);
  }

  Future<void> _handleTrigger(String words) async {
    if (_handling) return;
    _handling = true;
    await _speech.stop();
    listening.value = false;
    try {
      final ctx = appContext;
      bool send = true;
      if (ctx != null) {
        send = await showDialog<bool>(
              context: ctx,
              barrierDismissible: false,
              builder: (_) => SosCountdownDialog(reason: 'Heard: "$words"'),
            ) ??
            false;
      }
      if (send) {
        final msg = await SosService.trigger(source: 'voice');
        final c = appContext;
        if (c != null && c.mounted) {
          ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } finally {
      _handling = false;
      _restartSoon();
    }
  }
}
