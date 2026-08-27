import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundFeedback {
  SoundFeedback._();

  static const int _sampleRate = 44100;

  static final AudioPlayer _player = AudioPlayer();
  static bool _configured = false;

  static Future<void> ensureConfigured() async {
    if (_configured) return;
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(
        respectSilence: false,
        stayAwake: false,
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build(),
    );
    _configured = true;
  }

  static Future<void> success() async {
    await ensureConfigured();
    unawaited(HapticFeedback.lightImpact());
    await _play(_tone(1250, 90));
  }

  static Future<void> operation() async {
    await ensureConfigured();
    unawaited(HapticFeedback.mediumImpact());
    await _play(_tone(1550, 70));
  }

  static Future<void> lowStock() async {
    await ensureConfigured();
    unawaited(HapticFeedback.heavyImpact());
    await _play(_tone(880, 140));
    await Future<void>.delayed(const Duration(milliseconds: 110));
    unawaited(HapticFeedback.heavyImpact());
    await _play(_tone(620, 220));
  }

  static Future<void> error() async {
    await ensureConfigured();
    unawaited(HapticFeedback.heavyImpact());
    await _play(_tone(280, 220));
  }

  static Future<void> _play(Uint8List bytes) async {
    try {
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {}
  }

  static Uint8List _tone(
    double frequencyHz,
    int durationMs, {
    double volume = 0.7,
  }) {
    final sampleCount = (_sampleRate * durationMs / 1000).round();
    const bytesPerSample = 2;
    final dataSize = sampleCount * bytesPerSample;
    final buffer = ByteData(44 + dataSize);

    void writeUint32(int offset, int value) {
      buffer.setUint8(offset, value & 0xff);
      buffer.setUint8(offset + 1, (value >> 8) & 0xff);
      buffer.setUint8(offset + 2, (value >> 16) & 0xff);
      buffer.setUint8(offset + 3, (value >> 24) & 0xff);
    }

    void writeUint16(int offset, int value) {
      buffer.setUint8(offset, value & 0xff);
      buffer.setUint8(offset + 1, (value >> 8) & 0xff);
    }

    _ascii(buffer, 0, 'RIFF');
    writeUint32(4, 36 + dataSize);
    _ascii(buffer, 8, 'WAVE');
    _ascii(buffer, 12, 'fmt ');
    writeUint32(16, 16);
    writeUint16(20, 1);
    writeUint16(22, 1);
    writeUint32(24, _sampleRate);
    writeUint32(28, _sampleRate * bytesPerSample);
    writeUint16(32, bytesPerSample);
    writeUint16(34, 16);
    _ascii(buffer, 36, 'data');
    writeUint32(40, dataSize);

    final amplitude = (volume * 32767).round();
    final fadeSamples = (_sampleRate * 4 / 1000).round();

    for (var i = 0; i < sampleCount; i++) {
      final t = i / _sampleRate;
      final envelope = math.min(1.0, math.min(
        i / fadeSamples,
        (sampleCount - i) / fadeSamples,
      ));
      final value = (amplitude *
              envelope *
              math.sin(2 * math.pi * frequencyHz * t))
          .round()
          .clamp(-32768, 32767);
      writeUint16(44 + i * bytesPerSample, value);
    }

    return buffer.buffer.asUint8List();
  }

  static void _ascii(ByteData buffer, int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      buffer.setUint8(offset + i, text.codeUnitAt(i));
    }
  }
}