import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
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
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(height: 42, child: Row(children: [
        const SizedBox(width: 8),
        const Text('LIVE', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
        const Spacer(),
        const Text('Windows '),
        DropdownButton<int>(
          value: count,
          items: [1,2,4,6,8].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
          onChanged: (v) { if (v != null) setState(() => count = v); },
        ),
        const SizedBox(width: 8),
      ])),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final columns = count == 1 ? 1 : count == 2 ? 2 : count <= 4 ? 2 : 2;
        final rows = (count / columns).ceil();
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: (constraints.maxWidth / columns) /
                (constraints.maxHeight / rows),
            crossAxisSpacing: 4, mainAxisSpacing: 4,
          ),
          itemCount: count,
          itemBuilder: (context, i) => CameraTile(
            key: ValueKey('camera-tile-$i'), store: widget.store,
            
          ),
        );
      })),
    ]);
  }
}

class CameraTile extends StatefulWidget {
  final DeviceStore store;
  const CameraTile({super.key, required this.store});
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
    String? password;
    try { password = await widget.store.password(nvr.id); } catch (_) {}
    if (!mounted || request != generation) return;
    if (password == null || password.isEmpty) {
      setState(() => status = 'Missing NVR credentials'); return;
    }
    final url = StreamBuilderService.url(
      nvr, camera, password: password,
    );
    if (url == null) {
      setState(() => status = 'Live stream unsupported for ${nvr!.manufacturer}');
      return;
    }
    final fallback = nvr.manufacturer == 'Topcam'
        ? StreamBuilderService.url(nvr, camera, password: password, topcamFallback: true)
        : null;
    _openLive(request, url, fallback: fallback);
  }

  void _openLive(int request, String link, {String? fallback}) {
    final next = VlcPlayerController.network(
      link, hwAcc: HwAcc.auto, autoPlay: true,
      options: VlcPlayerOptions(
        rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1000)]),
      ),
    );
    bool failing = false;
    Future<void> failed(String message) async {
      if (failing) return;
      failing = true;
      timeout?.cancel();
      if (fallback == null || started) {
        setState(() => status = message);
        return;
      }
      setState(() { controller = null; status = 'Retrying Topcam live video…'; });
      await WidgetsBinding.instance.endOfFrame;
      try { await next.dispose(); } catch (_) {}
      if (mounted && request == generation) _openLive(request, fallback);
    }

    next.addListener(() {
      if (!mounted || request != generation || !identical(controller, next)) return;
      if (next.value.hasError) {
        unawaited(failed('Video failed; verify NVR, port and recording.'));
      } else if (!started && (next.value.isPlaying || next.value.position > Duration.zero)) {
        started = true;
        timeout?.cancel();
        setState(() => status = '');
      }
    });
    setState(() { controller = next; status = 'Loading video…'; });
    timeout = Timer(const Duration(seconds: 20), () {
      if (mounted && request == generation && !started) {
        unawaited(failed('No video received. Check camera and connection.'));
      }
    });
  }

  @override Widget build(BuildContext context) {
    Nvr? selected;
    for (final n in widget.store.devices) {
      if (n.id == deviceId) { selected = n; break; }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: const Color(0xFF0B1524), borderRadius: BorderRadius.circular(12), border: Border.all(color: cyan.withValues(alpha: 0.3))),
      child: Column(children: [
        SizedBox(height: 42, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6),child: Row(children: [
          Expanded(child: DropdownButton<String>(
            isExpanded: true, value: selected?.id,
            hint: const Text('NVR', style: TextStyle(fontSize: 12)),
            items: widget.store.devices.map((n) => DropdownMenuItem(
              value: n.id, child: Text(n.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (id) { setState(() { deviceId = id; camera = 1; }); unawaited(connect()); },
          )),
          SizedBox(width: 80, child: DropdownButton<int>(
            value: selected == null ? 1 : camera.clamp(1, selected.maxChannels).toInt(),
            items: List.generate(selected?.maxChannels ?? 1,
              (i) => DropdownMenuItem(value: i + 1, child: Text('Cam ${i + 1}', style: const TextStyle(fontSize: 12)))),
            onChanged: selected == null ? null : (v) {
              if (v != null) { setState(() => camera = v); unawaited(connect()); }
            },
          )),
          IconButton(icon: const Icon(Icons.refresh, size: 18), tooltip: 'Reconnect', onPressed: selected == null ? null : () => unawaited(connect())),
        ]))),
        Expanded(child: Stack(fit: StackFit.expand, children: [
          if (controller != null)
            LayoutBuilder(builder: (context, available) => VlcPlayer(
              controller: controller!,
              aspectRatio: available.maxWidth / available.maxHeight.clamp(1.0, double.infinity),
              virtualDisplay: false,
            )),
          if (status.isNotEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(8),
              child: Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
        ])),
      ]),
    );
  }
}
