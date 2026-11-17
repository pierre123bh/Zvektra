import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/camera_voice_command.dart';
import 'package:zvektra/playback_detection_results.dart';
import 'package:zvektra/recording_analysis.dart';

void main() {
  final start = DateTime(2026, 11, 15, 15);
  final end = start.add(const Duration(minutes: 5));
  final now = DateTime(2026, 11, 17);

  test('analysis intent supports English, Lebanese Arabic and a vehicle filter', () {
    for (final command in [
      'Check camera 2 on November 15 from 3 to 3:05 pm',
      'Show me what you detect on camera 2 November 15 from 3 to 3:05 pm',
      'فرجيني شو بتلقط عَ كاميرا رقم تنين، ١٥ تشرين التاني، من التلاتة للتلاتة وخمسة بعد الضهر.',
      'When did a vehicle appear on camera 2 November 15 from 3 to 3:05 pm',
    ]) {
      final parsed = parseRecordingAnalysis(command, now);
      expect(parsed?.range, (camera: 2, start: start, end: end), reason: command);
      expect(parsed?.filter, command.startsWith('When')
          ? RecordingAnalysisFilter.vehicles : RecordingAnalysisFilter.all);
    }
    expect(parseRecordingAnalysis('Camera 2 November 15 from 3 to 3:05 pm', now), isNull);
    expect(parseRecordingAnalysis('Analyze camera 2 November 15', now), isNull);
  });

  test('joins consecutive detections by category and starts a new event after a gap', () {
    final analysis = RecordingAnalysis(start, end, RecordingAnalysisFilter.all, 'test', 2);
    PlaybackDetection detection(PlaybackDetectionKind kind, int second) => PlaybackDetection(
      kind: kind, camera: 2, timestamp: start.add(Duration(seconds: second)),
      snapshot: Uint8List.fromList([second % 256]),
    );

    final first = detection(PlaybackDetectionKind.person, 4);
    analysis.add(first);
    analysis.add(detection(PlaybackDetectionKind.licensePlate, 5));
    analysis.add(detection(PlaybackDetectionKind.person, 7));
    analysis.add(detection(PlaybackDetectionKind.person, 11));
    analysis.add(detection(PlaybackDetectionKind.person, 300));
    expect(analysis.events, hasLength(3));
    expect(analysis.events.first.first, same(first));
    expect(analysis.events.first.lastSeen, start.add(const Duration(seconds: 7)));

    final vehicles = RecordingAnalysis(start, end, RecordingAnalysisFilter.vehicles, 'test', 2);
    vehicles.add(first);
    vehicles.add(detection(PlaybackDetectionKind.licensePlate, 5));
    expect(vehicles.events.single.first.kind, PlaybackDetectionKind.licensePlate);
  });
}
