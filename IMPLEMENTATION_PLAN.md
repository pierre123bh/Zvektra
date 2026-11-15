# Native integrations still required

1. **Whisper offline**: bundle a licensed GGML Whisper model, integrate whisper.cpp via Android NDK/JNI or a vetted Flutter plugin; record microphone PCM with permission; transcribe on-device; fill the existing editable command box; execute only after user confirms.
2. **People detection**: acquire decoded LibVLC frames via a native Android bridge or a parallel decoder, run an appropriately licensed TFLite/ONNX person detector on sampled frames, and record timestamped appearance detections. A generic Flutter VLC widget does not expose this pipeline.
3. **Snapshots**: crop or capture decoded frames with person bounding boxes, save securely in app storage and index in a local database. Duplicates are allowed; counts must be labeled appearances.
4. **Performance**: benchmark combined 1080p RTSP video+audio decoding, Whisper and detection on the actual phone, avoiding simultaneous heavy inference where possible.
5. **Manufacturer adapters**: only Dahua playback is verified. Other vendor recording URLs must be tested against actual NVR models.
