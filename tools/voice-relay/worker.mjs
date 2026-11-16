const maxClipBytes = 256 * 1024;

function error(status, message) {
  return Response.json({ error: message }, { status });
}

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== "/transcribe") {
      return error(404, "Unknown route");
    }
    if (request.method !== "POST") {
      return error(405, "Expected POST");
    }
    if (!env.OPENAI_API_KEY || !env.ZVEKTRA_RELAY_TOKEN || env.ZVEKTRA_RELAY_TOKEN.length < 32) {
      return error(503, "Voice relay not configured");
    }
    const encoder = new TextEncoder();
    const actual = encoder.encode(request.headers.get("Authorization") ?? "");
    const expected = encoder.encode("Bearer " + env.ZVEKTRA_RELAY_TOKEN);
    if (actual.length !== expected.length || !crypto.subtle.timingSafeEqual(actual, expected)) {
      return error(401, "Invalid relay access token");
    }
    if (request.headers.get("Content-Type")?.split(";")[0].trim() !== "audio/mp4") {
      return error(415, "Expected an M4A clip");
    }
    const length = Number(request.headers.get("Content-Length"));
    if (!Number.isInteger(length) || length < 8 || length > maxClipBytes) {
      return error(413, "Invalid clip size");
    }
    try {
      const clip = new Uint8Array(length);
      const reader = request.body.getReader();
      let offset = 0;
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (offset + value.length > length) {
          await reader.cancel();
          return error(413, "Invalid clip size");
        }
        clip.set(value, offset);
        offset += value.length;
      }
      if (offset !== length || String.fromCharCode(...clip.subarray(4, 8)) !== "ftyp") {
        return error(400, "Invalid M4A clip");
      }
      const form = new FormData();
      form.append("file", new Blob([clip], { type: "audio/mp4" }), "command.m4a");
      form.append("model", "gpt-transcribe");
      form.append("prompt", "Zvektra CCTV commands in Lebanese Arabic, English or French, sometimes mixed in the same sentence.");
      for (const word of ["Zvektra", "playback"]) form.append("keywords[]", word);
      for (const language of ["ar", "en", "fr"]) form.append("languages[]", language);
      const upstream = await fetch("https://api.openai.com/v1/audio/transcriptions", {
        method: "POST",
        headers: { Authorization: "Bearer " + env.OPENAI_API_KEY },
        body: form,
        signal: AbortSignal.timeout(15000),
      });
      if (!upstream.ok) return error(502, "Transcription service unavailable");
      const result = await upstream.json();
      if (typeof result.text !== "string") return error(502, "Invalid transcription response");
      return Response.json({ text: result.text });
    } catch {
      return error(502, "Transcription service unavailable");
    }
  },
};
