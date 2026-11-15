package net.zvektra.zvektra;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class WhisperInferenceTest {
    @Test
    public void transcribesARealAudioSampleWithTheBundledModel() throws Exception {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        byte[] bytes;
        try (InputStream audio = instrumentation.getContext().getAssets().open("whisper-jfk.pcm");
             ByteArrayOutputStream buffer = new ByteArrayOutputStream()) {
            byte[] page = new byte[4096];
            for (int count; (count = audio.read(page)) != -1;) {
                buffer.write(page, 0, count);
            }
            bytes = buffer.toByteArray();
        }
        short[] pcm = new short[bytes.length / 2];
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(pcm);
        byte[] result = WhisperNative.INSTANCE.transcribe(
                instrumentation.getTargetContext().getAssets(), pcm, pcm.length);
        assertNotNull(result);
        String text = new String(result, StandardCharsets.UTF_8).toLowerCase(Locale.ROOT);
        assertTrue("Whisper transcription: " + text,
                text.contains("ask not") && text.contains("country"));
    }
}
