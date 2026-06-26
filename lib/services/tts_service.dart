import 'dart:js_interop';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Text-to-speech for Guardian HUD's voice-out guidance.
///
/// On web this drives the browser Web Speech API (`speechSynthesis`) through
/// the `guardianSpeak` / `guardianSpeakStop` helpers defined in
/// `web/index.html`. On non-web targets it is a silent no-op so the rest of
/// the app can call it unconditionally.
///
/// Browsers require a user gesture before the first speech synthesis, and some
/// load voices asynchronously — the first successful [speak] usually primes
/// both. All calls are wrapped so a missing/changed JS helper never crashes
/// the UI.
@JS('guardianSpeak')
external void _guardianSpeak(String text);

@JS('guardianSpeakStop')
external void _guardianSpeakStop();

class TtsService {
  bool get isSupported => kIsWeb;

  /// Speaks [text], cancelling anything currently being spoken.
  void speak(String text) {
    if (!kIsWeb || text.trim().isEmpty) return;
    try {
      _guardianSpeak(text);
    } catch (_) {
      // JS helper missing or blocked — fail silently.
    }
  }

  /// Stops any in-progress speech.
  void stop() {
    if (!kIsWeb) return;
    try {
      _guardianSpeakStop();
    } catch (_) {}
  }

  void dispose() => stop();
}
