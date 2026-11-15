import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:intl/intl.dart';
import 'main.dart';

/// Independent players: changing a tile never changes another tile.
class MultiCameraScreen extends StatefulWidget {
  final DeviceStore store;
  const MultiCameraScreen({super.key, required this.store});
  @override
  State<MultiCameraScreen> createState() => _MultiCameraScreenState();
}

class _MultiCameraScreenState extends State<MultiCameraScreen> {
  int count = 4;
  DateTime? start;
  DateTime? end;
  bool playback = false;

  Future<DateTime?> chooseDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2020), lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void startPlayback() {
    if (start == null || end == null || !end!.isAfter(start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an end date/time after the start date/time.')),
      );
      return;
    }
    setState(() => playback = true);
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM yyyy  HH:mm');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Windows'),
          DropdownButton<int>(
            value: count,
            items: [1,2,4,6,8].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
            onChanged: (v) { if (v != null) setState(() => count = v); },
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => playback = false),
            icon: const Icon(Icons.live_tv), label: const Text('Live'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await chooseDateTime(start ?? DateTime.now().subtract(const Duration(hours: 1)));
              if (result != null) setState(() { start = result; playback = false; });
            },
            icon: const Icon(Icons.calendar_today),
            label: Text(start == null ? 'From date/time' : format.format(start!)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await chooseDateTime(end ?? DateTime.now());
              if (result != null) setState(() { end = result; playback = false; });
            },
            icon: const Icon(Icons.event),
            label: Text(end == null ? 'To date/time' : format.format(end!)),
          ),
          FilledButton.icon(
            onPressed: startPlayback,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play range'),
          ),
        ]),
      ),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final columns = count == 1 ? 1 : count == 2 ? 2 : count <= 4 ? 2 : 2;
        final rows = (count / columns).ceil();
        return GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: (constraints.maxWidth / columns) /
                ((constraints.maxHeight / rows).clamp(120.0, 10000.0)),
            crossAxisSpacing: 6, mainAxisSpacing: 6,
          ),
          itemCount: count,
          itemBuilder: (context, i) => CameraTile(
            key: ValueKey('camera-tile-$i'), store: widget.store,
            playback: playback, start: start, end: end,
          ),
        );
      })),
    ]);
  }
}

class CameraTile extends StatefulWidget {
  final DeviceStore store;
  final bool playback;
  final DateTime? start;
  final DateTime? end;
  const CameraTile({super.key, required this.store, required this.playback, this.start, this.end});
  @override State<CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<CameraTile> {
  String? deviceId;
  int camera = 1;
  VlcPlayerController? controller;
  String status = 'Choose an NVR and camera';
  int generation = 0;
  Timer? timeout;
  bool started = false;

  @override void didUpdateWidget(covariant CameraTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback ||
        oldWidget.start != widget.start || oldWidget.end != widget.end) {
      if (deviceId != null) unawaited(connect());
    }
  }

  @override void dispose() {
    ++generation;
    timeout?.cancel();
    final old = controller;
    if (old != null) unawaited(old.dispose());
    super.dispose();
  }

  Future<void> connect() async {
    final request = ++generation;
    timeout?.cancel();
    final previous = controller;
    setState(() { controller = null; started = false; status = 'Connecting…'; });
    if (previous != null) {
      try { await previous.dispose(); } catch (_) {}
    }
    if (!mounted || request != generation) return;
    Nvr? nvr;
    for (final device in widget.store.devices) {
      if (device.id == deviceId) { nvr = device; break; }
    }
    if (nvr == null) { setState(() => status = 'Select an NVR'); return; }
    if (widget.playback && (widget.start == null || widget.end == null)) {
      setState(() => status = 'Select playback dates'); return;
    }
    String? password;
    try { password = await widget.store.password(nvr.id); } catch (_) {}
    if (!mounted || request != generation) return;
    if (password == null || password.isEmpty) {
      setState(() => status = 'Missing NVR credentials'); return;
    }
    final url = StreamBuilderService.url(
      nvr, camera, password: password,
      start: widget.playback ? widget.start : null,
      end: widget.playback ? widget.end : null,
    );
    if (url == null) {
      setState(() => status = 'Playback/stream unsupported for ${nvr!.manufacturer}');
      return;
    }
    final next = VlcPlayerController.network(
      url, hwAcc: HwAcc.auto, autoPlay: true,
      options: VlcPlayerOptions(
        rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1000)]),
      ),
    );
    next.addListener(() {
      if (!mounted || request != generation || !identical(controller, next)) return;
      if (next.value.hasError) {
        timeout?.cancel();
        setState(() => status = 'Video failed; verify NVR, port and recording.');
      } else if (!started && (next.value.isPlaying || next.value.position > Duration.zero)) {
        started = true;
        timeout?.cancel();
        setState(() => status = '');
      }
    });
    setState(() { controller = next; status = 'Loading video…'; });
    timeout = Timer(const Duration(seconds: 20), () {
      if (mounted && request == generation && !started) {
        setState(() => status = 'No video received. Check camera and connection.');
      }
    });
  }

  @override Widget build(BuildContext context) {
    Nvr? selected;
    for (final n in widget.store.devices) {
      if (n.id == deviceId) { selected = n; break; }
    }
    return Container(
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white24)),
      child: Column(children: [
        SizedBox(height: 44, child: Row(children: [
          Expanded(child: DropdownButton<String>(
            isExpanded: true, value: selected?.id,
            hint: const Text('NVR', style: TextStyle(fontSize: 12)),
            items: widget.store.devices.map((n) => DropdownMenuItem(
              value: n.id, child: Text(n.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (id) { setState(() { deviceId = id; camera = 1; }); unawaited(connect()); },
          )),
          SizedBox(width: 80, child: DropdownButton<int>(
            value: selected == null ? 1 : camera.clamp(1, selected.maxChannels),
            items: List.generate(selected?.maxChannels ?? 1,
              (i) => DropdownMenuItem(value: i + 1, child: Text('Cam ${i + 1}', style: const TextStyle(fontSize: 12)))),
            onChanged: selected == null ? null : (v) {
              if (v != null) { setState(() => camera = v); unawaited(connect()); }
            },
          )),
          IconButton(icon: const Icon(Icons.refresh, size: 18), tooltip: 'Reconnect', onPressed: selected == null ? null : () => unawaited(connect())),
        ])),
        Expanded(child: Stack(fit: StackFit.expand, children: [
          if (controller != null)
            VlcPlayer(controller: controller!, aspectRatio: 16 / 9, virtualDisplay: false),
          if (status.isNotEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(8),
              child: Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
        ])),
      ]),
    );
  }
}
