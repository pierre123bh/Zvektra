# LibVLC looks up Java classes and methods by name through JNI.
-keep class org.videolan.libvlc.** { *; }

# ONNX Runtime resolves its Java bridge and tensor classes from JNI.
-keep class ai.onnxruntime.** { *; }
