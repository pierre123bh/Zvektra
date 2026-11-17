import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'playback_detection_results.dart';

enum RecordingAnalysisFilter { all, people, vehicles }

class RecordingEvent {
  RecordingEvent(this.first) : lastSeen = first.timestamp;

  final PlaybackDetection first;
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
  final _recent = <PlaybackDetectionKind, RecordingEvent>{};
  static const _eventLimit = 200;
  static const _joinGap = Duration(seconds: 3);

  Duration position = Duration.zero;
  final idle = Stopwatch()..start();
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
    final previous = _recent[kind];
    if (previous != null) {
      final gap = detection.timestamp.difference(previous.lastSeen);
      if (gap.isNegative) return;
      if (gap <= _joinGap) {
        previous.lastSeen = detection.timestamp;
        return;
      }
    }
    if (events.length >= _eventLimit) {
      overflow = true;
      return;
    }
    final event = RecordingEvent(detection);
    _recent[kind] = event;
    events.add(event);
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
                '· Cam ${analysis.camera} · ${time.format(analysis.start)}–${time.format(analysis.end)}'),
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
