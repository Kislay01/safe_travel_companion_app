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

  /// "help" and words the recogniser often hears instead of it.
  static const _helpWords = {'help', 'helps', 'helped', 'yelp', 'kelp', 'halp', 'helpme'};
  static const _helpFollowers = {'me', 'mi', 'mee', 'please', 'someone', 'us', 'plz'};

  /// Phrases that trigger on their own (English + Hindi).
  static const _phrases = [
    'save me', 'help me', 'emergency', 'sos', 's o s',
    'bachao', 'bachaao', 'bacho', 'bachav', 'madad', 'madad karo',
  ];

  /// True if [text] contains a distress phrase. Exposed for testing.
  static bool matches(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;
    final joined = ' ${words.join(' ')} ';
    if (_phrases.any((p) => joined.contains(' $p '))) return true;
    // Just "help" on its own (shouting it once) also counts.
    if (words.length == 1 && _helpWords.contains(words.first)) return true;

    for (var i = 0; i < words.length; i++) {
      if (!_helpWords.contains(words[i])) continue;
      if (words[i] == 'helpme') return true;
      final next = i + 1 < words.length ? words[i + 1] : '';
      final prev = i > 0 ? words[i - 1] : '';
      // "help me", "help please", "help help", "please help", "someone help"
      if (_helpFollowers.contains(next) || _helpWords.contains(next)) return true;
      if (prev == 'please' || prev == 'someone') return true;
    }
    return false;
  }

  final SpeechToText _speech = SpeechToText();
  bool _initialised = false;
  bool _enabled = false;
  bool _handling = false;
  String? _localeId;
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
    // Prefer Indian English (better for Indian accents and Hindi words).
    try {
      final locales = await _speech.locales();
      final ids = locales.map((l) => l.localeId.replaceAll('-', '_').toLowerCase()).toList();
      final i = ids.indexOf('en_in');
      _localeId = i >= 0 ? locales[i].localeId : null;
    } catch (_) {
      _localeId = null;
    }
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
      localeId: _localeId,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 10),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
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
    // Check every alternative transcription, not just the top guess.
    final candidates = <String>{
      result.recognizedWords,
      ...result.alternates.map((a) => a.recognizedWords),
    };
    for (final c in candidates) {
      if (matches(c)) {
        _handleTrigger(c.toLowerCase());
        return;
      }
    }
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
