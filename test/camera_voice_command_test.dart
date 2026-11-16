import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/camera_voice_command.dart';

void main() {
  final now = DateTime(2026, 11, 17, 17);
  CameraVoiceCommand? parse(String command) => parseCameraVoiceCommand(command, now);

  test('recognizes English, Lebanese and mixed live commands', () {
    for (final command in ['Show me camera two live', 'فرجيني كاميرا رقم تنين',
      'fergini kamera رقم اثنين', 'open cam2']) {
      expect(parse(command), (camera: 2, start: null, end: null), reason: command);
    }
  });

  test('uses the explicit date, camera, and time range', () {
    final expected = (camera: 2, start: DateTime(2026, 11, 15, 12),
      end: DateTime(2026, 11, 15, 12, 6));
    expect(parse('Play back cam2 yesterday from 12 pm to 12:06 pm November 15, 2026'), expected);
    expect(parse('playback camera two on November 15 2026 from twelve to twelve oh six pm'),
      isNull, reason: 'unknown clock wording must not lead to a guessed time');
    expect(parse('playback camera two on 15 November 2026 from 12 to 12:06 pm'), expected);
    expect(parse('فرجيني playback cam2 بتاريخ 2026-11-15 من 12 للـ 12 وستة بعد الضهر'), expected);
  });

  test('interprets Lebanese time and mixed commands', () {
    final expected = (camera: 2, start: DateTime(2026, 11, 16, 12),
      end: DateTime(2026, 11, 16, 12, 5));
    expect(parse('فرجيني كاميرا رقم اثنين مبارح من الساعة ١٢ للساعة ١٢ وخمسة بعد الظهر'), expected);
    expect(parse('fergini kamera رقم اثنين yesterday من 12 to 12:05 pm'), expected);
    expect(parse('playback cam2 from 12 pm to 12:05 pm yesterday'), expected);
  });

  test('asks for clarification instead of starting with incomplete or invalid details', () {
    for (final command in ['playback cam2 from 12 pm to 12:05 pm',
      'show me camera', 'cancel camera two', 'playback cam2 yesterday from 12 pm',
      'playback cam2 tomorrow from 12 pm to 12:05 pm', 'playback cam2 31 February 2026 from 12 to 13',
      'playback cam2 today from 18 to 19', 'show camera two or three']) {
      expect(parse(command), isNull, reason: command);
    }
  });
}
