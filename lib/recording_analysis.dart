import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'playback_detection_results.dart';

enum RecordingAnalysisFilter { all, people, vehicles }

class RecordingEvent {
  RecordingEvent(this.first) : lastSeen = first.timestamp;

  PlaybackDetection first;
  DateTime lastSeen;
}

/// Groups presence by category. Events are not unique people or vehicles.
class RecordingAnalysis {
  RecordingAnalysis(this.start, this.end, this.filter, this.deviceId, this.camera);

  final DateTime start;
  final DateTime end;
  final RecordingAnalysisFilter filter;
  final String deviceId;
  final int camera;
  final events = <RecordingEvent>[];
  static const _eventLimit = 200;
  static const _joinGap = Duration(seconds: 3);

  Duration position = Duration.zero;
  final idle = Stopwatch()..start();
  final _scanClock = Stopwatch();
  Duration _scanStart = Duration.zero;
  bool fastRequested = false;

  void startClock() {
    _scanStart = position;
    _scanClock.start();
  }

  double? get effectiveSpeed => _scanClock.elapsed < const Duration(seconds: 3)
      ? null : (position - _scanStart).inMilliseconds / _scanClock.elapsedMilliseconds;

  void stopClock() => _scanClock.stop();

  void restartAtNormalSpeed() {
    fastRequested = false;
    position = Duration.zero;
    _scanClock..stop()..reset();
    events.clear();
    overflow = false;
  }
  bool running = true;
  bool overflow = false;
  String? status;

  void advance(Duration next) {
    if (next <= position) return;
    position = next;
    idle.reset();
  }

  void add(PlaybackDetection detection) {
    final kind = detection.kind;
    if (detection.timestamp.isBefore(start) || !detection.timestamp.isBefore(end) ||
        (filter == RecordingAnalysisFilter.people && kind != PlaybackDetectionKind.person) ||
        (filter == RecordingAnalysisFilter.vehicles && kind != PlaybackDetectionKind.licensePlate)) {
      return;
    }
    RecordingEvent? match;
    for (var index = events.length - 1; index >= 0; index--) {
      final event = events[index];
      if (event.first.kind != kind ||
          detection.timestamp.difference(event.lastSeen) > _joinGap ||
          event.first.timestamp.difference(detection.timestamp) > _joinGap) continue;
      if (match == null) {
        match = event;
      } else {
        if (event.first.timestamp.isBefore(match.first.timestamp)) match.first = event.first;
        if (event.lastSeen.isAfter(match.lastSeen)) match.lastSeen = event.lastSeen;
        events.removeAt(index);
      }
    }
    if (match != null) {
      if (detection.timestamp.isBefore(match.first.timestamp)) match.first = detection;
      if (detection.timestamp.isAfter(match.lastSeen)) match.lastSeen = detection.timestamp;
    } else if (events.length < _eventLimit) {
      events.add(RecordingEvent(detection));
    } else {
      overflow = true;
      return;
    }
    events.sort((a, b) => a.first.timestamp.compareTo(b.first.timestamp));
  }
}

class RecordingAnalysisResults extends StatelessWidget {
  const RecordingAnalysisResults({
    super.key,
    required this.analysis,
    required this.onStop,
    required this.onClose,
    required this.onOpen,
  });

  final RecordingAnalysis analysis;
  final VoidCallback onStop;
  final VoidCallback onClose;
  final ValueChanged<DateTime> onOpen;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm:ss');
    final speed = analysis.effectiveSpeed;
    final progress = (analysis.position.inMilliseconds /
        analysis.end.difference(analysis.start).inMilliseconds).clamp(0.0, 1.0).toDouble();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(analysis.running ? 'Analyzing recording' : 'Recording analysis'),
            subtitle: Text('${DateFormat('dd MMM yyyy').format(analysis.start)} '
                '· Cam ${analysis.camera} · ${time.format(analysis.start)}–${time.format(analysis.end)}'
                '${speed == null ? '' : ' · ${speed.toStringAsFixed(1)}×'}'),
            trailing: analysis.running
                ? TextButton(onPressed: onStop, child: const Text('Stop'))
                : IconButton(tooltip: 'Close analysis', onPressed: onClose,
                    icon: const Icon(Icons.close)),
          ),
          if (analysis.running) LinearProgressIndicator(value: progress),
          if (analysis.status case final status?)
            Padding(padding: const EdgeInsets.all(8), child: Text(status)),
          if (analysis.overflow)
            const Padding(padding: EdgeInsets.all(8), child: Text('Showing the first 200 events.')),
          Expanded(
            child: analysis.events.isEmpty
                ? Center(child: Text(analysis.running ? 'Waiting for detections…' : 'No events detected.'))
                : ListView.builder(
                    itemCount: analysis.events.length,
                    itemBuilder: (context, index) {
                      final event = analysis.events[index];
                      final detection = event.first;
                      final first = time.format(detection.timestamp);
                      final last = time.format(event.lastSeen);
                      final label = detection.kind == PlaybackDetectionKind.person
                          ? 'Person detected' : 'Vehicle detected';
                      return ListTile(
                        leading: SizedBox(width: 64, height: 44,
                          child: Image.memory(detection.snapshot, fit: BoxFit.contain)),
                        title: Text(label),
                        subtitle: Text(first == last ? first : '$first–$last'),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () => onOpen(detection.timestamp),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
