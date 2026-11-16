import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A detection from an actual analyzed playback frame, never a placeholder.
enum PlaybackDetectionKind { person, licensePlate }

class PlaybackDetection {
  final PlaybackDetectionKind kind;
  final DateTime timestamp;
  final int camera;
  final Uint8List snapshot;
  const PlaybackDetection({
    required this.kind,
    required this.timestamp,
    required this.camera,
    required this.snapshot,
  });
}

/// Displays only verified detector outputs. Repeated appearances count separately.
class PlaybackDetectionResults extends StatelessWidget {
  final List<PlaybackDetection> detections;
  final bool running;
  const PlaybackDetectionResults({
    super.key,
    required this.detections,
    required this.running,
  });

  @override
  Widget build(BuildContext context) {
    final people = detections.where((d) => d.kind == PlaybackDetectionKind.person).toList();
    final plates = detections.where((d) => d.kind == PlaybackDetectionKind.licensePlate).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            const Icon(Icons.person_outline, size: 18),
            Text(' People: ${people.length}'),
            const SizedBox(width: 16),
            const Icon(Icons.directions_car_outlined, size: 18),
            Text(' Plates: ${plates.length}'),
            const Spacer(),
            if (running) const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
        if (detections.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No detections yet.'),
          )
        else
          SizedBox(
            height: 108,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: detections.length,
              itemBuilder: (context, index) {
                final detection = detections[index];
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(children: [
                    SizedBox(
                      width: 112, height: 76,
                      child: Image.memory(detection.snapshot, fit: BoxFit.contain),
                    ),
                    Text(
                      '${detection.kind == PlaybackDetectionKind.person ? 'Person' : 'Plate'} '
                      '${TimeOfDay.fromDateTime(detection.timestamp).format(context)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ]),
                );
              },
            ),
          ),
      ],
    );
  }
}
