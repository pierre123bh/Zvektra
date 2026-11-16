import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class CloudVoice {
  static const _endpoint = String.fromEnvironment('ZVEKTRA_VOICE_RELAY');
  static final uri = Uri.tryParse(_endpoint);
  static bool get enabled =>
      uri?.scheme == 'https' && uri!.host.isNotEmpty && uri!.userInfo.isEmpty;
  static const recorder = MethodChannel('net.zvektra/voice_clip');

  static Future<String> transcribe(Uint8List clip, String token) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.postUrl(uri!);
        request.followRedirects = false;
        request.headers
          ..contentType = ContentType('audio', 'mp4')
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.contentLength = clip.length;
        request.add(clip);
        final response = await request.close();
        if (response.statusCode == HttpStatus.unauthorized) {
          throw PlatformException(code: 'RELAY_TOKEN');
        }
        if (response.statusCode != HttpStatus.ok) {
          throw const HttpException('Transcription service unavailable');
        }
        final result = jsonDecode(await utf8.decoder.bind(response).join());
        final transcript = (result['text'] as String).trim();
        if (transcript.isEmpty) throw const FormatException('No speech detected');
        return transcript;
      })().timeout(const Duration(seconds: 25));
    } finally {
      client.close(force: true);
    }
  }
}
