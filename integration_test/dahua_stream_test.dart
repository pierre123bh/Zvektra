import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:zvektra/main.dart';
import 'package:zvektra/zvektra_theme.dart';
import 'package:zvektra/multi_camera.dart';
import 'package:zvektra/playback_detection_results.dart';
import 'package:zvektra/recording_analysis.dart';

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

Future<VlcPlayerController> waitForVideo(WidgetTester tester, String path,
    {bool acceptMonochrome = false}) async {
  for (var attempt = 0; attempt < 75; attempt++) {
    await tester.pump(const Duration(milliseconds: 400));
    final views = find.byType(VlcPlayer).evaluate();
    if (views.isEmpty) continue;
    final controller = (views.single.widget as VlcPlayer).controller;
    if (!controller.value.isInitialized || !controller.value.isPlaying) continue;
    final bytes = await controller.takeSnapshot();
    if (bytes.isEmpty) continue;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    try {
      final frame = await codec.getNextFrame();
      try {
        final rgba = (await frame.image.toByteData())!;
        var coloredPixels = 0;
        var midtonePixels = 0;
        for (var i = 0; i < rgba.lengthInBytes; i += 4) {
          final r = rgba.getUint8(i);
          final g = rgba.getUint8(i + 1);
          final b = rgba.getUint8(i + 2);
          if (r + g + b > 120 && r + g + b < 690) midtonePixels++;
          if ((r - g).abs() > 40 || (g - b).abs() > 40) coloredPixels++;
        }
        if (coloredPixels > 20 || (acceptMonochrome && midtonePixels > 20)) {
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
      theme: buildZvektraTheme(),
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
    expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);
    // Select a past interval explicitly so the fixture also runs before 1 PM.
    await tester.tap(find.byTooltip('Commands'));
    await tester.pump();
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        'playback camera 1 yesterday from 12 pm to 1 pm';
    tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Send command')).onPressed!();
    await tester.tap(find.byTooltip('Commands'));
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

    await tester.tap(find.byTooltip('Save photo to gallery').first);
    final saved = find.text('Photo saved to your gallery.');
    for (var attempt = 0; attempt < 30 && saved.evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(saved, findsOneWidget);
    expect(tester.widget<VlcPlayer>(find.byType(VlcPlayer)).controller, same(playback));
    expect(playback.value.isPlaying, isTrue);
    expect(find.byTooltip('Stop detection'), findsOneWidget);

    var backgrounded = false;
    final testLifecycle = AppLifecycleListener(onPause: () {
      backgrounded = true;
      debugPrint('ZVEKTRA_BACKGROUND_CONFIRMED');
    });
    debugPrint('ZVEKTRA_READY_FOR_BACKGROUND');
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (backgrounded && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) break;
    }
    testLifecycle.dispose();
    expect(backgrounded, isTrue);
    final restored = await waitForVideo(tester, '/cam/playback', acceptMonochrome: true);
    expect(restored, isNot(same(playback)));
    expect(Uri.parse(restored.dataSource).queryParameters['endtime'], query['endtime']);
    expect(find.byTooltip('Stop detection'), findsOneWidget);
    expect(tester.widget<PlaybackDetectionResults>(find.byType(PlaybackDetectionResults))
        .detections.length, greaterThanOrEqualTo(matches.length));

    await tester.tap(find.byTooltip('Stop detection'));
    await tester.pump();
    final stopped = tester.widget<PlaybackDetectionResults>(find.byType(PlaybackDetectionResults));
    expect(stopped.running, isFalse);
    final afterStop = stopped.detections.length;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<PlaybackDetectionResults>(find.byType(PlaybackDetectionResults)).detections,
        hasLength(afterStop));
    expect(restored.value.isPlaying, isTrue);
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
    expect(second, isNot(same(restored)));
    await tester.tap(find.byTooltip('Commands'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    // Inject the command without opening the emulator's soft keyboard.
    field.controller!.text = 'Check camera 2 on November 15 2024 from 3 to 3:05 pm';
    final send = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Send command'));
    send.onPressed!();
    final analysisFinder = find.byType(RecordingAnalysisResults);
    for (var attempt = 0; attempt < 25 && analysisFinder.evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(analysisFinder, findsOneWidget, reason: tester.widgetList<Text>(find.byType(Text))
        .map((text) => text.data).whereType<String>().join(' | '));
    expect(find.text('Analyzing recording'), findsOneWidget);
    expect(find.text('Save clip'), findsNothing);
    for (var attempt = 0; attempt < 90; attempt++) {
      await tester.pump(const Duration(milliseconds: 400));
      final timeline = tester.widget<RecordingAnalysisResults>(analysisFinder).analysis;
      if (timeline.events.map((event) => event.first.kind).toSet().length == 2) break;
    }
    final analysis = tester.widget<RecordingAnalysisResults>(analysisFinder).analysis;
    expect(analysis.events.map((event) => event.first.kind).toSet(),
        containsAll(PlaybackDetectionKind.values));
    expect(analysis.start, DateTime(2024, 11, 15, 15));
    expect(analysis.end, DateTime(2024, 11, 15, 15, 5));
    expect(analysis.camera, 2);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.textContaining('Results are partial'), findsOneWidget);
    expect(find.text('Save clip'), findsNothing);
    await tester.tap(find.byTooltip('Recording analysis results'));
    await tester.pump();
    final saveClip = find.ancestor(of: find.text('Save clip').first,
        matching: find.byWidgetPredicate((widget) => widget is TextButton)).first;
    await tester.ensureVisible(saveClip);
    await tester.pump(const Duration(milliseconds: 300));
    final exportButton = tester.widget<TextButton>(saveClip);
    expect(exportButton.onPressed, isNotNull);
    exportButton.onPressed!();
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(tester.widget<RecordingAnalysisResults>(analysisFinder).savingClips,
        hasLength(1));
    final clipSaved = find.textContaining('saved to your gallery.');
    for (var attempt = 0; attempt < 105 && clipSaved.evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 400));
      if (find.text('The recorder did not return a playable video clip.').evaluate().isNotEmpty) break;
    }
    expect(clipSaved, findsOneWidget, reason: 'Export the RTSP interval as a playable MP4 in MediaStore');
    final event = analysis.events.first.first;
    await tester.tap(find.text(event.kind == PlaybackDetectionKind.person
        ? 'Person detected' : 'Vehicle detected').first);
    final review = await waitForVideo(tester, '/cam/playback', acceptMonochrome: true);
    expect(Uri.parse(review.dataSource).queryParameters['channel'], '2');
    expect(Uri.parse(review.dataSource).queryParameters['endtime'], endsWith('_15_05_00'));
    expect(find.byTooltip('Recording analysis results'), findsOneWidget);
    const agent = MethodChannel('net.zvektra/background_agent');
    final agentRange = {
      'sources': [review.dataSource],
      'start': DateTime(2024, 11, 15, 15).millisecondsSinceEpoch,
      'end': DateTime(2024, 11, 15, 15, 0, 16).millisecondsSinceEpoch,
      'camera': 2,
    };
    expect(await agent.invokeMethod<bool>('start', agentRange), isTrue);
    expect(await agent.invokeMethod<bool>('start', agentRange), isFalse);
    expect((await agent.invokeMapMethod<String, dynamic>('status'))?['running'], isTrue);
    debugPrint('ZVEKTRA_BACKGROUND_AGENT_STARTED');

    Map<String, dynamic>? agentStatus;
    for (var attempt = 0; attempt < 150; attempt++) {
      await tester.pump(const Duration(milliseconds: 400));
      agentStatus = await agent.invokeMapMethod<String, dynamic>('status');
      if (agentStatus?['running'] == false) break;
    }
    expect(agentStatus?['running'], isFalse);
    expect(RegExp(r'Background analysis finished\. [2-9] clips saved\.')
        .hasMatch(agentStatus?['message'] as String? ?? ''), isTrue,
        reason: 'The native service must detect events and publish clips while Flutter is offscreen');
    expect(agentStatus?['message'], contains('Zvektra Port 1. Read'));
    // The RTSP port is intentionally unreachable for this second run.
    final downloadSource = Uri.parse(review.dataSource).replace(port: 8555);
    expect(await agent.invokeMethod<bool>('start', {
      ...agentRange,
      'sources': [downloadSource.toString()],
      'end': DateTime(2024, 11, 15, 15, 2).millisecondsSinceEpoch,
      'downloadPort': 8085,
    }), isTrue);
    for (var attempt = 0; attempt < 275; attempt++) {
      await tester.pump(const Duration(milliseconds: 400));
      agentStatus = await agent.invokeMapMethod<String, dynamic>('status');
      if (agentStatus?['running'] == false) break;
    }
    expect(agentStatus?['running'], isFalse);
    expect(agentStatus?['message'], predicate<String>((message) =>
        RegExp(r'Background analysis finished\. [1-9][0-9]* clips saved\.').hasMatch(message)),
        reason: 'Port 2 must download, analyze and save clips without RTSP');
    final result = agentStatus?['message'] as String;
    debugPrint(result);
    final readSeconds = RegExp(r'Zvektra Port 2\. Read ([0-9.]+)s').firstMatch(result);
    expect(readSeconds, isNotNull, reason: 'A two-minute DAV must finish through Port 2');
    expect(double.parse(readSeconds!.group(1)!), lessThan(20),
        reason: 'Local DAV remux must read faster than RTSP playback');
    expect(await agent.invokeMethod<bool>('start', {
      ...agentRange,
      'sources': [downloadSource.toString()],
      'recorderFamily': 'Hikvision',
      'downloadPort': 8085,
    }), isTrue);
    for (var attempt = 0; attempt < 125; attempt++) {
      await tester.pump(const Duration(milliseconds: 400));
      agentStatus = await agent.invokeMapMethod<String, dynamic>('status');
      if (agentStatus?['running'] == false) break;
    }
    expect(agentStatus?['running'], isFalse);
    expect(agentStatus?['message'], contains('Background analysis finished.'));
    expect(agentStatus?['message'], contains('Zvektra Port 2. Read'));
    debugPrint('ZVEKTRA_PLAYBACK_DETECTION_OK');
  });
}
