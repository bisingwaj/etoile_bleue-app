import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Generates and plays in-memory WAV call tones (ringback, connected, ended).
class CallSoundService {
  static final CallSoundService _instance = CallSoundService._();
  factory CallSoundService() => _instance;
  CallSoundService._();

  AudioPlayer? _ringbackPlayer;
  bool _isRingbackPlaying = false;

  static const int _sampleRate = 44100;
  static const int _bitsPerSample = 16;
  static const int _numChannels = 1;

  /// Ringback tone: 440 Hz for 1s, silence for 3s, looped.
  Future<void> startRingback() async {
    if (_isRingbackPlaying) return;
    _isRingbackPlaying = true;

    _ringbackPlayer?.dispose();
    _ringbackPlayer = AudioPlayer();
    await _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
    await _ringbackPlayer!.setVolume(0.5);

    final wav = _generateRingbackWav();
    try {
      await _ringbackPlayer!.play(BytesSource(wav));
    } catch (e) {
      debugPrint('[CallSound] Ringback play error: $e');
    }
  }

  Future<void> stopRingback() async {
    _isRingbackPlaying = false;
    await _ringbackPlayer?.stop();
    _ringbackPlayer?.dispose();
    _ringbackPlayer = null;
  }

  /// Short ascending beep when the call connects.
  Future<void> playConnected() async {
    final player = AudioPlayer();
    await player.setVolume(0.4);
    final wav = _generateToneWav(frequency: 880, durationMs: 150);
    try {
      await player.play(BytesSource(wav));
      await Future.delayed(const Duration(milliseconds: 200));
      await player.play(BytesSource(_generateToneWav(frequency: 1100, durationMs: 150)));
    } catch (e) {
      debugPrint('[CallSound] Connected play error: $e');
    }
    Future.delayed(const Duration(seconds: 1), () => player.dispose());
  }

  /// Two descending beeps when the call ends.
  /// Delayed slightly to let CallKit release the audio session on iOS.
  Future<void> playEnded() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 800));

    final player = AudioPlayer();
    await player.setVolume(0.4);
    final wav1 = _generateToneWav(frequency: 880, durationMs: 200);
    final wav2 = _generateToneWav(frequency: 660, durationMs: 300);
    try {
      await player.play(BytesSource(wav1));
      await Future.delayed(const Duration(milliseconds: 250));
      await player.play(BytesSource(wav2));
    } catch (e) {
      debugPrint('[CallSound] Ended play error (non-fatal): $e');
    }
    Future.delayed(const Duration(seconds: 1), () => player.dispose());
  }

  /// Ringback pattern: 1s tone at 440 Hz + 3s silence = 4s total
  Uint8List _generateRingbackWav() {
    final toneSamples = _sampleRate; // 1 second
    final silenceSamples = _sampleRate * 3; // 3 seconds
    final totalSamples = toneSamples + silenceSamples;
    final samples = Int16List(totalSamples);

    for (int i = 0; i < toneSamples; i++) {
      final t = i / _sampleRate;
      // Blend 440Hz + 480Hz for a standard ringback feel
      final value = (sin(2 * pi * 440 * t) * 0.5 + sin(2 * pi * 480 * t) * 0.3) * 16000;
      samples[i] = value.toInt().clamp(-32768, 32767);
    }

    return _wrapInWav(samples);
  }

  Uint8List _generateToneWav({required double frequency, required int durationMs}) {
    final numSamples = (_sampleRate * durationMs / 1000).round();
    final samples = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      // Fade in/out to avoid clicks (10ms ramp)
      final rampSamples = (_sampleRate * 0.01).round();
      double envelope = 1.0;
      if (i < rampSamples) envelope = i / rampSamples;
      if (i > numSamples - rampSamples) envelope = (numSamples - i) / rampSamples;

      final value = sin(2 * pi * frequency * t) * 20000 * envelope;
      samples[i] = value.toInt().clamp(-32768, 32767);
    }

    return _wrapInWav(samples);
  }

  Uint8List _wrapInWav(Int16List samples) {
    final dataSize = samples.length * 2;
    final fileSize = 36 + dataSize;
    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, _numChannels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * _numChannels * _bitsPerSample ~/ 8, Endian.little);
    header.setUint16(32, _numChannels * _bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, _bitsPerSample, Endian.little);

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, samples.buffer.asUint8List());

    return wav;
  }
}
