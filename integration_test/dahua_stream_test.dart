import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvektra/main.dart';
import 'package:zvektra/multi_camera.dart';
import 'package:zvektra/playback_detection_results.dart';

class TestNvrStore extends DeviceStore {
  TestNvrStore() {
    devices = [
      const Nvr(
        id: 'fixture', name: 'RTSP fixture', manufacturer: 'Dahua',
        port: '8554', username: 'viewer', maxChannels: 8,
      ),
    ];
  }

  @override
  Future<String?> password(String id) async => 'fixture-pass';
}

Future<VlcPlayerController> waitForVideo(
  WidgetTester tester, String path, {bool requireSnapshot = true}
) async {
  for (var attempt = 0; attempt < 75; attempt++) {
    await tester.pump(const Duration(milliseconds: 400));
    final views = find.byType(VlcPlayer).evaluate();
    if (views.isEmpty) continue;
    final controller = (views.single.widget as VlcPlayer).controller;
    if (!controller.value.isInitialized || !controller.value.isPlaying) continue;
    if (!requireSnapshot && controller.value.position > Duration.zero) {
      expect(Uri.parse(controller.dataSource).path, path);
      return controller;
    }
    final bytes = await controller.takeSnapshot();
    if (bytes.isEmpty) continue;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    try {
      final frame = await codec.getNextFrame();
      try {
        final rgba = (await frame.image.toByteData())!;
        var coloredPixels = 0;
        for (var i = 0; i < rgba.lengthInBytes; i += 4) {
          final r = rgba.getUint8(i);
          final g = rgba.getUint8(i + 1);
          final b = rgba.getUint8(i + 2);
          if ((r - g).abs() > 40 || (g - b).abs() > 40) coloredPixels++;
        }
        if (coloredPixels > 20) {
          expect(Uri.parse(controller.dataSource).path, path);
          return controller;
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
  final views = find.byType(VlcPlayer).evaluate();
  final value = views.isEmpty ? null : (views.single.widget as VlcPlayer).controller.value;
  throw StateError('No authenticated RTSP frames decoded from $path '
      '(initialized: ${value?.isInitialized}, playing: ${value?.isPlaying}, '
      'position: ${value?.position})');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Release Android app detects people and plates from recorded RTSP frames',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Home(store: TestNvrStore()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('8 Cameras'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();
    expect(find.byType(CameraTile), findsNWidgets(8));
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RTSP fixture').last);
    await waitForVideo(tester, '/cam/realmonitor');
    final live = tester.widget<VlcPlayer>(find.byType(VlcPlayer)).controller;
    debugPrint('Live fixture is decoding');
    expect(find.byTooltip('Detect people and vehicles'), findsNothing);

    // Exercise real inference on a known negative, including empty model output.
    final negativeFrame = await live.takeSnapshot();
    expect(negativeFrame, isA<Uint8List>().having((b) => b.length, 'bytes', greaterThan(0)));
    const detectionChannel = MethodChannel('net.zvektra/playback_detection');
    expect(await detectionChannel.invokeListMethod<Object?>('analyze', negativeFrame), isEmpty);

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playback'));
    for (var attempt = 0; attempt < 20 && find.byType(VlcPlayer).evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(VlcPlayer), findsOneWidget, reason: 'Playback must open the VLC player');
    final playback = await waitForVideo(tester, '/cam/playback');
    debugPrint('Playback fixture is decoding');
    final query = Uri.parse(playback.dataSource).queryParameters;
    expect(query['starttime'], endsWith('_12_00_00'));
    expect(query['endtime'], endsWith('_13_00_00'));

    await tester.tap(find.byTooltip('Detect people and vehicles'));
    await tester.pump();
    expect(find.byTooltip('Stop detection'), findsOneWidget);
    PlaybackDetectionResults? results;
    for (var attempt = 0; attempt < 75; attempt++) {
      await tester.pump(const Duration(milliseconds: 400));
      final widget = find.byType(PlaybackDetectionResults).evaluate().firstOrNull?.widget;
      if (widget is PlaybackDetectionResults && widget.peopleCount > 0 && widget.plateCount > 0) {
        results = widget;
        break;
      }
    }
    if (results == null) {
      final latest = find.byType(PlaybackDetectionResults).evaluate().firstOrNull?.widget
          as PlaybackDetectionResults?;
      debugPrint('Playback state: playing=${playback.value.isPlaying}, '
          'buffering=${playback.value.isBuffering}, position=${playback.value.position}. '
          'Results: people=${latest?.peopleCount}, plates=${latest?.plateCount}.');
    }
    expect(results, isNotNull, reason: 'Both models must make positive detections on the playback stream');
    expect(find.textContaining('People: '), findsOneWidget);
    expect(find.textContaining('Vehicles: '), findsOneWidget);
    final matches = List<PlaybackDetection>.of(results!.detections);
    for (final kind in PlaybackDetectionKind.values) {
      final match = matches.firstWhere((detection) => detection.kind == kind);
      expect(match.camera, 1);
      final codec = await ui.instantiateImageCodec(match.snapshot);
      try {
        final frame = await codec.getNextFrame();
        expect(frame.image.width, inInclusiveRange(1, 320));
        expect(frame.image.height, inInclusiveRange(1, 320));
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    }

    await tester.tap(find.byTooltip('Stop detection'));
    await tester.pump();
    final stopped = tester.widget<PlaybackDetectionResults>(find.byType(PlaybackDetectionResults));
    expect(stopped.running, isFalse);
    final afterStop = stopped.detections.length;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<PlaybackDetectionResults>(find.byType(PlaybackDetectionResults)).detections,
        hasLength(afterStop));
    expect(playback.value.isPlaying, isTrue);
    const sharing = MethodChannel('net.zvektra/snapshot_share');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    bool shared = false;
    messenger.setMockMethodCallHandler(sharing, (call) async {
      if (call.method == 'available') return true;
      expect(call.method, 'whatsapp');
      expect(call.arguments, isA<Uint8List>());
      expect(find.byType(VlcPlayer), findsNothing);
      shared = true;
      return null;
    });
    await tester.tap(find.byTooltip('Share snapshot via WhatsApp').first);
    await tester.pumpAndSettle();
    expect(shared, isTrue);
    expect(find.textContaining('Tap Resume'), findsOneWidget);
    expect(find.byType(PlaybackDetectionResults), findsOneWidget);
    messenger.setMockMethodCallHandler(sharing, null);
    await tester.tap(find.byTooltip('Resume'));
    // After replacing the Android texture, require the video-only stream's
    // media clock to advance. The other test stages sample rendered pixels.
    final resumed = await waitForVideo(tester, '/cam/playback', requireSnapshot: false);
    expect(Uri.parse(resumed.dataSource).queryParameters['channel'], '1');
    expect(Uri.parse(resumed.dataSource).queryParameters['endtime'], query['endtime']);

    await tester.tap(find.byTooltip('Detect people and vehicles'));
    await tester.pump();
    expect(find.byTooltip('Stop detection'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cam 2').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop detection'), findsNothing);
    await tester.tap(find.text('Playback'));
    final second = await waitForVideo(tester, '/cam/playback');
    expect(Uri.parse(second.dataSource).queryParameters['channel'], '2');
    expect(second, isNot(same(playback)));
    debugPrint('ZVEKTRA_PLAYBACK_DETECTION_OK');
  });
}
