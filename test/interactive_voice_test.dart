import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zvektra/main.dart';

class _VoiceDeviceStore extends DeviceStore {
  _VoiceDeviceStore() {
    devices = [
      const Nvr(id: 'fixture', name: 'Fixture', manufacturer: 'Dahua',
          port: '16554', username: 'tester', maxChannels: 8),
    ];
  }

  int connectionAttempts = 0;
  @override
  Future<String?> password(String id) async {
    connectionAttempts++;
    return null;
  }
}

void main() {
  const voice = MethodChannel('net.zvektra/speech');
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  const codec = StandardMethodCodec();

  testWidgets('prompts, listens and acts in the selected language', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(voice, (call) async {
      calls.add(call);
      return call.method == 'speak' ? true : null;
    });
    messenger.setMockMethodCallHandler(permission, (call) async {
      return {for (final int id in call.arguments as List) id: 1};
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(voice, null);
      messenger.setMockMethodCallHandler(permission, null);
    });

    Future<void> recognized(String text, double confidence) async {
      final ByteData message = codec.encodeMethodCall(
        MethodCall('recognized', {'text': text, 'confidence': confidence}),
      );
      await messenger.handlePlatformMessage(voice.name, message, (_) {});
      await tester.pump();
    }

    final store = _VoiceDeviceStore();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AssistantScreen(store: store))));
    await tester.tap(find.byTooltip('Voice'));
    await tester.pump();
    expect(calls.map((call) => call.method), ['speak', 'start']);
    expect(calls.first.arguments, {'text': 'شو بدّك فرجيك؟', 'locale': 'ar-LB'});
    expect(calls.last.arguments, {'locale': 'ar-LB'});
    await recognized('فرجيني كاميرا تنين', 0.95);
    expect(find.text('Cam 2'), findsOneWidget);
    expect(store.connectionAttempts, 1);
    expect(calls.last.arguments['locale'], 'ar-LB');

    await tester.tap(find.byTooltip('Voice language · Lebanese Arabic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voice'));
    await tester.pump();
    expect(calls.last.arguments, {'locale': 'en-US'});
    await recognized('show camera three', 0.2);
    expect(store.connectionAttempts, 1);
    expect(calls.last.arguments['text'], startsWith('Please repeat'));

    await tester.tap(find.byTooltip('Voice'));
    await tester.pump();
    await recognized('playback camera three November 15 2024 from 12 pm to 12:06 pm', 0.95);
    expect(find.text('Cam 3'), findsOneWidget);
    expect(find.text('15 Nov 2024'), findsOneWidget);
    expect(store.connectionAttempts, 2);
  });
}
