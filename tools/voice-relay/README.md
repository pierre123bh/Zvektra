# Zvektra cloud voice trial

Run `server.py` on a server that can reach the OpenAI API. Set
`OPENAI_API_KEY` in the server's secret configuration and set
`ZVEKTRA_RELAY_TOKEN` to a different random secret of at least 32 characters.
Generate the relay token with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`.

Run `python3 tools/voice-relay/server.py` behind an HTTPS reverse proxy on the
same host. Forward POST requests to `/transcribe` at
`http://127.0.0.1:8787/transcribe`. Allow up to 256 KiB per request and set a
proxy response timeout of at least 20 seconds.

Build the trial APK with the relay address:

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=ZVEKTRA_VOICE_RELAY=https://voice.example.com/transcribe
```

The microphone asks for the relay token on first use and stores it in Android
secure storage. Tap the microphone again to finish the clip or wait ten
seconds. Review the returned transcript in the command field before sending
it. Cloud voice sends microphone audio to OpenAI through the relay. The
existing command parser handles execution after review.

A build without the relay address continues to use the existing Android
speech recognizer.

For GitHub Actions, create the repository Actions variable
`ZVEKTRA_VOICE_RELAY` with the same HTTPS URL, then run the Android build on
`voice/openai-transcription`. Put both secrets on the relay host only.

## Cloudflare Workers deployment

Create a Worker in the Cloudflare dashboard and replace the starter script
with `worker.mjs`. In the Worker's settings, add two secret bindings named
`OPENAI_API_KEY` and `ZVEKTRA_RELAY_TOKEN`. Deploy the Worker and use its
`https://<worker>.<account>.workers.dev/transcribe` URL for the
`ZVEKTRA_VOICE_RELAY` Actions variable. The app asks for the relay token
when first using the microphone.
