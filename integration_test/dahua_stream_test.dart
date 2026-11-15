
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvektra/main.dart';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dahua live and playback routes both decode actual RTSP frames',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: AssistantScreen(store: TestNvrStore())),
    ));
    await tester.pumpAndSettle();

    final list = find.descendant(
      of: find.byType(ListView), matching: find.byType(Scrollable),
    ).first;
    for (final mode in ['Live', 'Playback']) {
      final button = find.text(mode);
      await tester.scrollUntilVisible(button, 100, scrollable: list);
      await tester.tap(button);
      bool decoded = false;
      String status = '';
      for (var attempt = 0; attempt < 125; attempt++) {
        await tester.pump(const Duration(milliseconds: 400));
        final cards = find.byType(Card).evaluate();
        if (cards.isNotEmpty) {
          final labels = find.descendant(
            of: find.byType(Card).first, matching: find.byType(Text),
          ).evaluate();
          if (labels.isNotEmpty) status = (labels.first.widget as Text).data ?? '';
        }
        final video = find.byType(VlcPlayer).evaluate();
        if (video.isEmpty) continue;
        final controller = (video.single.widget as VlcPlayer).controller;
        if (controller.value.isPlaying && !controller.value.size.isEmpty) {
          decoded = true;
          final data = controller.dataSource;
          final path = Uri.parse(data).path;
          expect(path, mode == 'Live' ? '/cam/realmonitor' : '/cam/playback');
          break;
        }
      }
      expect(decoded, isTrue, reason: '$mode fixture did not decode: $status');
    }
  });
}
