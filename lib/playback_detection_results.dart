import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final int peopleCount;
  final int plateCount;
  final bool running;
  const PlaybackDetectionResults({
    super.key,
    required this.detections,
    required this.peopleCount,
    required this.plateCount,
    required this.running,
  });

  Future<void> _shareSnapshot(BuildContext context, Uint8List snapshot) async {
    const share = MethodChannel('net.zvektra/snapshot_share');
    try {
      await share.invokeMethod<void>('whatsapp', snapshot);
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.code == 'WHATSAPP_UNAVAILABLE'
            ? 'Install WhatsApp or WhatsApp Business to share this snapshot.'
            : 'Could not share this snapshot.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            const Icon(Icons.person_outline, size: 18),
            Text(' People: $peopleCount'),
            const SizedBox(width: 16),
            const Icon(Icons.directions_car_outlined, size: 18),
            Text(' Vehicles: $plateCount'),
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
                final detection = detections[detections.length - 1 - index];
                return Tooltip(
                  message: 'Share snapshot via WhatsApp',
                  child: InkWell(
                    onTap: () => _shareSnapshot(context, detection.snapshot),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(children: [
                    SizedBox(
                      width: 112, height: 76,
                      child: Image.memory(detection.snapshot, fit: BoxFit.contain),
                    ),
                    Text(
                      '${detection.kind == PlaybackDetectionKind.person ? 'Person' : 'Vehicle'} '
                      '${TimeOfDay.fromDateTime(detection.timestamp).format(context)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
