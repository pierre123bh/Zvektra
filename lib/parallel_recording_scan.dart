import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import 'playback_detection_results.dart';
import 'recording_analysis.dart';

List<({DateTime start, DateTime end})> parallelRecordingRanges(DateTime start, DateTime end) {
  final duration = end.difference(start).inSeconds;
  final count = (duration ~/ 20).clamp(1, 8).toInt();
  return List.generate(count, (index) => (
    start: start.add(Duration(seconds: duration * index ~/ count)),
    end: index == count - 1 ? end : start.add(Duration(seconds: duration * (index + 1) ~/ count)),
  ));
}

/// Runs independent time-range requests. Each source keeps its own player clock.
class ParallelRecordingScan extends StatefulWidget {
  const ParallelRecordingScan({
    super.key,
    required this.analysis,
    required this.source,
    required this.onUpdate,
    required this.onFinished,
    required this.onUnavailable,
  });

  final RecordingAnalysis analysis;
  final String Function(DateTime, DateTime) source;
  final VoidCallback onUpdate;
  final VoidCallback onFinished;
  final VoidCallback onUnavailable;

  @override
  State<ParallelRecordingScan> createState() => _ParallelRecordingScanState();
}

class _Segment {
  _Segment(this.start, this.end, this.player);
  final DateTime start;
  final DateTime end;
  final VlcPlayerController player;
  final idle = Stopwatch()..start();
  Duration progress = Duration.zero;
  Duration? lastSample;
  Future<void>? work;
  bool complete = false;
}

class _ParallelRecordingScanState extends State<ParallelRecordingScan> {
  static const _detection = MethodChannel('net.zvektra/playback_detection');
  late final List<_Segment> _segments;
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    final analysis = widget.analysis;
    _segments = parallelRecordingRanges(analysis.start, analysis.end).map((range) {
      final player = VlcPlayerController.network(
        widget.source(range.start, range.end),
        autoPlay: false,
        options: VlcPlayerOptions(
          rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
          advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1000)]),
        ),
      );
      player.addOnInitListener(() => unawaited(_start(player)));
      return _Segment(range.start, range.end, player);
    }).toList();
    analysis.startClock();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  Future<void> _start(VlcPlayerController player) async {
    try {
      await player.setVolume(0);
    } on Exception {
      // A recorder can provide video without audio controls.
    }
    if (_closed) return;
    try {
      await player.play();
    } on Exception {
      // A connection that never advances is handled by the segment timeout.
    }
  }

  void _tick() {
    if (_closed || !widget.analysis.running) return;
    for (final segment in _segments) {
      if (segment.complete) continue;
      final value = segment.player.value;
      final length = segment.end.difference(segment.start);
      final position = value.position;
      if (position > segment.progress) {
        segment.progress = position > length ? length : position;
        segment.idle.reset();
      }
      if (segment.progress >= length ||
          (value.isEnded && length - segment.progress <= const Duration(seconds: 1))) {
        if (segment.work != null) continue;
        segment.progress = length;
        segment.complete = true;
        unawaited(_pause(segment.player));
        continue;
      }
      if (value.hasError || value.isEnded || segment.idle.elapsed > const Duration(seconds: 15)) {
        _closed = true;
        _timer?.cancel();
        widget.onUnavailable();
        return;
      }
      final last = segment.lastSample;
      if (value.isPlaying && segment.work == null &&
          (last == null || segment.progress - last >= const Duration(seconds: 1))) {
        segment.lastSample = segment.progress;
        segment.work = _sample(segment, segment.progress);
      }
    }
    widget.analysis.advance(_segments.fold(Duration.zero, (sum, segment) => sum + segment.progress));
    widget.onUpdate();
    if (_segments.every((segment) => segment.complete)) {
      _closed = true;
      _timer?.cancel();
      widget.onFinished();
    }
  }

  Future<void> _sample(_Segment segment, Duration position) async {
    try {
      final image = await segment.player.takeSnapshot();
      if (_closed || !widget.analysis.running || image.isEmpty) return;
      final results = await _detection.invokeListMethod<Map<Object?, Object?>>('analyze', image);
      if (_closed || !widget.analysis.running || results == null) return;
      for (final entry in results) {
        widget.analysis.add(PlaybackDetection(
          kind: PlaybackDetectionKind.values.byName(entry['kind'] as String),
          timestamp: segment.start.add(position),
          camera: widget.analysis.camera,
          snapshot: entry['snapshot'] as Uint8List,
        ));
      }
    } on Exception {
      if (!_closed && widget.analysis.running) {
        _closed = true;
        _timer?.cancel();
        widget.onUnavailable();
      }
    } finally {
      segment.work = null;
    }
  }

  Future<void> _pause(VlcPlayerController player) async {
    try {
      await player.pause();
    } on Exception {
      // The stream may already have ended.
    }
  }

  Future<void> _disposeSegment(_Segment segment) async {
    await segment.work;
    try {
      await segment.player.dispose();
    } on Exception {
      // The platform view may detach before the controller initializes.
    }
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    for (final segment in _segments) {
      unawaited(_disposeSegment(segment));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final segment in _segments)
        VlcPlayer(key: ObjectKey(segment.player), controller: segment.player,
          aspectRatio: 16 / 9, virtualDisplay: false),
    ],
  );
}
