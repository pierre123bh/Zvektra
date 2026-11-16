"""Transcribe short Zvektra voice clips behind an HTTPS reverse proxy."""
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import Request, urlopen
from uuid import uuid4

MAX_BYTES = 256 * 1024


def transcribe(audio):
    boundary = uuid4().hex
    body = bytearray()
    fields = [
        ("model", "gpt-transcribe"),
        ("prompt", "Zvektra CCTV commands in Lebanese Arabic, English or French, sometimes mixed in the same sentence."),
        ("keywords[]", "Zvektra"),
        ("keywords[]", "playback"),
        *[("languages[]", lang) for lang in ("ar", "en", "fr")],
    ]
    for field, value in fields:
        body.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"\r\n\r\n{value}\r\n'.encode())
    body.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="command.m4a"\r\nContent-Type: audio/mp4\r\n\r\n'.encode())
    body.extend(audio)
    body.extend(f"\r\n--{boundary}--\r\n".encode())
    request = Request("https://api.openai.com/v1/audio/transcriptions", data=body, headers={
        "Authorization": "Bearer " + os.environ["OPENAI_API_KEY"],
        "Content-Type": f"multipart/form-data; boundary={boundary}",
    })
    with urlopen(request, timeout=15) as response:
        result = json.load(response)
    return result["text"]


class Relay(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def do_POST(self):
        if self.path != "/transcribe":
            return self.respond(404, {"error": "Unknown route"})
        header = self.headers.get("Authorization", "").encode()
        expected = ("Bearer " + os.environ["ZVEKTRA_RELAY_TOKEN"]).encode()
        if not hmac.compare_digest(header, expected):
            return self.respond(401, {"error": "Invalid relay access token"})
        if self.headers.get_content_type() != "audio/mp4":
            return self.respond(415, {"error": "Expected an M4A clip"})
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            return self.respond(411, {"error": "Content length required"})
        if not 0 < length <= MAX_BYTES:
            return self.respond(413, {"error": "Invalid clip size"})
        try:
            audio = self.rfile.read(length)
            if len(audio) != length or audio[4:8] != b"ftyp":
                return self.respond(400, {"error": "Invalid M4A clip"})
            self.respond(200, {"text": transcribe(audio)})
        except (OSError, ValueError, KeyError):
            self.respond(502, {"error": "Transcription service unavailable"})

    def respond(self, status, result):
        body = json.dumps(result).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    if not os.environ.get("OPENAI_API_KEY") or len(os.environ.get("ZVEKTRA_RELAY_TOKEN", "")) < 32:
        raise SystemExit("Set OPENAI_API_KEY and a random ZVEKTRA_RELAY_TOKEN of at least 32 characters")
    HTTPServer(("127.0.0.1", 8787), Relay).serve_forever()
