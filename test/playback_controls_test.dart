import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/main.dart';
import 'package:zvektra/zvektra_theme.dart';

class TestDeviceStore extends DeviceStore {
  @override
  Future<String?> password(String id) async => null;

  TestDeviceStore() {
    devices = [
      const Nvr(id: 'shop', name: 'Shop', manufacturer: 'Dahua',
        port: '16554', username: 'test', maxChannels: 4),
    ];
  }
}

void main() {
  testWidgets('Typed playback uses the explicit date before yesterday',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildZvektraTheme(),
      home: Scaffold(body: AssistantScreen(store: TestDeviceStore())),
    ));
    await tester.tap(find.byTooltip('Commands'));
    await tester.pump();
    await tester.enterText(find.byType(TextField),
        'play back cam2 yesterday from 12 pm to 12:06 pm November 15 2024');
    await tester.tap(find.byTooltip('Send command'));
    await tester.pumpAndSettle();

    expect(find.text('15 Nov 2024'), findsOneWidget);
  });

  testWidgets('Assistant shows single-camera playback date and time controls',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TestDeviceStore();
    await tester.pumpWidget(MaterialApp(
      theme: buildZvektraTheme(),
      home: Scaffold(body: AssistantScreen(store: store)),
    ));
    expect(find.text('Device'), findsOneWidget);
    final pickers = find.byType(OutlinedButton);
    expect(pickers, findsNWidgets(3));
    for (var index = 0; index < 3; index++) {
      final picker = pickers.at(index);
      final buttonBounds = tester.getRect(picker);
      final labelBounds = tester.getRect(find.descendant(of: picker, matching: find.byType(Text)));
      expect(buttonBounds.left, greaterThanOrEqualTo(8));
      expect(buttonBounds.right, lessThanOrEqualTo(312));
      expect(labelBounds.left, greaterThanOrEqualTo(buttonBounds.left));
      expect(labelBounds.right, lessThanOrEqualTo(buttonBounds.right));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Playback'), findsOneWidget);
    expect(find.textContaining('From '), findsOneWidget);
    expect(find.textContaining('To '), findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
  });
}
