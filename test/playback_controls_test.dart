import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/main.dart';

class TestDeviceStore extends DeviceStore {
  TestDeviceStore() {
    devices = [
      const Nvr(id: 'shop', name: 'Shop', manufacturer: 'Dahua',
        port: '16554', username: 'test', maxChannels: 4),
    ];
  }
}

void main() {
  testWidgets('Assistant shows single-camera playback date and time controls',
      (tester) async {
    final store = TestDeviceStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AssistantScreen(store: store)),
    ));
    expect(find.text('Playback'), findsOneWidget);
    expect(find.textContaining('From '), findsOneWidget);
    expect(find.textContaining('To '), findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
  });
}
