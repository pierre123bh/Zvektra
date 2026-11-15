#include <android/asset_manager_jni.h>
#include <jni.h>
#include <algorithm>
#include <memory>
#include <string>
#include <thread>
#include <vector>
#include "whisper.h"

namespace {
size_t read_asset(void *context, void *buffer, size_t length) {
    auto *asset = static_cast<AAsset *>(context);
    auto *bytes = static_cast<char *>(buffer);
    size_t total = 0;
    while (total < length) {
        const int count = AAsset_read(asset, bytes + total, length - total);
        if (count <= 0) break;
        total += static_cast<size_t>(count);
    }
    return total;
}

bool end_of_asset(void *context) {
    return AAsset_getRemainingLength64(static_cast<AAsset *>(context)) == 0;
}

void no_op_close(void *) {}
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_net_zvektra_zvektra_WhisperNative_transcribe(
    JNIEnv *env, jobject, jobject java_assets, jshortArray pcm, jint sample_count) {
    if (!pcm || sample_count < 1 || sample_count > 16000 * 12 ||
        sample_count > env->GetArrayLength(pcm)) return nullptr;

    auto *manager = AAssetManager_fromJava(env, java_assets);
    if (!manager) return nullptr;
    std::unique_ptr<AAsset, decltype(&AAsset_close)> asset(
        AAssetManager_open(manager, "whisper/ggml-tiny-q5_1.bin", AASSET_MODE_RANDOM),
        AAsset_close);
    if (!asset) return nullptr;
    whisper_model_loader loader{asset.get(), read_asset, end_of_asset, no_op_close};
    auto context_params = whisper_context_default_params();
    context_params.use_gpu = false;
    std::unique_ptr<whisper_context, decltype(&whisper_free)> context(
        whisper_init_with_params(&loader, context_params), whisper_free);
    if (!context) return nullptr;

    std::vector<jshort> samples(sample_count);
    env->GetShortArrayRegion(pcm, 0, sample_count, samples.data());
    if (env->ExceptionCheck()) return nullptr;
    std::vector<float> audio(sample_count);
    std::transform(samples.begin(), samples.end(), audio.begin(),
                   [](jshort sample) { return sample / 32768.0f; });

    auto options = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    options.language = "auto";
    options.translate = false;
    options.no_context = true;
    options.no_timestamps = true;
    options.print_progress = false;
    options.print_realtime = false;
    options.print_timestamps = false;
    options.n_threads = static_cast<int>(std::clamp(std::thread::hardware_concurrency(), 1u, 3u));
    if (whisper_full(context.get(), options, audio.data(), sample_count) != 0) return nullptr;

    std::string text;
    const int count = whisper_full_n_segments(context.get());
    for (int i = 0; i < count; ++i) {
        if (const auto *segment = whisper_full_get_segment_text(context.get(), i)) {
            text += segment;
        }
    }
    auto result = env->NewByteArray(static_cast<jsize>(text.size()));
    if (result && !text.empty()) {
        env->SetByteArrayRegion(
            result, 0, static_cast<jsize>(text.size()),
            reinterpret_cast<const jbyte *>(text.data()));
    }
    return result;
}
