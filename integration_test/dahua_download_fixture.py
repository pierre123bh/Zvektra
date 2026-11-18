"""Authenticated synthetic recording for the Background Agent Android smoke test."""
import hashlib
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

RECORDING = Path(sys.argv[1]).read_bytes()
HIKVISION_RECORDING = Path(sys.argv[2]).read_bytes()
PLAYBACK_URI = "rtsp://127.0.0.1/Streaming/tracks/201/"



def md5(value):
    return hashlib.md5(value.encode()).hexdigest()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        request = urlsplit(self.path)
        query = parse_qs(request.query)
        if (
            request.path != "/cgi-bin/loadfile.cgi"
            or query.get("action") != ["startLoad"]
            or query.get("channel") != ["2"]
            or query.get("startTime") != ["2024-11-15 15:00:00"]
            or query.get("endTime") != ["2024-11-15 15:02:00"]
        ):
            self.send_error(404)
            return

        if self.authorized():
            self.reply(RECORDING, "application/octet-stream")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
        if not self.authorized():
            return
        if self.path == "/ISAPI/ContentMgmt/search" and "<trackID>201</trackID>" in body:
            result = (
                "<CMSearchResult><matchList><searchMatchItem><timeSpan>"
                "<startTime>2024-11-15T15:00:00Z</startTime>"
                "<endTime>2024-11-15T15:00:16Z</endTime></timeSpan>"
                f"<mediaSegmentDescriptor><playbackURI>{PLAYBACK_URI}</playbackURI>"
                "</mediaSegmentDescriptor></searchMatchItem></matchList></CMSearchResult>"
            )
            self.reply(result.encode(), "application/xml")
        elif self.path == "/ISAPI/ContentMgmt/download" and PLAYBACK_URI in body:
            self.reply(HIKVISION_RECORDING, "application/octet-stream")
        else:
            self.send_error(400)

    def reply(self, body, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        authorization = self.headers.get("Authorization", "")
        fields = {
            key: quoted or token
            for key, quoted, token in re.findall(r'(\w+)=(?:"([^"]*)"|([^,\s]+))', authorization)
        }
        ha1 = md5("viewer:fixture:fixture-pass")
        ha2 = md5(self.command + ":" + self.path)
        expected = md5(f"{ha1}:fixture-nonce:00000001:{fields.get('cnonce')}:auth:{ha2}")
        if (
            authorization.startswith("Digest ")
            and fields.get("username") == "viewer"
            and fields.get("uri") == self.path
            and fields.get("response") == expected
        ):
            return True
        self.send_response(401)
        self.send_header(
            "WWW-Authenticate",
            'Digest realm="fixture", nonce="fixture-nonce", algorithm=MD5, qop="auth"',
        )
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False


HTTPServer(("127.0.0.1", 8085), Handler).serve_forever()
